import Foundation
import Testing
@testable import SevenZipKit

@Suite("ProgressParser")
struct ProgressParserTests {

    @Test("parses a plain percentage token")
    func parsesPercent() {
        var parser = ProgressParser()
        let lines = parser.consume("  42%\u{08}\u{08}\u{08}\u{08}")
        #expect(lines.count == 1)
        #expect(lines.first?.percent == 42)
        #expect(lines.first?.currentFile == nil)
    }

    @Test("parses percentage with a current file")
    func parsesPercentWithFile() {
        var parser = ProgressParser()
        let lines = parser.consume(" 73% 7 - folder/sub/file.bin\u{08}\u{08}")
        #expect(lines.first?.percent == 73)
        #expect(lines.first?.currentFile == "folder/sub/file.bin")
    }

    @Test("parses the '+' separator used while compressing")
    func parsesCompressionFile() {
        var parser = ProgressParser()
        let lines = parser.consume(" 50% 20 + ctest/docs/f_28.txt\u{08}")
        #expect(lines.first?.percent == 50)
        #expect(lines.first?.currentFile == "ctest/docs/f_28.txt")
    }

    @Test("handles carriage-return redraws")
    func handlesCarriageReturn() {
        var parser = ProgressParser()
        let lines = parser.consume(" 10%\r 20%\r 30%\r")
        #expect(lines.map(\.percent) == [10, 20, 30])
    }

    @Test("joins a token split across two chunks")
    func joinsSplitToken() {
        var parser = ProgressParser()
        let first = parser.consume(" 5")
        #expect(first.isEmpty)
        let second = parser.consume("5% 2 - a.txt\u{08}")
        #expect(second.first?.percent == 55)
        #expect(second.first?.currentFile == "a.txt")
    }

    @Test("ignores non-progress lines")
    func ignoresNoise() {
        var parser = ProgressParser()
        let lines = parser.consume("Extracting archive: big.7z\nEverything is Ok\n")
        #expect(lines.isEmpty)
    }

    @Test("clamps out-of-range percentages")
    func clampsRange() {
        #expect(ProgressParser.parse("150%")?.percent == 100)
    }
}
