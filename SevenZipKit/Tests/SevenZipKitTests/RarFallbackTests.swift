import XCTest
@testable import SevenZipKit

final class RarFallbackUnitTests: XCTestCase {
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

    // MARK: VolumeSetHealth

    func testHealthyRarSetIsNotDamaged() throws {
        for part in ["01", "02", "03"] { try write("Set.part\(part).rar", bytes: 4) }
        let health = VolumeSetHealth.assess(directory.appendingPathComponent("Set.part01.rar"))
        XCTAssertEqual(health, VolumeSetHealth(emptyVolumes: [], missingVolumeNumbers: []))
        XCTAssertEqual(health?.isDamaged, false)
    }

    func testEmptyAndMissingVolumesAreDetected() throws {
        try write("Set X.part01.rar", bytes: 4)
        try write("Set X.part02.rar", bytes: 0)
        try write("Set X.part04.rar", bytes: 4)
        let health = VolumeSetHealth.assess(directory.appendingPathComponent("Set X.part01.rar"))
        XCTAssertEqual(health?.emptyVolumes, ["Set X.part02.rar"])
        XCTAssertEqual(health?.missingVolumeNumbers, [3])
        XCTAssertEqual(health?.isDamaged, true)
    }

    func testNonPartNamesAreNotAssessed() throws {
        try write("plain.rar", bytes: 0)
        try write("a.7z.001", bytes: 0)
        XCTAssertNil(VolumeSetHealth.assess(directory.appendingPathComponent("plain.rar")))
        XCTAssertNil(VolumeSetHealth.assess(directory.appendingPathComponent("a.7z.001")))
    }

    func testOtherSetsInTheSameFolderAreIgnored() throws {
        try write("A.part01.rar", bytes: 4)
        try write("B.part01.rar", bytes: 0)
        let health = VolumeSetHealth.assess(directory.appendingPathComponent("A.part01.rar"))
        XCTAssertEqual(health?.isDamaged, false)
    }

    // MARK: unar arguments

