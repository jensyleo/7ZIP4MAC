import Foundation

/// Abstraction over the 7-Zip engine used by the services.
///
/// This is the seam the architecture requires between the services and the
/// engine: services depend on this protocol, never on `Process` or `7zz`
/// directly, which keeps them unit-testable with a fake implementation.
public protocol SevenZipBridge: Sendable {
    /// Lists the technical contents of an archive.
    ///
    /// - Parameters:
    ///   - url: Location of the archive file.
    ///   - password: Optional password for encrypted archives / headers.
    /// - Returns: The archive's properties and its entries.
    func list(archiveAt url: URL, password: String?) async throws -> (ArchiveProperties, [ArchiveEntry])

    /// Extracts an archive, reporting progress as it runs.
    ///
    /// - Parameters:
    ///   - request: What, where and how to extract.
    ///   - progress: Called repeatedly with the latest ``ProgressInfo``.
    func extract(
        _ request: ExtractionRequest,
        progress: @escaping @Sendable (ProgressInfo) -> Void
    ) async throws

    /// Creates an archive from the given sources, reporting progress as it runs.
    func compress(
        _ request: CompressionRequest,
        progress: @escaping @Sendable (ProgressInfo) -> Void
    ) async throws

    /// Runs the engine's built-in benchmark.
    /// - Parameter passes: Number of benchmark passes, or nil for the default.
    func benchmark(passes: Int?) async throws -> BenchmarkResult

    /// Tests the integrity of an archive. Returns true if everything is OK.
    /// Tests the integrity of an archive, or just the given entries within it
    /// when `selectedPaths` is non-empty.
    func test(archiveAt url: URL, selectedPaths: [String], password: String?) async throws -> Bool

    /// Deletes entries from an archive in place, rewriting it without them.
    func delete(archiveAt url: URL, paths: [String], password: String?) async throws

    /// Renames or moves an entry within an archive in place (changing its
    /// path renames it; changing its parent folder moves it — 7-Zip's `rn`
    /// command does both the same way).
    func rename(archiveAt url: URL, from oldPath: String, to newPath: String, password: String?) async throws
}

/// The production bridge: turns high-level requests into `7zz` invocations,
/// classifies the exit status into typed errors, and parses the output.
public struct SystemSevenZipBridge: SevenZipBridge {
    private let runner: SevenZipRunner

    public init(runner: SevenZipRunner) {
        self.runner = runner
    }

    public init(executable: SevenZipExecutable) {
        self.init(runner: SevenZipRunner(executable: executable))
    }

