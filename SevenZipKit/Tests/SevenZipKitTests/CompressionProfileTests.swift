import Foundation
import Testing
@testable import SevenZipKit

@Suite("CompressionProfile")
struct CompressionProfileTests {

    @Test("ships built-in profiles with stable identities")
    func builtIns() {
        let allBuiltIn = CompressionProfile.builtIns.allSatisfy { $0.isBuiltIn }
        let stableIDs = CompressionProfile.builtIns.map(\.id) == CompressionProfile.builtIns.map(\.id)
        #expect(!CompressionProfile.builtIns.isEmpty)
        #expect(allBuiltIn)
        #expect(stableIDs)
    }

    @Test("the Encrypted profile requests a password and encrypted headers")
    func encryptedProfile() throws {
        let encrypted = try #require(CompressionProfile.builtIns.first { $0.name == "Encrypted" })
        #expect(encrypted.requiresPassword)
        #expect(encrypted.encryptFileNames)
        #expect(encrypted.format == .sevenZip)
    }

    @Test("the Split profile carries a volume size")
    func splitProfile() throws {
        let split = try #require(CompressionProfile.builtIns.first { $0.name.contains("Split") })
        #expect(split.volumeSize != nil)
        #expect((split.volumeSize ?? 0) > 0)
    }

    @Test("encodes and decodes round-trip")
    func codableRoundTrip() throws {
        let profile = CompressionProfile(
            name: "My Preset", format: .zip, level: .maximum,
            encryptFileNames: false, requiresPassword: true, volumeSize: 700 * 1024 * 1024
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CompressionProfile.self, from: data)
        #expect(decoded == profile)
    }
}
