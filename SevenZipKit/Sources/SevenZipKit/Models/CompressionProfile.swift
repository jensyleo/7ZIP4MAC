import Foundation

/// A named preset of compression settings the user can pick in one click.
public struct CompressionProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var format: ArchiveFormat
    public var level: CompressionLevel
    /// Encrypt entry names (7-Zip only, when a password is supplied).
    public var encryptFileNames: Bool
    /// Whether this profile is meant to be encrypted (the UI should ask for a
    /// password when it is chosen).
    public var requiresPassword: Bool
    /// Split size in bytes, or nil for a single file.
    public var volumeSize: UInt64?
    /// Built-in profiles ship with the app and cannot be deleted.
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        format: ArchiveFormat,
        level: CompressionLevel,
        encryptFileNames: Bool = false,
        requiresPassword: Bool = false,
        volumeSize: UInt64? = nil,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.level = level
        self.encryptFileNames = encryptFileNames
        self.requiresPassword = requiresPassword
        self.volumeSize = volumeSize
        self.isBuiltIn = isBuiltIn
    }
}

public extension CompressionProfile {
    /// Fixed identifiers so a built-in keeps its identity across launches.
    private static func builtInID(_ n: UInt8) -> UUID {
        UUID(uuid: (0x7A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, n))
    }

    /// One gibibyte, for volume sizes.
    private static let giB: UInt64 = 1024 * 1024 * 1024
    private static let miB: UInt64 = 1024 * 1024

    /// The profiles that ship with the app.
    static let builtIns: [CompressionProfile] = [
        CompressionProfile(id: builtInID(1), name: "Ultra Compression",
                           format: .sevenZip, level: .ultra, isBuiltIn: true),
        CompressionProfile(id: builtInID(2), name: "Fast Backup",
                           format: .sevenZip, level: .fastest, isBuiltIn: true),
        CompressionProfile(id: builtInID(3), name: "Encrypted",
                           format: .sevenZip, level: .normal,
                           encryptFileNames: true, requiresPassword: true, isBuiltIn: true),
        CompressionProfile(id: builtInID(4), name: "Source Code",
                           format: .sevenZip, level: .maximum, isBuiltIn: true),
        CompressionProfile(id: builtInID(5), name: "Photos",
                           format: .zip, level: .store, isBuiltIn: true),
        CompressionProfile(id: builtInID(6), name: "Split DVD (4.7 GB)",
                           format: .sevenZip, level: .normal,
                           volumeSize: 4_700 * miB, isBuiltIn: true),
    ]
}
