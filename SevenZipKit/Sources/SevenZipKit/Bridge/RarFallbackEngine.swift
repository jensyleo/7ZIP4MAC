import Foundation

/// Secondary engine (`lsar` + `unar`, from The Unarchiver) used only for
/// multi-part RAR sets that 7-Zip cannot handle — a volume that is 0 bytes
/// makes 7-Zip refuse the whole set, and a missing one stops its listing at
/// the gap. `lsar`/`unar` read each volume's headers independently, so
/// everything outside the damaged volumes stays readable.
public struct RarFallbackEngine: Sendable {
    public let lister: SevenZipExecutable
    public let extractor: SevenZipExecutable

    public init(lister: SevenZipExecutable, extractor: SevenZipExecutable) {
        self.lister = lister
        self.extractor = extractor
    }

    // MARK: - Listing

    func list(archiveAt url: URL, password: String?) async throws -> (ArchiveProperties, [ArchiveEntry]) {
        var arguments = ["-j"]
        if let password, !password.isEmpty { arguments += ["-p", password] }
        arguments.append(url.path)
        let result = try await SevenZipRunner(executable: lister).run(arguments)
        guard result.exitCode == 0 else {
            throw ArchiveError.operationFailed(
                code: result.exitCode,
                message: result.diagnosticMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return try Self.parseListing(result.standardOutput)
    }

    static func parseListing(_ data: Data) throws -> (ArchiveProperties, [ArchiveEntry]) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["lsarContents"] as? [[String: Any]]
        else {
            throw ArchiveError.parsingFailed(reason: "The fallback engine returned an unreadable listing.")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        func unsigned(_ value: Any?) -> UInt64? {
            (value as? NSNumber).map { $0.uint64Value }
        }

        let entries: [ArchiveEntry] = items.compactMap { item in
            guard var path = item["XADFileName"] as? String else { return nil }
            while path.hasPrefix("./") { path.removeFirst(2) }
            while path.hasSuffix("/") { path.removeLast() }
            guard !path.isEmpty, path != "." else { return nil }
            return ArchiveEntry(
                path: path,
                isDirectory: (item["XADIsDirectory"] as? Bool) ?? false,
                size: unsigned(item["XADFileSize"]) ?? 0,
                packedSize: unsigned(item["XADCompressedSize"]),
                modified: (item["XADLastModificationDate"] as? String).flatMap(formatter.date(from:)),
                crc: nil,
                isEncrypted: (item["XADIsEncrypted"] as? Bool) ?? false,
                method: item["XADCompressionName"] as? String,
                attributes: nil
            )
        }
        let properties = ArchiveProperties(
            format: (root["lsarFormatName"] as? String) ?? "Rar", physicalSize: nil, headersSize: nil,
            method: nil, isSolid: nil, blocks: nil
        )
        return (properties, entries)
    }

    // MARK: - Integrity test

    /// Verifies every (or every selected) file with `lsar -t`, which reads and
    /// checks the data without writing anything. Returns normally when all
    /// pass; throws ``ArchiveError/integrityFailures(passed:failed:)`` otherwise.
    /// With `basis`, each finished file advances `progress` by its size.
    func test(
        archiveAt url: URL, selectedPaths: [String], password: String?,
        basis: TestProgressBasis? = nil,
        progress: @escaping @Sendable (ProgressInfo) -> Void = { _ in }
    ) async throws {
        var arguments = ["-t"]
        if let password, !password.isEmpty { arguments += ["-p", password] }
        arguments.append(url.path)
        arguments += Self.selectionArguments(for: selectedPaths)
        let state = LsarTestState(basis: basis, report: progress)
        let (exitCode, errorData) = try await SevenZipRunner(executable: lister)
            .stream(arguments) { state.consume($0) }
        state.finish()
        if Task.isCancelled { throw ArchiveError.cancelled }

        let (passed, failures) = (state.passed, state.failures)
        if failures.isEmpty {
            guard exitCode == 0 else {
                throw ArchiveError.operationFailed(
                    code: exitCode,
                    message: String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            return
        }
        throw ArchiveError.integrityFailures(passed: passed, failed: failures)
    }

    /// One `lsar -t` result line: `name... OK.` or `name... <reason>!`.
    static func parseTestLine(_ line: String) -> (name: String, status: String)? {
        guard let range = line.range(of: "... ", options: .backwards) else { return nil }
        let status = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !status.isEmpty else { return nil }
        return (String(line[..<range.lowerBound]), status)
    }

    // MARK: - Extraction

    func extract(
        _ request: ExtractionRequest,
        progress: @escaping @Sendable (ProgressInfo) -> Void
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: request.destinationURL, withIntermediateDirectories: true)

        // `unar` has no "flatten" switch, so a flattened extraction lands in a
        // private scratch folder first and its files are moved up afterwards.
        let flatten = request.flattenPaths && !request.selectedPaths.isEmpty
        if flatten { Self.removeStaleScratch(in: request.destinationURL) }
        let target = flatten
            ? request.destinationURL.appendingPathComponent(".7zip4mac-\(UUID().uuidString)", isDirectory: true)
            : request.destinationURL
        defer { if flatten { try? fileManager.removeItem(at: target) } }

        var scoped = request
        scoped.destinationURL = target
        let state = UnarOutputState(totalBytes: request.totalUncompressedSize, report: progress)
        let (exitCode, errorData) = try await SevenZipRunner(executable: extractor)
            .stream(Self.extractionArguments(for: scoped)) { state.consume($0) }
        state.finish()

        if Task.isCancelled { throw ArchiveError.cancelled }

        if flatten {
            try Self.moveFlattened(
                selectedPaths: request.selectedPaths, from: target,
                to: request.destinationURL, policy: request.overwritePolicy
            )
        }

        let failures = state.failures
        ArchiveLog.service.info("Fallback extraction: unar exited with code \(exitCode), \(failures.count, privacy: .public) file(s) failed")
        guard exitCode != 0 || !failures.isEmpty else { return }

        let combined = (failures.map(\.detail) + [String(decoding: errorData, as: UTF8.self)])
            .joined(separator: " ").lowercased()
        if combined.contains("password") { throw ArchiveError.wrongPassword }

        guard !failures.isEmpty else {
            throw ArchiveError.operationFailed(
                code: exitCode,
                message: String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        throw ArchiveError.partialExtraction(
            failed: failures.map { "\($0.name) (\($0.detail))" },
            destinationIssue: failures.contains { $0.detail.lowercased().contains("write") }
        )
    }

    /// Never interactive: `unar` asks on a conflict unless told otherwise.
    static func extractionArguments(for request: ExtractionRequest) -> [String] {
        var arguments = ["-D", "-o", request.destinationURL.path]
        switch request.overwritePolicy {
        case .overwrite: arguments.append("-f")
        case .skip: arguments.append("-s")
        case .rename: arguments.append("-r")
        }
        if let password = request.password, !password.isEmpty {
            arguments += ["-p", password]
        }
        // Like 7-Zip, don't expand archives found inside the archive.
        arguments.append("-nr")
        arguments.append(request.archiveURL.path)
        arguments += selectionArguments(for: request.selectedPaths)
        return arguments
    }

    /// Selected entries as `--` plus glob patterns: names are patterns for
    /// `unar`/`lsar`, and a folder only matches its contents as `folder/*`.
    static func selectionArguments(for paths: [String]) -> [String] {
        guard !paths.isEmpty else { return [] }
        var arguments = ["--"]
        for path in paths {
            let escaped = escapedPattern(path)
            arguments += [escaped, escaped + "/*"]
        }
        return arguments
    }

    static func escapedPattern(_ name: String) -> String {
        var result = ""
        for character in name {
            if "\\*?[]".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    /// Scratch folders left behind by a run that was killed before its
    /// cleanup. Only this app's own hidden `.7zip4mac-<UUID>` folders, and
    /// only once they are a day old, so a run in progress is never touched.
    static func removeStaleScratch(in destination: URL) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: destination.path) else { return }
        let pattern = #"^\.7zip4mac-[0-9A-Fa-f-]{36}$"#
        for name in names where name.range(of: pattern, options: .regularExpression) != nil {
            let url = destination.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
            if Date.now.timeIntervalSince(modified) > 86_400 { try? fileManager.removeItem(at: url) }
        }
    }

    static func moveFlattened(
        selectedPaths: [String], from scratch: URL, to destination: URL,
        policy: ExtractionRequest.OverwritePolicy
    ) throws {
        let fileManager = FileManager.default
        for path in selectedPaths {
            let components = path.split(separator: "/").map(String.init).filter { $0 != "." && $0 != ".." && !$0.isEmpty }
            guard let leaf = components.last else { continue }
            let source = components.reduce(scratch) { $0.appendingPathComponent($1) }
            guard fileManager.fileExists(atPath: source.path) else { continue }
            // A symlinked folder inside the archive could point anywhere; only
            // move what really resolves to a place inside the scratch folder.
            let inside = scratch.resolvingSymlinksInPath().path + "/"
            guard source.resolvingSymlinksInPath().path.hasPrefix(inside) else { continue }
            var target = destination.appendingPathComponent(leaf)
            if fileManager.fileExists(atPath: target.path) {
                switch policy {
                case .skip: continue
                case .overwrite: try fileManager.removeItem(at: target)
                case .rename:
                    let base = target.deletingPathExtension().lastPathComponent
                    let ext = target.pathExtension
                    var counter = 1
                    repeat {
                        let name = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
                        target = destination.appendingPathComponent(name)
                        counter += 1
                    } while fileManager.fileExists(atPath: target.path)
                }
            }
            try fileManager.moveItem(at: source, to: target)
        }
    }
}

/// Parses `unar`'s per-file output (`  name  (123 B)... OK.` /
/// `... Failed! (reason)`) into progress and a list of failed files.
final class UnarOutputState: @unchecked Sendable {
    struct Failure: Equatable, Sendable { let name: String; let detail: String }

    private let lock = NSLock()
    private let totalBytes: UInt64
    private let report: @Sendable (ProgressInfo) -> Void
    private var estimator = RateEstimator()
    private var lines = LineBuffer()
    private var processed: UInt64 = 0
    private var failed: [Failure] = []
    private var current: String?
    private var loggedAllReported = false

    init(totalBytes: UInt64, report: @escaping @Sendable (ProgressInfo) -> Void) {
        self.totalBytes = totalBytes
        self.report = report
    }

    var failures: [Failure] {
        lock.lock(); defer { lock.unlock() }
        return failed
    }

    func consume(_ chunk: String) {
        lock.lock()
        for line in lines.feed(chunk) { handle(line) }
        let info = makeInfo()
        let justReachedEnd = totalBytes > 0 && processed >= totalBytes && !loggedAllReported
        if justReachedEnd { loggedAllReported = true }
        lock.unlock()
        if justReachedEnd {
            ArchiveLog.service.info("Fallback extraction: every file reported; waiting for unar to exit")
        }
        report(info)
    }

    func finish() {
        lock.lock()
        if let last = lines.flush() { handle(last) }
        lock.unlock()
    }

    private func handle(_ line: String) {
        guard let parsed = Self.parse(line: line) else { return }
        processed += parsed.size
        current = parsed.name
        if let detail = parsed.failureDetail { failed.append(Failure(name: parsed.name, detail: detail)) }
    }

    private func makeInfo() -> ProgressInfo {
        let fraction = totalBytes > 0 ? min(Double(processed) / Double(totalBytes), 1) : 0
        let rate = estimator.rate(processed: processed)
        let remaining = RateEstimator.remaining(total: totalBytes, processed: processed, rate: rate)
        return ProgressInfo(
            fractionCompleted: fraction, processedBytes: processed, totalBytes: totalBytes,
            bytesPerSecond: rate, estimatedTimeRemaining: remaining, currentFile: current
        )
    }

    private static let linePattern = try? NSRegularExpression(pattern: #"^\s*(.+?)\s+\((\d+) B[^)]*\)\.\.\. (.*)$"#)

    static func parse(line: String) -> (name: String, size: UInt64, failureDetail: String?)? {
        guard
            let regex = linePattern,
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let nameRange = Range(match.range(at: 1), in: line),
            let sizeRange = Range(match.range(at: 2), in: line),
            let statusRange = Range(match.range(at: 3), in: line)
        else { return nil }
        let status = String(line[statusRange])
        let detail: String? = status.hasPrefix("Failed!")
            ? status.dropFirst("Failed!".count).trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
            : nil
        return (String(line[nameRange]), UInt64(line[sizeRange]) ?? 0, detail)
    }
}


/// Reads `lsar -t` output as it streams and turns each finished file into
/// progress, using the entry sizes the archive listing already provided.
final class LsarTestState: @unchecked Sendable {
    private let lock = NSLock()
    private let basis: TestProgressBasis?
    private let report: @Sendable (ProgressInfo) -> Void
    private var estimator = RateEstimator()
    private var lines = LineBuffer()
    private var processed: UInt64 = 0
    private var latest: String?
    private var passedCount = 0
    private var failedNames: [String] = []

    init(basis: TestProgressBasis?, report: @escaping @Sendable (ProgressInfo) -> Void) {
        self.basis = basis
        self.report = report
    }

    var passed: Int { lock.lock(); defer { lock.unlock() }; return passedCount }
    var failures: [String] { lock.lock(); defer { lock.unlock() }; return failedNames }

    func consume(_ chunk: String) {
        lock.lock()
        for line in lines.feed(chunk) { handle(line) }
        let info = makeInfo()
        lock.unlock()
        if let info { report(info) }
    }

    func finish() {
        lock.lock()
        if let last = lines.flush() { handle(last) }
        lock.unlock()
    }

    private func handle(_ line: String) {
        guard let (name, status) = RarFallbackEngine.parseTestLine(line) else { return }
        latest = name
        processed += basis?.entrySizes[name] ?? 0
        if status == "OK." {
            passedCount += 1
        } else {
            failedNames.append("\(name) (\(status.trimmingCharacters(in: CharacterSet(charactersIn: "!."))))")
        }
    }

    private func makeInfo() -> ProgressInfo? {
        guard let total = basis?.totalBytes, total > 0 else { return nil }
        let done = min(processed, total)
        let rate = estimator.rate(processed: done)
        let remaining = RateEstimator.remaining(total: total, processed: done, rate: rate)
        return ProgressInfo(
            fractionCompleted: Double(done) / Double(total),
            processedBytes: done, totalBytes: total,
            bytesPerSecond: rate, estimatedTimeRemaining: remaining, currentFile: latest
        )
    }
}
