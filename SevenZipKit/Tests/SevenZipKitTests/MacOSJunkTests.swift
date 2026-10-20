import XCTest
@testable import SevenZipKit

private func entry(_ path: String, directory: Bool = false) -> ArchiveEntry {
    ArchiveEntry(
        path: path, isDirectory: directory, size: directory ? 0 : 1, packedSize: nil, modified: nil,
        crc: nil, isEncrypted: false, method: nil, attributes: nil
    )
}

final class MacOSJunkTests: XCTestCase {
    func testRecognizesTheClutterMacOSAdds() {
        for junk in [
            "__MACOSX", "__MACOSX/", "__MACOSX/dir/._a.txt", ".DS_Store", "dir/.DS_Store", "dir/sub/._b.txt",
            ".Spotlight-V100/Store-V2/x", ".AppleDouble/a", ".Trashes/501", ".fseventsd/x", ".apdisk", "Icon\r",
        ] {
            XCTAssertTrue(MacOSJunk.isJunk(path: junk), junk)
        }
    }

    func testLeavesRealContentAlone() {
        for real in [
            "a.txt", "dir/a.txt", "__init__.py", "pkg/__init__.py", "__tests__/a.js", "__pycache__/m.pyc",
            ".gitignore", ".git/config", "._", "dir/._", "My.DS_Store.txt", "DS_Store",
        ] {
            XCTAssertFalse(MacOSJunk.isJunk(path: real), real)
        }
    }

    func testBrowsingHidesDotfilesAndMacOSXButNotOtherDoubleUnderscoreNames() {
        XCTAssertTrue(MacOSJunk.isHiddenName(".DS_Store"))
        XCTAssertTrue(MacOSJunk.isHiddenName(".git"))
        XCTAssertTrue(MacOSJunk.isHiddenName("__MACOSX"))
        XCTAssertFalse(MacOSJunk.isHiddenName("__init__.py"), "real content must not be hidden")
        XCTAssertFalse(MacOSJunk.isHiddenName("__tests__"))
        XCTAssertFalse(MacOSJunk.isHiddenName("a.txt"))
    }

    func testAFolderOfJunkIsOneRootAndLooseJunkKeepsItsOwnPath() {
        let summary = MacOSJunk.summary(of: [
            entry("a.txt"), entry("dir", directory: true), entry("dir/b.txt"),
            entry("__MACOSX/", directory: true), entry("__MACOSX/dir/", directory: true),
            entry("__MACOSX/._a.txt"), entry("__MACOSX/dir/._b.txt"),
            entry(".DS_Store"), entry("dir/.DS_Store"), entry("dir/._b.txt"),
        ])
        XCTAssertEqual(summary.roots, ["__MACOSX", ".DS_Store", "dir/.DS_Store", "dir/._b.txt"])
        XCTAssertEqual(summary.fileCount, 5, "folders themselves aren't counted")
        XCTAssertEqual(summary.exampleNames, ["__MACOSX", ".DS_Store", "._b.txt"], "repeated names are listed once")
        XCTAssertFalse(summary.isEmpty)
    }

    func testNamesThatSevenZipWouldReadAsWildcardsAreNeverOffered() {
        let summary = MacOSJunk.summary(of: [
            entry("dir*/.DS_Store"), entry("x?/._y"), entry("__MACOSX*/._z"), entry("._*"), entry("ok/.DS_Store"),
        ])
        XCTAssertEqual(summary.roots, ["ok/.DS_Store"])
        XCTAssertEqual(summary.fileCount, 1)
    }

    func testAnArchiveWithoutClutterHasNothingToRemove() {
        XCTAssertTrue(MacOSJunk.summary(of: [entry("a.txt"), entry("__init__.py"), entry("d", directory: true)]).isEmpty)
        XCTAssertEqual(MacOSJunk.Summary.none, MacOSJunk.summary(of: []))
    }
}

/// With the real 7-Zip engine: removing the roots really leaves only the user's files.
final class MacOSJunkRemovalTests: XCTestCase {
    private var root: URL!

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

    private func service() throws -> ArchiveService {
        ArchiveService(executable: try SevenZipExecutable(validatingURL: Self.engine))
    }

    private func makeZip(extra: (URL) throws -> Void = { _ in }) throws -> URL {
        let source = root.appendingPathComponent("src", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: source.appendingPathComponent("dir"), withIntermediateDirectories: true)
        try fm.createDirectory(at: source.appendingPathComponent("__MACOSX/dir"), withIntermediateDirectories: true)
        for (name, text) in [
            ("a.txt", "a"), ("dir/b.txt", "b"), ("__init__.py", "keep"), (".DS_Store", "j"), ("dir/.DS_Store", "j"),
            ("dir/._b.txt", "r"), ("__MACOSX/._a.txt", "r"), ("__MACOSX/dir/._b.txt", "r"),
        ] { try text.write(to: source.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        try extra(source)
        let zip = root.appendingPathComponent("t.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = source
        process.arguments = ["-qr", zip.path, "."]
        try process.run(); process.waitUntilExit()
        return zip
    }

    func testRemovingTheRootsLeavesOnlyTheUsersFiles() async throws {
        let zip = try makeZip()
        let service = try service()
        let opened = try await service.open(archiveAt: zip)
        let summary = MacOSJunk.summary(of: opened.entries)
        XCTAssertEqual(Set(summary.roots), ["__MACOSX", ".DS_Store", "dir/.DS_Store", "dir/._b.txt"])

        try await service.delete(archiveAt: zip, paths: summary.roots)

        let remaining = Set(try await service.open(archiveAt: zip).entries.filter { !$0.isDirectory }.map(\.path))
        XCTAssertEqual(remaining, ["a.txt", "dir/b.txt", "__init__.py"])
    }

    func testThousandsOfJunkFilesAreRemovedInBatches() async throws {
        let zip = try makeZip { source in
            try FileManager.default.createDirectory(at: source.appendingPathComponent("many"), withIntermediateDirectories: true)
            for i in 0..<1_000 {
                try "x".write(to: source.appendingPathComponent("many/._file\(i).txt"), atomically: true, encoding: .utf8)
            }
        }
        let service = try service()
        let summary = MacOSJunk.summary(of: try await service.open(archiveAt: zip).entries)
        XCTAssertGreaterThan(summary.roots.count, 1_000)

        try await service.delete(archiveAt: zip, paths: summary.roots)

        let remaining = Set(try await service.open(archiveAt: zip).entries.filter { !$0.isDirectory }.map(\.path))
        XCTAssertEqual(remaining, ["a.txt", "dir/b.txt", "__init__.py"])
    }
}
