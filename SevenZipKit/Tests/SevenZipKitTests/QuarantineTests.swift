import XCTest
import Darwin
@testable import SevenZipKit

final class QuarantineTests: XCTestCase {
    private var root: URL!
    private let marker = Data("0083;5f000000;Safari;11111111-1111-1111-1111-111111111111".utf8)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relative: String, _ text: String = "x") throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testApplyMarksTheWholeTreeAndTheSymlinkItself() throws {
        let file = try write("tree/a/b.txt")
        let link = root.appendingPathComponent("tree/link")
        let outside = try write("outside.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        Quarantine.apply(marker, to: root.appendingPathComponent("tree"))

        XCTAssertEqual(Quarantine.value(of: file), marker)
        XCTAssertEqual(Quarantine.value(of: root.appendingPathComponent("tree/a")), marker)
        XCTAssertEqual(Quarantine.value(of: link), marker, "the link itself is marked")
        XCTAssertNil(Quarantine.value(of: outside), "a link's target must never be followed and marked")
    }

    func testCutoffLeavesOlderItemsAlone() throws {
        let old = try write("d/old.txt"), fresh = try write("d/new.txt")
        try FileManager.default.setAttributes([.creationDate: Date.now.addingTimeInterval(-86_400)], ofItemAtPath: old.path)
        Quarantine.apply(marker, to: root.appendingPathComponent("d"), onlyCreatedSince: .now.addingTimeInterval(-60))
        XCTAssertEqual(Quarantine.value(of: fresh), marker)
        XCTAssertNil(Quarantine.value(of: old))
    }

    func testNoMarkerMeansNothingToCarry() throws {
        XCTAssertNil(Quarantine.value(of: try write("plain.txt")))
    }

    func testSafeArchiveRelativePaths() {
        for good in ["a.txt", "dir/a.txt", "dir/sub/a b.txt", "a..b", "dir/.hidden"] {
            XCTAssertTrue(good.isSafeArchiveRelativePath, good)
        }
        for bad in ["", "/etc/passwd", "../x", "a/../../x", "a/..", "dir//../x"] {
            XCTAssertFalse(bad.isSafeArchiveRelativePath, bad)
        }
    }

    func testTrimmingTrailingSlash() {
        XCTAssertEqual("dir/".trimmingTrailingSlash, "dir")
        XCTAssertEqual("dir/sub".trimmingTrailingSlash, "dir/sub")
        XCTAssertEqual("".trimmingTrailingSlash, "")
    }
}

/// With the real 7-Zip engine: files extracted from a downloaded archive keep
/// the "downloaded" marker, and files that were already in the destination do not
/// get one.
final class QuarantineExtractionTests: XCTestCase {
    private var root: URL!
    private let marker = Data("0083;5f000000;Safari;22222222-2222-2222-2222-222222222222".utf8)

    private static var engine: URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { dir.deleteLastPathComponent() }
        return dir.appending(path: "App/Resources/Engine/7zz")
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: Self.engine.path), "7zz not bundled")
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func makeZip(quarantined: Bool) throws -> URL {
        let source = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("dir/sub"), withIntermediateDirectories: true)
        try "one".write(to: source.appendingPathComponent("dir/f.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: source.appendingPathComponent("dir/sub/g.txt"), atomically: true, encoding: .utf8)
        let zip = root.appendingPathComponent("download.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = source
        process.arguments = ["-qr", zip.path, "dir"]
        try process.run(); process.waitUntilExit()
        if quarantined { Quarantine.apply(marker, to: zip) }
        return zip
    }

    private func service() throws -> ArchiveService {
        ArchiveService(executable: try SevenZipExecutable(validatingURL: Self.engine))
    }

    func testWholeArchiveIntoANewFolderIsMarkedEverywhere() async throws {
        let zip = try makeZip(quarantined: true)
        let out = root.appendingPathComponent("out")
        try await service().extract(ExtractionRequest(archiveURL: zip, destinationURL: out)) { _ in }
        for relative in ["dir", "dir/f.txt", "dir/sub", "dir/sub/g.txt"] {
            XCTAssertEqual(Quarantine.value(of: out.appendingPathComponent(relative)), marker, relative)
        }
    }

    func testArchiveWithoutTheMarkerStaysUnmarked() async throws {
        let zip = try makeZip(quarantined: false)
        let out = root.appendingPathComponent("out")
        try await service().extract(ExtractionRequest(archiveURL: zip, destinationURL: out)) { _ in }
        XCTAssertNil(Quarantine.value(of: out.appendingPathComponent("dir/f.txt")))
    }

    func testFilesAlreadyInTheDestinationAreNotMarked() async throws {
        let zip = try makeZip(quarantined: true)
        let out = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let mine = out.appendingPathComponent("mine.txt")
        try "mine".write(to: mine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.creationDate: Date.now.addingTimeInterval(-86_400)], ofItemAtPath: mine.path)

        try await service().extract(ExtractionRequest(archiveURL: zip, destinationURL: out)) { _ in }

        XCTAssertNil(Quarantine.value(of: mine), "an unrelated pre-existing file must not be marked")
        XCTAssertEqual(Quarantine.value(of: out.appendingPathComponent("dir/f.txt")), marker)
    }

    func testFlattenedSelectionIsMarkedAtItsFinalLocation() async throws {
        let zip = try makeZip(quarantined: true)
        let out = root.appendingPathComponent("out")
        try await service().extract(
            ExtractionRequest(archiveURL: zip, destinationURL: out, selectedPaths: ["dir/sub/g.txt"], flattenPaths: true)
        ) { _ in }
        XCTAssertEqual(Quarantine.value(of: out.appendingPathComponent("g.txt")), marker)
    }

    func testSelectedFolderKeepsItsStructureAndIsMarked() async throws {
        let zip = try makeZip(quarantined: true)
        let out = root.appendingPathComponent("out")
        try await service().extract(
            ExtractionRequest(archiveURL: zip, destinationURL: out, selectedPaths: ["dir/sub"])
        ) { _ in }
        XCTAssertEqual(Quarantine.value(of: out.appendingPathComponent("dir/sub/g.txt")), marker)
        XCTAssertEqual(Quarantine.value(of: out.appendingPathComponent("dir/sub")), marker)
    }
}