    func testGlobCharactersAreEscaped() {
        XCTAssertEqual(RarFallbackEngine.escapedPattern("a[1].txt"), #"a\[1\].txt"#)
        XCTAssertEqual(RarFallbackEngine.escapedPattern("x*y?.txt"), #"x\*y\?.txt"#)
        XCTAssertEqual(RarFallbackEngine.escapedPattern(#"back\slash"#), #"back\\slash"#)
        XCTAssertEqual(RarFallbackEngine.escapedPattern("plain/dir"), "plain/dir")
    }

    func testExtractionArgumentsAreNeverInteractive() {
        for (policy, flag) in [(ExtractionRequest.OverwritePolicy.overwrite, "-f"), (.skip, "-s"), (.rename, "-r")] {
            let request = ExtractionRequest(
                archiveURL: URL(fileURLWithPath: "/a/Set.part01.rar"),
                destinationURL: URL(fileURLWithPath: "/dest"),
                overwritePolicy: policy
            )
            let arguments = RarFallbackEngine.extractionArguments(for: request)
            XCTAssertTrue(arguments.contains(flag))
            XCTAssertEqual(arguments.prefix(3), ["-D", "-o", "/dest"])
            XCTAssertTrue(arguments.contains("-nr"), "archives inside the archive must not be expanded, as with 7-Zip")
            XCTAssertEqual(arguments.last, "/a/Set.part01.rar")
        }
    }

    func testSelectionUsesDoubleDashAndFolderGlob() {
        let request = ExtractionRequest(
            archiveURL: URL(fileURLWithPath: "/a/Set.part01.rar"),
            destinationURL: URL(fileURLWithPath: "/dest"),
            password: "pw",
            selectedPaths: ["-weird[1].txt", "dir"]
        )
        let arguments = RarFallbackEngine.extractionArguments(for: request)
        XCTAssertTrue(arguments.contains("pw"))
        let tail = Array(arguments.drop { $0 != "--" })
        XCTAssertEqual(tail, ["--", #"-weird\[1\].txt"#, #"-weird\[1\].txt/*"#, "dir", "dir/*"])
    }

    // MARK: unar output

    func testOutputLinesAreParsed() {
        let ok = UnarOutputState.parse(line: "  snes-msu1/a b.pcm  (2597744 B)... OK.")
        XCTAssertEqual(ok?.name, "snes-msu1/a b.pcm")
        XCTAssertEqual(ok?.size, 2_597_744)
        XCTAssertNil(ok?.failureDetail)

        let bad = UnarOutputState.parse(
            line: "  x/y.pcm  (14918972 B, corrupted)... Failed! (Attempted to read more data than was available)"
        )
        XCTAssertEqual(bad?.name, "x/y.pcm")
        XCTAssertEqual(bad?.failureDetail, "Attempted to read more data than was available")

        XCTAssertNil(UnarOutputState.parse(line: "Successfully extracted to \"/dest\"."))
        XCTAssertNil(UnarOutputState.parse(line: "  somedir  (dir)... OK."))
    }

    func testStateAccumulatesAcrossSplitChunksAndCollectsFailures() {
        let last = LockedBox<ProgressInfo?>(nil)
        let state = UnarOutputState(totalBytes: 100) { last.value = $0 }
        state.consume("  a  (40 B)... OK.\n  b  (10 B, corr")
        state.consume("upted)... Failed! (bad data)\n")
        state.finish()
        XCTAssertEqual(state.failures, [UnarOutputState.Failure(name: "b", detail: "bad data")])
        XCTAssertEqual(last.value?.processedBytes, 50)
        XCTAssertEqual(last.value?.fractionCompleted ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(last.value?.bytesPerSecond ?? 0, 0, "the panel shows Speed from this")
        XCTAssertNotNil(last.value?.estimatedTimeRemaining, "the panel shows Remaining from this")
    }

    // MARK: lsar listing

    func testListingJSONIsParsed() throws {
        let json = """
        {"lsarFormatVersion":2,"lsarContents":[
          {"XADIndex":0,"XADIsDirectory":true,"XADFileName":"dir","XADFileSize":0,"XADCompressedSize":0,
           "XADLastModificationDate":"2026-10-05 19:05:00 +0000"},
          {"XADIndex":1,"XADFileName":"./dir/f1.txt","XADFileSize":2,"XADCompressedSize":2,
           "XADIsEncrypted":true,"XADCompressionName":"None",
           "XADLastModificationDate":"2026-10-05 19:05:00 +0000"},
          {"XADIndex":2,"XADFileSize":9}
        ]}
        """
        let (properties, entries) = try RarFallbackEngine.parseListing(Data(json.utf8))
        XCTAssertEqual(properties.format, "Rar")
        XCTAssertEqual(entries.map(\.path), ["dir", "dir/f1.txt"])
        XCTAssertEqual(entries[0].isDirectory, true)
        XCTAssertEqual(entries[1].size, 2)
        XCTAssertEqual(entries[1].isEncrypted, true)
        XCTAssertNotNil(entries[1].modified)
    }

    func testGarbageListingThrows() {
        XCTAssertThrowsError(try RarFallbackEngine.parseListing(Data("not json".utf8)))
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// End-to-end: a zip named like a RAR volume set with an empty sibling volume
/// must be routed through the bundled `lsar`/`unar` instead of 7-Zip.
final class RarFallbackIntegrationTests: XCTestCase {
    private var directory: URL!

    private static func engine(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { dir.deleteLastPathComponent() }
        return dir.appending(path: "App/Resources/Engine/\(name)")
    }

    override func setUpWithError() throws {
        for name in ["7zz", "lsar", "unar"] {
            try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: Self.engine(name).path), "\(name) not bundled")
        }
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func makeService() throws -> ArchiveService {
        let fallback = RarFallbackEngine(
            lister: try SevenZipExecutable(validatingURL: Self.engine("lsar")),
            extractor: try SevenZipExecutable(validatingURL: Self.engine("unar"))
        )
        return ArchiveService(
            executable: try SevenZipExecutable(validatingURL: Self.engine("7zz")),
            fallback: fallback
        )
    }

    private func makeDamagedSet() throws -> URL {
        let source = directory.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("dir"), withIntermediateDirectories: true)
        try "one".write(to: source.appendingPathComponent("dir/f1.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: source.appendingPathComponent("a[1].txt"), atomically: true, encoding: .utf8)
        try "decoy".write(to: source.appendingPathComponent("a1.txt"), atomically: true, encoding: .utf8)
        let archive = directory.appendingPathComponent("Set.part01.rar")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = source
        zip.arguments = ["-qr", archive.path, "dir", "a[1].txt", "a1.txt"]
        try zip.run()
        zip.waitUntilExit()
        try Data().write(to: directory.appendingPathComponent("Set.part02.rar"))
        return archive
    }

    func testDamagedSetListsAndExtractsThroughFallback() async throws {
        let archive = try makeDamagedSet()
        let service = try makeService()

        let opened = try await service.open(archiveAt: archive)
        XCTAssertEqual(Set(opened.entries.map(\.path)), ["dir", "dir/f1.txt", "a[1].txt", "a1.txt"])

        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try await service.extract(
            ExtractionRequest(
                archiveURL: archive, destinationURL: destination,
                selectedPaths: ["a[1].txt", "dir"], totalUncompressedSize: 6
            )
        ) { _ in }
        let fileManager = FileManager.default
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("a[1].txt"), encoding: .utf8), "two")
        XCTAssertTrue(fileManager.fileExists(atPath: destination.appendingPathComponent("dir/f1.txt").path))
        XCTAssertFalse(fileManager.fileExists(atPath: destination.appendingPathComponent("a1.txt").path), "glob must not match the decoy")
    }

    func testArchiveInsideTheArchiveIsExtractedAsAFileNotExpanded() async throws {
        let source = directory.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "inner".write(to: source.appendingPathComponent("in.txt"), atomically: true, encoding: .utf8)
        let inner = Process()
        inner.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); inner.currentDirectoryURL = source
        inner.arguments = ["-q", "inner.zip", "in.txt"]; try inner.run(); inner.waitUntilExit()
        let outer = directory.appendingPathComponent("Set.part01.rar")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); zip.currentDirectoryURL = source
        zip.arguments = ["-q", outer.path, "inner.zip"]; try zip.run(); zip.waitUntilExit()
        try Data().write(to: directory.appendingPathComponent("Set.part02.rar"))

        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try await makeService().extract(
            ExtractionRequest(archiveURL: outer, destinationURL: destination, totalUncompressedSize: 1)
        ) { _ in }

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("inner.zip").path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue, "with -nr the inner archive stays a file, as with 7-Zip")
    }

    func testFlattenedSelectionLandsInDestinationRoot() async throws {
        let archive = try makeDamagedSet()
        let service = try makeService()
        _ = try await service.open(archiveAt: archive)

        let destination = directory.appendingPathComponent("flat", isDirectory: true)
        try await service.extract(
            ExtractionRequest(
                archiveURL: archive, destinationURL: destination,
                selectedPaths: ["dir/f1.txt"], totalUncompressedSize: 3, flattenPaths: true
            )
        ) { _ in }
        let contents = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        XCTAssertEqual(contents, ["f1.txt"], "no scratch folder or nested path may be left behind")
    }
}

final class RarFallbackTestOutputTests: XCTestCase {
    func testParsesPassAndFailLines() {
        let state = LsarTestState(basis: nil) { _ in }
        state.consume("""
        Set.part01.rar: RAR (49 volumes)
        a/ok.pcm... OK.
        a/bad one.pcm... Checksum failed!
        b/cut.pcm... Unpacking failed!
        2 passed, 2 failed.

        """)
        state.finish()
        XCTAssertEqual(state.passed, 1)
        XCTAssertEqual(state.failures, ["a/bad one.pcm (Checksum failed)", "b/cut.pcm (Unpacking failed)"])
    }

    func testAllPassingHasNoFailures() {
        let state = LsarTestState(basis: nil) { _ in }
        state.consume("x: Zip\na... OK.\nb... OK.\n2 passed, 0 failed.\n")
        state.finish()
        XCTAssertEqual(state.passed, 2)
        XCTAssertTrue(state.failures.isEmpty)
    }

    func testIntegrityErrorMessageListsFilesAndHintsAtPassword() {
        let message = ArchiveError.integrityFailures(passed: 0, failed: ["a (Unpacking failed)"]).errorDescription ?? ""
        XCTAssertTrue(message.contains("• a (Unpacking failed)"))
        XCTAssertTrue(message.contains("check that the password is correct"))
        let many = ArchiveError.integrityFailures(passed: 3, failed: (1...7).map { "f\($0)" }).errorDescription ?? ""
        XCTAssertTrue(many.contains("and 2 more"))
        XCTAssertFalse(many.contains("password"))
    }
}

final class LsarTestProgressTests: XCTestCase {
    func testProgressFollowsFinishedFileSizesAcrossSplitChunks() {
        let last = LockedBox<ProgressInfo?>(nil)
        let basis = TestProgressBasis(totalBytes: 100, entrySizes: ["a": 40, "dir/b c": 60])
        let state = LsarTestState(basis: basis) { last.value = $0 }
        state.consume("Set.part01.rar: RAR (3 volumes)\na... OK.\ndir/b")
        XCTAssertEqual(last.value?.processedBytes, 40)
        XCTAssertEqual(last.value?.fractionCompleted ?? 0, 0.4, accuracy: 0.0001)
        state.consume(" c... Checksum failed!\n")
        state.finish()
        XCTAssertEqual(last.value?.processedBytes, 100)
        XCTAssertEqual(last.value?.currentFile, "dir/b c")
        XCTAssertEqual(state.passed, 1)
        XCTAssertEqual(state.failures, ["dir/b c (Checksum failed)"])
    }

    func testNoBasisReportsNothingButStillCountsResults() {
        let called = LockedBox(false)
        let state = LsarTestState(basis: nil) { _ in called.value = true }
        state.consume("x... OK.\n")
        XCTAssertFalse(called.value)
        XCTAssertEqual(state.passed, 1)
    }

    func testUnknownNamesDoNotAdvanceProgress() {
        let last = LockedBox<ProgressInfo?>(nil)
        let state = LsarTestState(basis: TestProgressBasis(totalBytes: 10, entrySizes: ["a": 10])) { last.value = $0 }
        state.consume("zzz... OK.\n")
        XCTAssertEqual(last.value?.processedBytes, 0)
    }
}

/// Real engines end to end: progress must reach 100% on a passing archive, for
/// both the fallback path (`lsar -t`) and the regular one (`7zz t -bsp1`).
final class TestProgressIntegrationTests: XCTestCase {
    private var directory: URL!

    private static func engine(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { dir.deleteLastPathComponent() }
        return dir.appending(path: "App/Resources/Engine/\(name)")
    }

    override func setUpWithError() throws {
        for name in ["7zz", "lsar"] {
            try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: Self.engine(name).path), "\(name) not bundled")
        }
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func makeService() throws -> ArchiveService {
        ArchiveService(
            executable: try SevenZipExecutable(validatingURL: Self.engine("7zz")),
            fallback: RarFallbackEngine(
                lister: try SevenZipExecutable(validatingURL: Self.engine("lsar")),
                extractor: try SevenZipExecutable(validatingURL: Self.engine("lsar"))
            )
        )
    }

    private func run(_ tool: String, _ arguments: [String], in dir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.currentDirectoryURL = dir
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    private func makeSource() throws -> URL {
        let source = directory.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try String(repeating: "alpha ", count: 20_000).write(to: source.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try String(repeating: "beta ", count: 40_000).write(to: source.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        return source
    }

    private func basis() -> TestProgressBasis {
        TestProgressBasis(totalBytes: 120_000 + 200_000, entrySizes: ["a.txt": 120_000, "b.txt": 200_000])
    }

    func testFallbackTestReportsProgressToOneHundredPercent() async throws {
        let source = try makeSource()
        let archive = directory.appendingPathComponent("Set.part01.rar")
        try run("/usr/bin/zip", ["-qr", archive.path, "a.txt", "b.txt"], in: source)
        try Data().write(to: directory.appendingPathComponent("Set.part02.rar"))

        let seen = LockedBox<[Double]>([])
        let ok = try await makeService().test(
            archiveAt: archive, selectedPaths: [], password: nil, basis: basis()
        ) { info in seen.value.append(info.fractionCompleted) }
        XCTAssertTrue(ok)
        XCTAssertEqual(seen.value.last ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(seen.value, seen.value.sorted(), "progress must never go backwards")
    }

    func testRegularTestReportsProgressAndStillDetectsSuccess() async throws {
        let source = try makeSource()
        let archive = directory.appendingPathComponent("plain.7z")
        try run(Self.engine("7zz").path, ["a", "-t7z", archive.path, "a.txt", "b.txt"], in: source)

        let seen = LockedBox<[Double]>([])
        let ok = try await makeService().test(
            archiveAt: archive, selectedPaths: [], password: nil, basis: basis()
        ) { info in seen.value.append(info.fractionCompleted) }
        XCTAssertTrue(ok, "adding -bsp1 must not break the 'Everything is Ok' check")
        XCTAssertEqual(seen.value.last ?? 0, 1, accuracy: 0.0001)
    }
}


final class PartialExtractionMessageTests: XCTestCase {
    func testListsFilesAndSaysEverythingElseWasExtracted() {
        let message = ArchiveError.partialExtraction(failed: ["a (bad data)", "b (Checksum failed)"], destinationIssue: false).errorDescription ?? ""
        XCTAssertTrue(message.hasPrefix("Everything else was extracted"))
        XCTAssertTrue(message.contains("• a (bad data)"))
        XCTAssertFalse(message.contains("7-Zip"), "must not blame the 7-Zip engine for the fallback engine")
        XCTAssertFalse(message.contains("writing to the destination"))
    }

    func testWriteFailuresPointAtTheDestinationNotTheArchive() {
        let message = ArchiveError.partialExtraction(failed: ["x (Failed to write to file)"], destinationIssue: true).errorDescription ?? ""
        XCTAssertTrue(message.contains("writing to the destination"))
        XCTAssertTrue(message.contains("Extract just those files again"))
    }

    func testShowsTenAndCountsTheRest() {
        let many = (1...13).map { "f\($0) (bad)" }
        let message = ArchiveError.partialExtraction(failed: many, destinationIssue: false).errorDescription ?? ""
        XCTAssertTrue(message.contains("• f10 (bad)"))
        XCTAssertFalse(message.contains("• f11 (bad)"))
        XCTAssertTrue(message.contains("and 3 more"))
    }
}


final class LineBufferTests: XCTestCase {
    func testHoldsBackAPartialLineUntilItIsComplete() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.feed("one\ntw"), ["one"])
        XCTAssertEqual(buffer.feed("o\nthree"), ["two"])
        XCTAssertEqual(buffer.flush(), "three")
        XCTAssertNil(buffer.flush(), "flush must hand the leftover over only once")
    }

    func testEmptyChunksAndBlankLines() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.feed(""), [])
        XCTAssertEqual(buffer.feed("\n\n"), ["", ""])
    }
}

final class FlattenSafetyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMovesAFileFoundInsideTheScratchFolder() throws {
        let scratch = root.appendingPathComponent("scratch"), destination = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("d"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "x".write(to: scratch.appendingPathComponent("d/f.txt"), atomically: true, encoding: .utf8)
        try RarFallbackEngine.moveFlattened(selectedPaths: ["d/f.txt"], from: scratch, to: destination, policy: .overwrite)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("f.txt").path))
    }

    func testNeverMovesAFileReachedThroughASymlinkOutOfTheScratchFolder() throws {
        let scratch = root.appendingPathComponent("scratch"), destination = root.appendingPathComponent("dest")
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "secret".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        // What a malicious archive could leave behind: a folder link pointing out.
        try FileManager.default.createSymbolicLink(at: scratch.appendingPathComponent("a"), withDestinationURL: outside)

        try RarFallbackEngine.moveFlattened(selectedPaths: ["a/secret.txt"], from: scratch, to: destination, policy: .overwrite)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.appendingPathComponent("secret.txt").path), "the real file must stay where it was")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("secret.txt").path))
    }

    func testRemovesOnlyOldScratchFoldersOfThisApp() throws {
        let fileManager = FileManager.default
        let oldScratch = root.appendingPathComponent(".7zip4mac-\(UUID().uuidString)")
        let freshScratch = root.appendingPathComponent(".7zip4mac-\(UUID().uuidString)")
        let unrelated = root.appendingPathComponent(".7zip4mac-keep-me")
        for url in [oldScratch, freshScratch, unrelated] { try fileManager.createDirectory(at: url, withIntermediateDirectories: true) }
        try fileManager.setAttributes([.modificationDate: Date.now.addingTimeInterval(-2 * 86_400)], ofItemAtPath: oldScratch.path)

        RarFallbackEngine.removeStaleScratch(in: root)

        XCTAssertFalse(fileManager.fileExists(atPath: oldScratch.path))
        XCTAssertTrue(fileManager.fileExists(atPath: freshScratch.path), "a run in progress must not be touched")
        XCTAssertTrue(fileManager.fileExists(atPath: unrelated.path), "only UUID-named folders are ours")
    }
}
