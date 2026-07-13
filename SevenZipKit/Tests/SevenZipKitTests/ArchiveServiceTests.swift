import Foundation
import Testing
@testable import SevenZipKit

/// A fake bridge that returns canned data, so the service can be tested
/// without a real engine or filesystem.
private struct FakeBridge: SevenZipBridge {
    let properties: ArchiveProperties
    let entries: [ArchiveEntry]
    let error: ArchiveError?

    init(
        properties: ArchiveProperties = .unknown,
        entries: [ArchiveEntry] = [],
        error: ArchiveError? = nil
    ) {
        self.properties = properties
        self.entries = entries
        self.error = error
    }

    func list(archiveAt url: URL, password: String?) async throws -> (ArchiveProperties, [ArchiveEntry]) {
        if let error { throw error }
        return (properties, entries)
    }

    func extract(
        _ request: ExtractionRequest,
        progress: @escaping @Sendable (ProgressInfo) -> Void
    ) async throws {
        if let error { throw error }
        progress(ProgressInfo(
            fractionCompleted: 1, processedBytes: request.totalUncompressedSize,
            totalBytes: request.totalUncompressedSize, bytesPerSecond: 0,
            estimatedTimeRemaining: 0, currentFile: nil
        ))
    }

    func compress(
        _ request: CompressionRequest,
        progress: @escaping @Sendable (ProgressInfo) -> Void
    ) async throws {
        if let error { throw error }
        progress(ProgressInfo(
            fractionCompleted: 1, processedBytes: request.totalSourceSize,
            totalBytes: request.totalSourceSize, bytesPerSecond: 0,
            estimatedTimeRemaining: 0, currentFile: nil
        ))
    }

    func benchmark(passes: Int?) async throws -> BenchmarkResult {
        if let error { throw error }
        return BenchmarkResult(totalRatingMIPS: 12345)
    }

    func test(archiveAt url: URL, selectedPaths: [String], password: String?) async throws -> Bool {
        if let error { throw error }
        return true
    }

    func delete(archiveAt url: URL, paths: [String], password: String?) async throws {
        if let error { throw error }
    }

    func rename(archiveAt url: URL, from oldPath: String, to newPath: String, password: String?) async throws {
        if let error { throw error }
    }
}

@Suite("ArchiveService")
struct ArchiveServiceTests {

    private func entry(_ path: String, dir: Bool, size: UInt64) -> ArchiveEntry {
        ArchiveEntry(
            path: path, isDirectory: dir, size: size, packedSize: nil,
            modified: nil, crc: nil, isEncrypted: false, method: nil, attributes: nil
        )
    }

    @Test("assembles an Archive from the bridge output")
    func buildsArchive() async throws {
        let bridge = FakeBridge(
            properties: ArchiveProperties(
                format: "7z", physicalSize: 281, headersSize: 225,
                method: "LZMA2:6k", isSolid: true, blocks: 1
            ),
            entries: [
                entry("dir", dir: true, size: 0),
                entry("dir/a.txt", dir: false, size: 100),
                entry("dir/b.txt", dir: false, size: 250)
            ]
        )
        let service = ArchiveService(bridge: bridge)
        let archive = try await service.open(archiveAt: URL(fileURLWithPath: "/tmp/x.7z"))

        #expect(archive.properties.format == "7z")
        #expect(archive.entries.count == 3)
        #expect(archive.fileCount == 2)
        #expect(archive.folderCount == 1)
        #expect(archive.totalSize == 350)
    }

    @Test("propagates a wrong-password error")
    func propagatesWrongPassword() async {
        let bridge = FakeBridge(error: .wrongPassword)
        let service = ArchiveService(bridge: bridge)
        await #expect(throws: ArchiveError.wrongPassword) {
            _ = try await service.open(archiveAt: URL(fileURLWithPath: "/tmp/x.7z"))
        }
    }
}
