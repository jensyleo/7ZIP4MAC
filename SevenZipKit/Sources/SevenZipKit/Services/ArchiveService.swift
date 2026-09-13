import Foundation

/// High-level API the app's ViewModels use to work with archives.
///
/// Services own the logic; ViewModels only call them and publish the result.
/// `ArchiveService` depends on the ``SevenZipBridge`` abstraction, so it can
/// be exercised in tests with a fake bridge and no real engine.
public protocol ArchiveServing: Sendable {
    /// Opens an archive and returns its parsed contents.
    func open(archiveAt url: URL, password: String?) async throws -> Archive

    /// Extracts an archive, reporting progress as it runs.
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
    func benchmark(passes: Int?) async throws -> BenchmarkResult

    /// Tests the integrity of an archive, or just `selectedPaths` when given.
    /// Returns true if everything is OK.
    func test(archiveAt url: URL, selectedPaths: [String], password: String?) async throws -> Bool

    /// Deletes entries from an archive in place.
    func delete(archiveAt url: URL, paths: [String], password: String?) async throws

    /// Renames or moves an entry within an archive in place.
    func rename(archiveAt url: URL, from oldPath: String, to newPath: String, password: String?) async throws
}

public struct ArchiveService: ArchiveServing {
    private let bridge: SevenZipBridge

    public init(bridge: SevenZipBridge) {
        self.bridge = bridge
    }

    /// Convenience initialiser that wires the production system bridge.
    public init(executable: SevenZipExecutable) {
        self.init(bridge: SystemSevenZipBridge(executable: executable))
    }

    /// Single-stream compressors: formats 7-Zip reports as the archive's
    /// `Type` that carry exactly one anonymous data stream and no entry list
    /// of their own — bzip2/gzip/xz all work this way, which is why opening
    /// a bare `.tar.bz2` through `7zz l -slt` lists zero entries: the "file"
    /// is the compressed stream itself, not a container. The real contents
    /// (almost always a `.tar`) only appear once that stream is extracted.
    private static let singleStreamFormats: Set<String> = ["bzip2", "gzip", "xz", "lzma", "z", "brotli", "lz4", "lz5"]

    /// How many nested single-stream layers to unwrap before giving up (a
    /// real `.tar.bz2` only ever needs one) — just a guard against chasing a
    /// pathological or corrupt chain forever.
    private static let maxUnwrapDepth = 4

    public func open(archiveAt url: URL, password: String? = nil) async throws -> Archive {
        let (properties, entries) = try await bridge.list(archiveAt: url, password: password)
        guard entries.isEmpty, let format = properties.format,
              Self.singleStreamFormats.contains(format.lowercased())
        else {
            return Archive(url: url, properties: properties, entries: entries)
        }
        return try await unwrap(url: url, properties: properties, password: password, depth: 0)
    }

    /// Extracts `url`'s single compressed stream to a staging directory and
    /// lists whatever comes out, recursing if that's itself another
    /// single-stream layer. Falls back to the original (entry-less) listing
    /// if anything about the unwrap doesn't come out as expected, rather than
    /// failing the whole open.
    private func unwrap(
        url: URL,
        properties: ArchiveProperties,
        password: String?,
        depth: Int
    ) async throws -> Archive {
        guard depth < Self.maxUnwrapDepth else {
            return Archive(url: url, properties: properties, entries: [])
        }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("7ZIP4MAC-Unwrap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            let request = ExtractionRequest(
                archiveURL: url, destinationURL: staging, password: password, selectedPaths: []
            )
            try await bridge.extract(request) { _ in }

            let items = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            guard let innerURL = items.first, items.count == 1 else {
                try? FileManager.default.removeItem(at: staging)
                return Archive(url: url, properties: properties, entries: [])
            }

            if let (innerProperties, innerEntries) = try? await bridge.list(archiveAt: innerURL, password: password) {
                if innerEntries.isEmpty, let innerFormat = innerProperties.format,
                   Self.singleStreamFormats.contains(innerFormat.lowercased()) {
                    let deeper = try await unwrap(url: innerURL, properties: innerProperties, password: password, depth: depth + 1)
                    // The deeper unwrap staged its own directory; this level's
                    // staging only held the intermediate file, no longer needed.
                    try? FileManager.default.removeItem(at: staging)
                    return Archive(
                        url: url, properties: deeper.properties, entries: deeper.entries,
                        effectiveURL: deeper.effectiveURL, stagingDirectory: deeper.stagingDirectory
                    )
                }
                return Archive(
                    url: url, properties: innerProperties, entries: innerEntries,
                    effectiveURL: innerURL, stagingDirectory: staging
                )
            }

            // The unwrapped stream isn't itself a recognizable archive — a
            // plain file (not a tar) was bz2/gz/xz-compressed on its own,
            // e.g. "notes.txt.gz". 7-Zip's own -slt never reports a Path for
            // this single stream, so there's no entry name selective
            // extraction could target; falling back to the entry-less
            // listing keeps this honest rather than faking one. "Extract
            // All" on `url` itself still works fine either way — it doesn't
            // need an entry to extract a single-stream compressor's content.
            try? FileManager.default.removeItem(at: staging)
            return Archive(url: url, properties: properties, entries: [])
        } catch {
            try? FileManager.default.removeItem(at: staging)
            return Archive(url: url, properties: properties, entries: [])
        }
    }

    public func extract(
        _ request: ExtractionRequest,
        progress: @escaping @Sendable (ProgressInfo) -> Void
    ) async throws {
        try await bridge.extract(request, progress: progress)
    }

    public func compress(
        _ request: CompressionRequest,
        progress: @escaping @Sendable (ProgressInfo) -> Void
    ) async throws {
        try await bridge.compress(request, progress: progress)
    }

    public func benchmark(passes: Int? = nil) async throws -> BenchmarkResult {
        try await bridge.benchmark(passes: passes)
    }

    public func test(archiveAt url: URL, selectedPaths: [String] = [], password: String? = nil) async throws -> Bool {
        try await bridge.test(archiveAt: url, selectedPaths: selectedPaths, password: password)
    }

    public func delete(archiveAt url: URL, paths: [String], password: String? = nil) async throws {
        try await bridge.delete(archiveAt: url, paths: paths, password: password)
    }

    public func rename(archiveAt url: URL, from oldPath: String, to newPath: String, password: String? = nil) async throws {
        try await bridge.rename(archiveAt: url, from: oldPath, to: newPath, password: password)
    }
}
