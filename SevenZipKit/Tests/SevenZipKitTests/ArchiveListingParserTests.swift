import Foundation
import Testing
@testable import SevenZipKit

@Suite("ArchiveListingParser")
struct ArchiveListingParserTests {

    private func loadFixture() throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: "listing_slt", withExtension: "txt"),
            "fixture listing_slt.txt must be bundled with the tests"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("parses archive header properties")
    func parsesHeader() throws {
        let (properties, _) = try ArchiveListingParser.parse(loadFixture())
        #expect(properties.format == "7z")
        #expect(properties.physicalSize == 281)
        #expect(properties.headersSize == 225)
        #expect(properties.method == "LZMA2:6k")
        #expect(properties.isSolid == true)
        #expect(properties.blocks == 1)
    }

    @Test("parses the correct number of entries")
    func parsesEntryCount() throws {
        let (_, entries) = try ArchiveListingParser.parse(loadFixture())
        #expect(entries.count == 5)
    }

    @Test("distinguishes directories from files")
    func detectsDirectories() throws {
        let (_, entries) = try ArchiveListingParser.parse(loadFixture())
        let directories = entries.filter(\.isDirectory).map(\.path)
        #expect(directories == ["sample", "sample/sub"])
        let files = entries.filter { !$0.isDirectory }.map(\.path)
        #expect(files == ["sample/a.txt", "sample/sub/big.dat", "sample/sub/c.log"])
    }

    @Test("parses sizes, CRC and method for a file entry")
    func parsesFileDetails() throws {
        let (_, entries) = try ArchiveListingParser.parse(loadFixture())
        let file = try #require(entries.first { $0.path == "sample/a.txt" })
        #expect(file.size == 12)
        #expect(file.packedSize == 56)
        #expect(file.crc == "AF083B2D")
        #expect(file.method == "LZMA2:6k")
        #expect(file.isEncrypted == false)
    }

    @Test("leaves packed size nil when the engine omits it")
    func parsesMissingPackedSize() throws {
        let (_, entries) = try ArchiveListingParser.parse(loadFixture())
        let file = try #require(entries.first { $0.path == "sample/sub/big.dat" })
        #expect(file.packedSize == nil)
        #expect(file.size == 5000)
    }

    @Test("parses the modified timestamp to whole-second precision")
    func parsesModifiedDate() throws {
        let (_, entries) = try ArchiveListingParser.parse(loadFixture())
        let file = try #require(entries.first { $0.path == "sample/a.txt" })
        let date = try #require(file.modified)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 8)
        #expect(components.second == 47)
    }

    @Test("derives name and parent path from the full path")
    func derivesNameAndParent() throws {
        let (_, entries) = try ArchiveListingParser.parse(loadFixture())
        let file = try #require(entries.first { $0.path == "sample/sub/c.log" })
        #expect(file.name == "c.log")
        #expect(file.parentPath == "sample/sub")
    }

    @Test("throws when the entries section is missing")
    func throwsOnMalformedOutput() {
        let garbage = "not a 7-zip listing at all\njust some text"
        #expect(throws: ArchiveError.self) {
            try ArchiveListingParser.parse(garbage)
        }
    }
}