    public func list(
        archiveAt url: URL,
        password: String?
    ) async throws -> (ArchiveProperties, [ArchiveEntry]) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ArchiveError.archiveNotFound(path: url.path)
        }

        ArchiveLog.service.info("Listing started for \(url.lastPathComponent, privacy: .public)")

        var arguments = ["l", "-slt", "-y"]
        // Force a password value so 7-Zip fails fast instead of blocking on a
        // prompt when headers are encrypted. Never logged.
        arguments.append("-p" + (password ?? ""))
        arguments.append(url.path)

        let result = try await runner.run(arguments)

        // Exit codes: 0 = OK, 1 = warning (still usable), >= 2 = fatal.
        if result.exitCode >= 2 {
            let message = result.errorString.isEmpty ? result.outputString : result.errorString
            if Self.indicatesWrongPassword(message) {
                ArchiveLog.service.error("Listing failed: wrong password for \(url.lastPathComponent, privacy: .public)")
                throw ArchiveError.wrongPassword
            }
            if Self.indicatesUnsupportedFormat(message) {
                ArchiveLog.service.error("Listing failed: unsupported format for \(url.lastPathComponent, privacy: .public)")
                throw ArchiveError.unsupportedFormat
            }
            ArchiveLog.service.error("Listing failed (code \(result.exitCode)) for \(url.lastPathComponent, privacy: .public)")
            throw ArchiveError.operationFailed(
                code: result.exitCode,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let parsed = try ArchiveListingParser.parse(result.outputString)
        ArchiveLog.service.info("Listing finished: \(parsed.1.count, privacy: .public) entries in \(url.lastPathComponent, privacy: .public)")
        return parsed
    }

    public func extract(
        _ request: ExtractionRequest,
        progress: @escaping @Sendable (ProgressInfo) -> Void
    ) async throws {
        guard FileManager.default.fileExists(atPath: request.archiveURL.path) else {
            throw ArchiveError.archiveNotFound(path: request.archiveURL.path)
        }

        ArchiveLog.service.info("Extraction started for \(request.archiveURL.lastPathComponent, privacy: .public)")

        var arguments = [request.flattenPaths ? "e" : "x", request.archiveURL.path]
        arguments.append("-o" + request.destinationURL.path)
        arguments.append("-y")
        arguments.append("-bsp1")            // progress to stdout
        arguments.append(request.overwritePolicy.switchArgument)
        // Only pass -p when there's a real password: a bare "-p" (empty
        // string) can make 7zz block on an interactive password prompt with
        // no terminal attached (same hang the `d`/`rn` commands guard against).
        if let password = request.password, !password.isEmpty {
            arguments.append("-p" + password)
        }
        // Restrict to selected entries, if any.
        arguments.append(contentsOf: request.selectedPaths)

        let state = ProgressReportingState(
            totalBytes: request.totalUncompressedSize,
            report: progress
        )

        let (exitCode, errorData) = try await runner.stream(arguments) { chunk in
            state.consume(chunk)
        }
        state.finish()

        if Task.isCancelled {
            ArchiveLog.service.info("Extraction cancelled for \(request.archiveURL.lastPathComponent, privacy: .public)")
            throw ArchiveError.cancelled
        }

        if exitCode >= 2 {
            let message = String(decoding: errorData, as: UTF8.self)
            if Self.indicatesWrongPassword(message) {
                throw ArchiveError.wrongPassword
            }
            if Self.indicatesUnsupportedFormat(message) {
                throw ArchiveError.unsupportedFormat
            }
            ArchiveLog.service.error("Extraction failed (code \(exitCode)) for \(request.archiveURL.lastPathComponent, privacy: .public)")
            throw ArchiveError.operationFailed(
                code: exitCode,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        // Ensure the UI ends at 100%.
        progress(ProgressInfo(
            fractionCompleted: 1,
            processedBytes: request.totalUncompressedSize,
            totalBytes: request.totalUncompressedSize,
            bytesPerSecond: 0,
            estimatedTimeRemaining: 0,
            currentFile: nil
        ))
        ArchiveLog.service.info("Extraction finished for \(request.archiveURL.lastPathComponent, privacy: .public)")
    }

    public func compress(
        _ request: CompressionRequest,
        progress: @escaping @Sendable (ProgressInfo) -> Void
    ) async throws {
        guard !request.sourceURLs.isEmpty else {
            throw ArchiveError.operationFailed(code: -1, message: "No files were selected to compress.")
        }

        ArchiveLog.service.info("Compression started → \(request.destinationURL.lastPathComponent, privacy: .public)")

        var arguments = ["a", "-t" + request.format.typeArgument]
        arguments.append("-mx=\(request.level.mxValue)")
        arguments.append("-bsp1")
        arguments.append("-y")

        if request.format.supportsPassword, let password = request.password, !password.isEmpty {
            arguments.append("-p" + password)
            if request.format == .zip {
                arguments.append("-mem=AES256")
            }
            if request.format.supportsEncryptedHeaders, request.encryptFileNames {
                arguments.append("-mhe=on")
            }
        }

        if let volumeSize = request.volumeSize, volumeSize > 0 {
            arguments.append("-v\(volumeSize)b")
        }

        arguments.append(request.destinationURL.path)
        arguments.append(contentsOf: request.sourceArguments)

        let state = ProgressReportingState(
            totalBytes: request.totalSourceSize,
            report: progress
        )

        let (exitCode, errorData) = try await runner.stream(
            arguments,
            workingDirectory: request.workingDirectory
        ) { chunk in
            state.consume(chunk)
        }
        state.finish()

        if Task.isCancelled {
            // Remove a partially written archive so a cancel leaves no debris.
            try? FileManager.default.removeItem(at: request.destinationURL)
            ArchiveLog.service.info("Compression cancelled → \(request.destinationURL.lastPathComponent, privacy: .public)")
            throw ArchiveError.cancelled
        }

        if exitCode >= 2 {
            let message = String(decoding: errorData, as: UTF8.self)
            ArchiveLog.service.error("Compression failed (code \(exitCode)) → \(request.destinationURL.lastPathComponent, privacy: .public)")
            throw ArchiveError.operationFailed(
                code: exitCode,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        progress(ProgressInfo(
            fractionCompleted: 1,
            processedBytes: request.totalSourceSize,
            totalBytes: request.totalSourceSize,
            bytesPerSecond: 0,
            estimatedTimeRemaining: 0,
            currentFile: nil
        ))
        ArchiveLog.service.info("Compression finished → \(request.destinationURL.lastPathComponent, privacy: .public)")
    }

    public func benchmark(passes: Int?) async throws -> BenchmarkResult {
        ArchiveLog.service.info("Benchmark started")
        var arguments = ["b"]
        if let passes { arguments.append(String(passes)) }

        let result = try await runner.run(arguments)
        if result.exitCode >= 2 {
            let message = result.errorString.isEmpty ? result.outputString : result.errorString
            ArchiveLog.service.error("Benchmark failed (code \(result.exitCode))")
            throw ArchiveError.operationFailed(
                code: result.exitCode,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let parsed = BenchmarkParser.parse(result.outputString)
        ArchiveLog.service.info("Benchmark finished: \(parsed.totalRatingMIPS ?? 0, privacy: .public) MIPS")
        return parsed
    }

    public func test(archiveAt url: URL, selectedPaths: [String], password: String?) async throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ArchiveError.archiveNotFound(path: url.path)
        }
        ArchiveLog.service.info("Test started for \(url.lastPathComponent, privacy: .public)")
        var arguments = ["t", "-y", "-p" + (password ?? ""), url.path]
        arguments.append(contentsOf: selectedPaths)
        let result = try await runner.run(arguments)

        if result.exitCode >= 2 {
            let message = result.errorString.isEmpty ? result.outputString : result.errorString
            if Self.indicatesWrongPassword(message) { throw ArchiveError.wrongPassword }
            ArchiveLog.service.error("Test failed (code \(result.exitCode)) for \(url.lastPathComponent, privacy: .public)")
            return false
        }
        let ok = result.outputString.contains("Everything is Ok")
        ArchiveLog.service.info("Test finished: \(ok ? "OK" : "problems", privacy: .public) for \(url.lastPathComponent, privacy: .public)")
        return ok
    }

    public func delete(archiveAt url: URL, paths: [String], password: String?) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ArchiveError.archiveNotFound(path: url.path)
        }
        guard !paths.isEmpty else { return }

        ArchiveLog.service.info("Delete started for \(url.lastPathComponent, privacy: .public)")
        // Unlike list/extract/test, a bare "-p" (no password characters
        // attached) makes `d`/`rn` block waiting on an interactive password
        // prompt instead of treating it as "no password" — with no terminal
        // attached, that hangs until 7zz gives up ("Break signaled", exit 255).
        // So the flag is only included when there's an actual password.
        var arguments = ["d", url.path, "-y"]
        if let password, !password.isEmpty { arguments.append("-p" + password) }
        arguments.append(contentsOf: paths)
        let result = try await runner.run(arguments)

        if result.exitCode >= 2 {
            let message = result.errorString.isEmpty ? result.outputString : result.errorString
            if Self.indicatesWrongPassword(message) { throw ArchiveError.wrongPassword }
            ArchiveLog.service.error("Delete failed (code \(result.exitCode)) for \(url.lastPathComponent, privacy: .public)")
            throw ArchiveError.operationFailed(
                code: result.exitCode,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        ArchiveLog.service.info("Delete finished for \(url.lastPathComponent, privacy: .public)")
    }

    public func rename(archiveAt url: URL, from oldPath: String, to newPath: String, password: String?) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ArchiveError.archiveNotFound(path: url.path)
        }

        ArchiveLog.service.info("Rename started for \(url.lastPathComponent, privacy: .public)")
        var arguments = ["rn", url.path, "-y"]
        if let password, !password.isEmpty { arguments.append("-p" + password) }
        arguments.append(contentsOf: [oldPath, newPath])
        let result = try await runner.run(arguments)

        if result.exitCode >= 2 {
            let message = result.errorString.isEmpty ? result.outputString : result.errorString
            if Self.indicatesWrongPassword(message) { throw ArchiveError.wrongPassword }
            ArchiveLog.service.error("Rename failed (code \(result.exitCode)) for \(url.lastPathComponent, privacy: .public)")
            throw ArchiveError.operationFailed(
                code: result.exitCode,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        ArchiveLog.service.info("Rename finished for \(url.lastPathComponent, privacy: .public)")
    }

    // MARK: - Error classification

    private static func indicatesWrongPassword(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("wrong password") || lowered.contains("cannot open encrypted")
    }

    private static func indicatesUnsupportedFormat(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("cannot open the file as archive")
            || lowered.contains("is not supported archive")
            || lowered.contains("unsupported")
    }
}
