import Foundation

/// A single item (file or folder) stored inside an archive.
///
/// Value type, `Sendable` and `Identifiable` so it can cross actor
/// boundaries and drive SwiftUI collections directly.
public struct ArchiveEntry: Identifiable, Hashable, Sendable {
    /// The full path of the entry inside the archive. Also used as the identity.
    public let path: String

    /// Whether this entry is a directory.
    public let isDirectory: Bool

    /// Uncompressed size in bytes.
    public let size: UInt64

    /// Compressed size in bytes, when 7-Zip reports it for this entry.
    /// Solid archives only report a packed size on the first entry of a block,
    /// so this is optional per entry.
    public let packedSize: UInt64?

    /// Last-modified timestamp, when available.
    public let modified: Date?

    /// CRC checksum as reported by 7-Zip (hex), when available.
    public let crc: String?

    /// Whether the entry's data is encrypted.
    public let isEncrypted: Bool

    /// Compression method reported for the entry (e.g. `LZMA2:6k`).
    public let method: String?

    /// Raw attribute string reported by 7-Zip (e.g. `A -rw-r--r--`).
    public let attributes: String?

    public var id: String { path }

    /// The display name: the last path component.
    public var name: String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }

    /// The parent directory path inside the archive, or empty for top level.
    public var parentPath: String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        var components = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count > 1 else { return "" }
        components.removeLast()
        return components.joined(separator: "/")
    }

    public init(
        path: String,
        isDirectory: Bool,
        size: UInt64,
        packedSize: UInt64?,
        modified: Date?,
        crc: String?,
        isEncrypted: Bool,
        method: String?,
        attributes: String?
    ) {
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.packedSize = packedSize
        self.modified = modified
        self.crc = crc
        self.isEncrypted = isEncrypted
        self.method = method
        self.attributes = attributes
    }
}
