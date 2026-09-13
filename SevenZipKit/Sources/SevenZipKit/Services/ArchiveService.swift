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
    /// `Type` that carry exactly one data stream and no entry list of their
    /// own — bzip2/xz/lzma/z never report any entry at all for `.tar.bz2`,
    /// while gzip is a partial exception (it embeds the original filename in
    /// its header, so 7-Zip lists *one* entry named e.g. "app.tar" — but that
    /// entry is still just the compressed stream's name, not something you
    /// can browse into). Either way, the real contents (almost always a
    /// `.tar`) only appear once that stream is actually extracted, so both
    /// cases go through the same unwrap.
    private static let singleStreamFormats: Set<String> = ["bzip2", "gzip", "xz", "lzma", "z", "brotli", "lz4", "lz5"]

    /// How many nested single-stream layers to unwrap before giving up (a
    /// real `.tar.bz2` only ever needs one) — just a guard against chasing a
    /// pathological or corrupt chain forever.
    private static let maxUnwrapDepth = 4

    public func open(archiveAt url: URL, password: String? = nil) async throws -> Archive {
        let (properties, entries) = try await bridge.list(archiveAt: url, password: password)
        guard let format = properties.format, Self.singleStreamFormats.contains(format.lowercased()) else {
            return Archive(url: url, properties: properties, entries: entries)
        }
        return try await unwrap(url: url, rootProperties: properties, rootEntries: entries, password: password, depth: 0)
    }

    /// Extracts `url`'s single compressed stream to a staging directory and,
    /// if what comes out is itself a real container (most commonly a
    /// `.tar`), lists that instead — recursing if that's itself another
    /// single-stream layer (`.tar.bz2.gz`, rare but possible). Falls back to
    /// `rootEntries` (the root archive's own listing — empty for bzip2/xz,
    /// one gzip-header-derived entry for gzip) whenever the unwrap doesn't
    /// turn up anything more useful, rather than losing that or failing the
    /// whole open.
    private func unwrap(
        url: URL,
        rootProperties: ArchiveProperties,
        rootEntries: [ArchiveEntry],
        password: String?,
        depth: Int
    ) async throws -> Archive {
        let fallback = Archive(url: url, properties: rootProperties, entries: rootEntries)
        guard depth < Self.maxUnwrapDepth else { return fallback }

        let staging = try FileManager.default.makeScratchDirectory(tag: "Unwrap")

        do {
            let request = ExtractionRequest(
                archiveURL: url, destinationURL: staging, password: password, selectedPaths: []
            )
            try await bridge.extract(request) { _ in }

            let items = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            guard let innerURL = items.first, items.count == 1 else {
                try? FileManager.default.removeItem(at: staging)
                return fallback
            }

            guard let (innerProperties, innerEntries) = try? await bridge.list(archiveAt: innerURL, password: password) else {
                // Not a recognizable archive inside — a plain, non-tar file
                // was compressed on its own (e.g. "notes.txt.gz"). The root's
                // own listing is the best available: empty for bzip2/xz, or
                // (for gzip) one entry already carrying the real name/size
                // from its header.
                try? FileManager.default.removeItem(at: staging)
                return fallback
            }

            if innerEntries.isEmpty, let innerFormat = innerProperties.format,
               Self.singleStreamFormats.contains(innerFormat.lowercased()) {
                let deeper = try await unwrap(
                    url: innerURL, rootProperties: innerProperties, rootEntries: innerEntries,
                    password: password, depth: depth + 1
                )
                // The deeper unwrap staged its own directory; this level's
                // staging only held the intermediate file, no longer needed.
                try? FileManager.default.removeItem(at: staging)
                return Archive(
                    url: url, properties: deeper.properties, entries: deeper.entries,
                    effectiveURL: deeper.effectiveURL, stagingDirectory: deeper.stagingDirectory
                )
            }

            guard !innerEntries.isEmpty else {
                // Recognized but still entry-less, and not a further
                // single-stream layer either — nothing better than the root's
                // own listing.
                try? FileManager.default.removeItem(at: staging)
                return fallback
            }

            return Archive(
                url: url, properties: innerProperties, entries: innerEntries,
                effectiveURL: innerURL, stagingDirectory: staging
            )
        } catch {
            try? FileManager.default.removeItem(at: staging)
            return fallback
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
