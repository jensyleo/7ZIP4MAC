import Foundation
import Testing
@testable import SevenZipKit

@Suite("BenchmarkParser")
struct BenchmarkParserTests {

    private func loadFixture() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "benchmark", withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("parses machine info")
    func machineInfo() throws {
        let r = BenchmarkParser.parse(try loadFixture())
        #expect(r.cpuModel == "Apple M4 10C10T")
        #expect(r.ramSizeMB == 16384)
        #expect(r.benchmarkThreads == 2)
    }

    @Test("parses the average compress/decompress figures")
    func averages() throws {
        let r = BenchmarkParser.parse(try loadFixture())
        #expect(r.compressSpeedKiBs == 26593)
        #expect(r.compressRatingMIPS == 27875)
        #expect(r.decompressSpeedKiBs == 234177)
        #expect(r.decompressRatingMIPS == 20410)
    }

    @Test("parses the total rating")
    func total() throws {
        let r = BenchmarkParser.parse(try loadFixture())
        #expect(r.totalRatingMIPS == 24143)
    }

    @Test("parses per-dictionary rows")
    func rows() throws {
        let r = BenchmarkParser.parse(try loadFixture())
        #expect(r.rows.count == 4)
        let first = try #require(r.rows.first)
        #expect(first.dictionary == 22)
        #expect(first.compressSpeedKiBs == 28472)
        #expect(first.compressRatingMIPS == 27698)
        #expect(first.decompressSpeedKiBs == 238919)
        #expect(first.decompressRatingMIPS == 20399)
    }
}
