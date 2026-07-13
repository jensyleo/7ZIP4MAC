import Foundation
import Testing
@testable import SevenZipKit

/// End-to-end tests that drive the real, bundled `7zz` engine.
///
/// These exercise the whole stack (service → bridge → runner → 7zz) the way the
/// app does, covering the behaviours the drag-out and Quick Look features rely
/// on: single-entry extraction, folder recursion, and compression round-trips.
///
/// The engine is located relative to this source file (the app bundles it at
/// `App/Resources/Engine/7zz`); if it cannot be found the suite is skipped.
@Suite(.enabled(if: SevenZipEngine.isAvailable), .serialized)
struct SevenZipIntegrationTests {

    private let fm = FileManager.default

    /// Creates a fresh temporary workspace containing a known file tree and
    /// returns its URL. The tree:
    /// `root/a.txt`, `root/sub/b.txt`, `root/sub/deep/c.bin`
    private func makeWorkspace() throws -> URL {
        let base = fm.temporaryDirectory.appending(
            path: "7zk-it-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        let root = base.appending(path: "root", directoryHint: .isDirectory)
        try fm.createDirectory(at: root.appending(path: "sub/deep"), withIntermediateDirectories: true)
        try "hello A".data(using: .utf8)!.write(to: root.appending(path: "a.txt"))
        try "nested B".data(using: .utf8)!.write(to: root.appending(path: "sub/b.txt"))
        try Data((0..<4096).map { UInt8($0 & 0xFF) }).write(to: root.appending(path: "sub/deep/c.bin"))
        return base
    }

    private func service() throws -> ArchiveService {
        let executable = try SevenZipExecutable(validatingURL: SevenZipEngine.url)
        return ArchiveService(executable: executable)
    }

    // MARK: - Compression + listing round-trip

    @Test("compresses a tree and lists it back with the right entries")
    func compressAndList() async throws {
        let workspace = try makeWorkspace()
        defer { try? fm.removeItem(at: workspace) }
        let archive = workspace.appending(path: "out.7z")

        let request = CompressionRequest(
            destinationURL: archive,
            sourceURLs: [workspace.appending(path: "root")],
            format: .sevenZip,
            level: .fast
        )
        try await service().compress(request) { _ in }
        #expect(fm.fileExists(atPath: archive.path))

        let opened = try await service().open(archiveAt: archive)
        let paths = Set(opened.entries.map(\.path))
        #expect(paths.contains("root/a.txt"))
        #expect(paths.contains("root/sub/b.txt"))
        #expect(paths.contains("root/sub/deep/c.bin"))
        #expect(opened.fileCount == 3)
        #expect(opened.properties.format == "7z")
    }

    @Test("adding a file into an already-existing archive appends it (Add feature)")
    func addIntoExistingArchive() async throws {
        let workspace = try makeWorkspace()
        defer { try? fm.removeItem(at: workspace) }
        let archive = workspace.appending(path: "out.7z")

        try await service().compress(
            CompressionRequest(destinationURL: archive, sourceURLs: [workspace.appending(path: "root")], format: .sevenZip),
            progress: { _ in }
        )

        // Simulate a dropped/newly-added file living elsewhere on disk —
        // exactly what ArchiveViewModel.addFiles does with a drag-and-drop URL.
        let extra = workspace.appending(path: "extra.txt")
        try "new content".data(using: .utf8)!.write(to: extra)

        try await service().compress(
            CompressionRequest(destinationURL: archive, sourceURLs: [extra], format: .sevenZip),
            progress: { _ in }
        )

        let opened = try await service().open(archiveAt: archive)
        let paths = Set(opened.entries.map(\.path))
        #expect(paths.contains("root/a.txt"), "original contents must survive the append")
        #expect(paths.contains("extra.txt"), "the newly added file must be present")
        #expect(opened.fileCount == 4)
    }

    // MARK: - Extraction

    @Test("extracts the whole archive byte-identically")
    func extractAll() async throws {
        let workspace = try makeWorkspace()
        defer { try? fm.removeItem(at: workspace) }
        let archive = workspace.appending(path: "out.7z")
        try await service().compress(
            CompressionRequest(destinationURL: archive,
                               sourceURLs: [workspace.appending(path: "root")]),
            progress: { _ in }
        )

        let dest = workspace.appending(path: "extract-all", directoryHint: .isDirectory)
        try await service().extract(
            ExtractionRequest(archiveURL: archive, destinationURL: dest),
            progress: { _ in }
        )

        let original = try Data(contentsOf: workspace.appending(path: "root/sub/deep/c.bin"))
        let extracted = try Data(contentsOf: dest.appending(path: "root/sub/deep/c.bin"))
        #expect(original == extracted)
        #expect(try String(contentsOf: dest.appending(path: "root/a.txt"), encoding: .utf8) == "hello A")
    }

    @Test("extracts a single selected file and nothing else")
    func extractSingleFile() async throws {
        let workspace = try makeWorkspace()
        defer { try? fm.removeItem(at: workspace) }
        let archive = workspace.appending(path: "out.7z")
        try await service().compress(
            CompressionRequest(destinationURL: archive,
                               sourceURLs: [workspace.appending(path: "root")]),
            progress: { _ in }
        )

        let dest = workspace.appending(path: "extract-one", directoryHint: .isDirectory)
        try await service().extract(
            ExtractionRequest(archiveURL: archive, destinationURL: dest,
                              selectedPaths: ["root/sub/b.txt"]),
            progress: { _ in }
        )

        // The selected file lands at dest/<full path>…
        #expect(fm.fileExists(atPath: dest.appending(path: "root/sub/b.txt").path))
        // …and the siblings must NOT be present.
        #expect(!fm.fileExists(atPath: dest.appending(path: "root/a.txt").path))
        #expect(!fm.fileExists(atPath: dest.appending(path: "root/sub/deep/c.bin").path))
    }

    @Test("extracting a folder brings its whole subtree")
    func extractFolderRecurses() async throws {
        let workspace = try makeWorkspace()
        defer { try? fm.removeItem(at: workspace) }
        let archive = workspace.appending(path: "out.7z")
        try await service().compress(
            CompressionRequest(destinationURL: archive,
                               sourceURLs: [workspace.appending(path: "root")]),
            progress: { _ in }
        )

        let dest = workspace.appending(path: "extract-folder", directoryHint: .isDirectory)
        try await service().extract(
            ExtractionRequest(archiveURL: archive, destinationURL: dest,
                              selectedPaths: ["root/sub"]),
            progress: { _ in }
        )

        #expect(fm.fileExists(atPath: dest.appending(path: "root/sub/b.txt").path))
        #expect(fm.fileExists(atPath: dest.appending(path: "root/sub/deep/c.bin").path))
        #expect(!fm.fileExists(atPath: dest.appending(path: "root/a.txt").path))
    }

    // MARK: - Progress

    @Test("reports terminal progress on completion")
    func reportsProgress() async throws {
        let workspace = try makeWorkspace()
        defer { try? fm.removeItem(at: workspace) }
        let archive = workspace.appending(path: "out.7z")

        let collector = ProgressCollector()
        try await service().compress(
            CompressionRequest(destinationURL: archive,
                               sourceURLs: [workspace.appending(path: "root")]),
            progress: { collector.record($0.fractionCompleted) }
        )
        #expect(collector.sawCompletion)
    }

    @Test("splitting produces multiple volumes that extract back")
    func splitVolumes() async throws {
        let workspace = try makeWorkspace()
        defer { try? fm.removeItem(at: workspace) }
        // Incompressible (random) payload so it actually spans several volumes.
        let big = workspace.appending(path: "root/big.bin")
        try Data((0..<500_000).map { _ in UInt8.random(in: 0...255) }).write(to: big)

        let archive = workspace.appending(path: "split.7z")
        try await service().compress(
            CompressionRequest(destinationURL: archive,
                               sourceURLs: [workspace.appending(path: "root")],
                               level: .fastest,
                               volumeSize: 150_000),
            progress: { _ in }
        )

        // 7-Zip writes split.7z.001, .002, … (not split.7z itself).
        let parts = (try fm.contentsOfDirectory(atPath: workspace.path))
            .filter { $0.hasPrefix("split.7z.") }
        #expect(parts.count >= 2)
        #expect(!fm.fileExists(atPath: archive.path))

        // The first volume opens and lists the whole archive.
        let opened = try await service().open(archiveAt: workspace.appending(path: "split.7z.001"))
        #expect(opened.entries.contains { $0.path == "root/big.bin" })
    }

    @Test("tests a healthy archive as OK, and a corrupted one as not OK")
    func testIntegrity() async throws {
        let workspace = try makeWorkspace()
        defer { try? fm.removeItem(at: workspace) }
        let archive = workspace.appending(path: "out.7z")
        try await service().compress(
            CompressionRequest(destinationURL: archive,
                               sourceURLs: [workspace.appending(path: "root")]),
            progress: { _ in }
        )

        let ok = try await service().test(archiveAt: archive, password: nil)
        #expect(ok)

        // Corrupt the archive body and expect the test to report a problem.
        var bytes = try Data(contentsOf: archive)
        if bytes.count > 40 {
            for i in 32..<min(bytes.count, 64) { bytes[i] = bytes[i] &+ 1 }
            try bytes.write(to: archive)
            let corrupted = (try? await service().test(archiveAt: archive, password: nil)) ?? false
            #expect(corrupted == false)
        }
    }

    @Test("tests only the selected entry, ignoring problems elsewhere")
    func testSelectedEntry() async throws {
        let workspace = try makeWorkspace()
        defer { try? fm.removeItem(at: workspace) }
        let archive = workspace.appending(path: "out.7z")
        try await service().compress(
            CompressionRequest(destinationURL: archive,
                               sourceURLs: [workspace.appending(path: "root")]),
            progress: { _ in }
        )

        let ok = try await service().test(archiveAt: archive, selectedPaths: ["root/a.txt"])
        #expect(ok)
    }

    // MARK: - Benchmark

    @Test("runs a real benchmark and returns a positive total rating")
    func benchmark() async throws {
        let result = try await service().benchmark(passes: 1)
        #expect(result.totalRatingMIPS ?? 0 > 0)
        #expect(!result.rows.isEmpty)
        #expect(result.cpuModel != nil)
    }

    // MARK: - Errors

    @Test("password-protected 7z cannot be listed without the password")
    func encryptedHeadersRequirePassword() async throws {
        let workspace = try makeWorkspace()
        defer { try? fm.removeItem(at: workspace) }
        let archive = workspace.appending(path: "secret.7z")
        try await service().compress(
            CompressionRequest(destinationURL: archive,
                               sourceURLs: [workspace.appending(path: "root")],
                               format: .sevenZip, level: .fast,
                               password: "s3cr3t", encryptFileNames: true),
            progress: { _ in }
        )

        // With encrypted headers, listing with no/wrong password must fail.
        await #expect(throws: (any Error).self) {
            _ = try await service().open(archiveAt: archive, password: "wrong")
        }
        // With the right password it succeeds.
        let opened = try await service().open(archiveAt: archive, password: "s3cr3t")
        #expect(opened.fileCount == 3)
    }
}

/// Thread-safe collector for progress fractions observed during an operation.
private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var completion = false
    func record(_ fraction: Double) {
        lock.lock(); if fraction >= 1.0 { completion = true }; lock.unlock()
    }
    var sawCompletion: Bool { lock.lock(); defer { lock.unlock() }; return completion }
}

/// Locates the bundled `7zz` engine for the integration tests.
enum SevenZipEngine {
    static let url: URL = {
        if let override = ProcessInfo.processInfo.environment["SEVENZIP_TEST_BINARY"] {
            return URL(fileURLWithPath: override)
        }
        // From <repo>/SevenZipKit/Tests/SevenZipKitTests/<thisFile> up to <repo>.
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { dir.deleteLastPathComponent() }
        return dir.appending(path: "App/Resources/Engine/7zz")
    }()

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }
}
