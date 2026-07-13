import Foundation
import Testing
@testable import SevenZipKit

@Suite("CompressionRequest")
struct CompressionRequestTests {

    private func request(sources: [String]) -> CompressionRequest {
        CompressionRequest(
            destinationURL: URL(fileURLWithPath: "/tmp/out.7z"),
            sourceURLs: sources.map { URL(fileURLWithPath: $0) }
        )
    }

    @Test("uses the common parent as the working directory")
    func commonParent() {
        let r = request(sources: ["/Users/x/Documents/a.txt", "/Users/x/Documents/b/c.txt"])
        #expect(r.workingDirectory?.path == "/Users/x/Documents")
    }

    @Test("stores sources relative to the working directory")
    func relativeSources() {
        let r = request(sources: ["/Users/x/Documents/a.txt", "/Users/x/Documents/b"])
        #expect(r.sourceArguments == ["a.txt", "b"])
    }

    @Test("single source is stored by its basename")
    func singleSource() {
        let r = request(sources: ["/Users/x/Documents/report"])
        #expect(r.workingDirectory?.path == "/Users/x/Documents")
        #expect(r.sourceArguments == ["report"])
    }

    @Test("password and header encryption only apply to supporting formats")
    func formatCapabilities() {
        #expect(ArchiveFormat.sevenZip.supportsPassword)
        #expect(ArchiveFormat.sevenZip.supportsEncryptedHeaders)
        #expect(ArchiveFormat.zip.supportsPassword)
        #expect(!ArchiveFormat.zip.supportsEncryptedHeaders)
        #expect(!ArchiveFormat.tar.supportsPassword)
    }

    @Test("compression levels map to -mx values")
    func levels() {
        #expect(CompressionLevel.store.mxValue == 0)
        #expect(CompressionLevel.normal.mxValue == 5)
        #expect(CompressionLevel.ultra.mxValue == 9)
    }
}
