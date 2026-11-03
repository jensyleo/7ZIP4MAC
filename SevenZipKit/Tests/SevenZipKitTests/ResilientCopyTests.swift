import Foundation
import Testing
@testable import SevenZipKit

@Suite("Resilient copy")
struct ResilientCopyTests {
    private func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "7zk-rc-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a file is copied whole, with its date")
    func copiesAFile() throws {
        let dir = try workspace(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "a.bin")
        let payload = Data((0..<9_000_000).map { UInt8($0 & 0xFF) })   // more than one 4 MB piece
        try payload.write(to: source)
        let date = Date(timeIntervalSince1970: 1_500_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: source.path)
        let destination = dir.appending(path: "b.bin")
        try ResilientCopy.copyContentsOnly(at: source, to: destination)
        #expect(try Data(contentsOf: destination) == payload)
        let copiedDate = try destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(copiedDate == date)
    }

    @Test("a folder tree and a symlink are copied")
    func copiesAFolder() throws {
        let dir = try workspace(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "src", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source.appending(path: "sub/deep"), withIntermediateDirectories: true)
        try "one".write(to: source.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: source.appending(path: "sub/deep/b.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: source.appending(path: "link").path, withDestinationPath: "a.txt")
        let destination = dir.appending(path: "dst", directoryHint: .isDirectory)
        try ResilientCopy.copyContentsOnly(at: source, to: destination)
        #expect(try String(contentsOf: destination.appending(path: "sub/deep/b.txt"), encoding: .utf8) == "two")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.appending(path: "link").path) == "a.txt")
    }

    @Test("the public entry point copies like copyItem when nothing goes wrong")
    func plainCopy() throws {
        let dir = try workspace(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "a.txt")
        try "hello".write(to: source, atomically: true, encoding: .utf8)
        let destination = dir.appending(path: "b.txt")
        try ResilientCopy.copyItem(at: source, to: destination)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "hello")
    }

    @Test("a missing source fails and leaves nothing at the destination")
    func missingSource() throws {
        let dir = try workspace(); defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appending(path: "b.txt")
        #expect(throws: (any Error).self) { try ResilientCopy.copyItem(at: dir.appending(path: "nope"), to: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
