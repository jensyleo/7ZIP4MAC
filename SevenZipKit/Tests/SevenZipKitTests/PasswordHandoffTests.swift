import Foundation
import Testing
@testable import SevenZipKit

@Suite("Password hand-off")
struct PasswordHandoffTests {

    @Test("a normal password never appears in the arguments")
    func secretStaysOffTheCommandLine() {
        let opening = PasswordHandoff("hunter2 ñ'\"$x")
        #expect(opening.argument == nil)
        #expect(opening.input == "hunter2 ñ'\"$x\n")
        let creating = PasswordHandoff("pw", creating: true)
        #expect(creating.argument == "-p")
        #expect(creating.input == "pw\npw\n")
    }

    @Test("passwords a terminal cannot carry keep the argument form")
    func unusablePasswordsFallBack() {
        #expect(PasswordHandoff("").input == nil)
        #expect(PasswordHandoff("").argument == "-p")
        #expect(PasswordHandoff("a\nb").input == nil)
        #expect(PasswordHandoff("a\nb").argument == "-pa\nb")
        #expect(PasswordHandoff(String(repeating: "x", count: 1001)).input == nil)
    }
}

/// Real 7-Zip, password supplied only through the terminal input.
@Suite(.enabled(if: SevenZipEngine.isAvailable), .serialized)
struct PasswordHandoffEngineTests {
    private let fm = FileManager.default

    private func service() throws -> ArchiveService {
        ArchiveService(executable: try SevenZipExecutable(validatingURL: SevenZipEngine.url))
    }

    private func workspace() throws -> URL {
        let base = fm.temporaryDirectory.appending(path: "7zk-pw-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = base.appending(path: "root", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "alpha".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: root.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        return base
    }

    @Test("create, list, test, extract, rename and delete with a password",
          arguments: [(ArchiveFormat.sevenZip, true), (.sevenZip, false), (.zip, false)])
    func fullCycle(format: ArchiveFormat, encryptNames: Bool) async throws {
        let base = try workspace()
        defer { try? fm.removeItem(at: base) }
        let password = "p ss'\"w0rd $1"
        let archive = base.appending(path: "x.\(format.fileExtension)")
        let svc = try service()

        try await svc.compress(
            CompressionRequest(destinationURL: archive, sourceURLs: [base.appending(path: "root")],
                               format: format, level: .fast, password: password,
                               encryptFileNames: encryptNames),
            progress: { _ in }
        )

        let opened = try await svc.open(archiveAt: archive, password: password)
        #expect(opened.fileCount == 2)
        if encryptNames {
            await #expect(throws: ArchiveError.wrongPassword) { _ = try await svc.open(archiveAt: archive, password: "nope") }
        }

        #expect(try await svc.test(archiveAt: archive, selectedPaths: [], password: password))
        await #expect(throws: ArchiveError.wrongPassword) {
            _ = try await svc.test(archiveAt: archive, selectedPaths: [], password: "nope")
        }

        let out = base.appending(path: "out", directoryHint: .isDirectory)
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        try await svc.extract(
            ExtractionRequest(archiveURL: archive, destinationURL: out, password: password, selectedPaths: []),
            progress: { _ in }
        )
        #expect(try String(contentsOf: out.appending(path: "root/b.txt"), encoding: .utf8) == "beta")

        try await svc.rename(archiveAt: archive, from: "root/a.txt", to: "root/z.txt", password: password)
        try await svc.delete(archiveAt: archive, paths: ["root/b.txt"], password: password)
        let after = try await svc.open(archiveAt: archive, password: password)
        #expect(after.entries.map(\.path).contains("root/z.txt"))
        #expect(!after.entries.map(\.path).contains("root/b.txt"))
    }
}

/// A tiny file that unpacks to far more than the disk can take must be refused.
@Suite(.enabled(if: SevenZipEngine.isAvailable), .serialized)
struct UnpackedTooLargeTests {
    private func makeGzip(megabytes: Int, in dir: URL) throws -> URL {
        let raw = dir.appending(path: "zeros.bin")
        try Data(count: megabytes << 20).write(to: raw)
        let gz = dir.appending(path: "zeros.bin.gz")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        p.arguments = ["-k", "-f", raw.path]
        try p.run(); p.waitUntilExit()
        try FileManager.default.removeItem(at: raw)
        return gz
    }

    @Test("a single-stream archive that outgrows the limit is not opened, and leaves no scratch behind")
    func refusesBomb() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "7zk-bomb-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let gz = try makeGzip(megabytes: 200, in: dir)
        let service = ArchiveService(
            bridge: SystemSevenZipBridge(executable: try SevenZipExecutable(validatingURL: SevenZipEngine.url)),
            unwrapLimit: 1 << 20
        )
        await #expect(throws: ArchiveError.unpackedTooLarge) { _ = try await service.open(archiveAt: gz, password: nil) }
    }

    @Test("within the limit it opens as before")
    func opensNormally() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "7zk-bomb-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let gz = try makeGzip(megabytes: 2, in: dir)
        let service = ArchiveService(
            bridge: SystemSevenZipBridge(executable: try SevenZipExecutable(validatingURL: SevenZipEngine.url))
        )
        let archive = try await service.open(archiveAt: gz, password: nil)
        #expect(archive.entries.count == 1)
    }

    @Test("the default limit leaves room on the disk")
    func defaultLimitIsSane() {
        let limit = ArchiveService.defaultUnwrapLimit(for: FileManager.default.temporaryDirectory)
        #expect(limit >= 256 << 20)
    }
}
