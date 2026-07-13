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

    public func open(archiveAt url: URL, password: String? = nil) async throws -> Archive {
        let (properties, entries) = try await bridge.list(archiveAt: url, password: password)
        return Archive(url: url, properties: properties, entries: entries)
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
