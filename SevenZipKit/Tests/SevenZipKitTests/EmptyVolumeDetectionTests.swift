import XCTest
@testable import SevenZipKit

final class EmptyVolumeDetectionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ name: String, bytes: Int) throws {
        try Data(count: bytes).write(to: directory.appendingPathComponent(name))
    }

    func testDetectsEmptyRarParts() throws {
        for part in ["01", "02", "03"] { try write("Set X.part\(part).rar", bytes: part == "02" ? 0 : 4) }
        let empty = SystemSevenZipBridge.emptySiblingVolumes(of: directory.appendingPathComponent("Set X.part01.rar"))
        XCTAssertEqual(empty, ["Set X.part02.rar"])
    }

    func testDetectsEmptyNumberedVolumes() throws {
        try write("a.7z.001", bytes: 4)
        try write("a.7z.002", bytes: 0)
        let empty = SystemSevenZipBridge.emptySiblingVolumes(of: directory.appendingPathComponent("a.7z.001"))
        XCTAssertEqual(empty, ["a.7z.002"])
    }

    func testIgnoresUnrelatedEmptyFilesAndSingleArchives() throws {
        try write("other.part01.rar", bytes: 0)
        try write("Set.part01.rar", bytes: 4)
        try write("plain.zip", bytes: 0)
        XCTAssertTrue(SystemSevenZipBridge.emptySiblingVolumes(of: directory.appendingPathComponent("Set.part01.rar")).isEmpty)
        XCTAssertTrue(SystemSevenZipBridge.emptySiblingVolumes(of: directory.appendingPathComponent("plain.zip")).isEmpty)
    }
}
