import Foundation

/// Archive-level metadata reported by 7-Zip in the header of a listing.
public struct ArchiveProperties: Hashable, Sendable {
    /// The archive format, e.g. `7z`, `zip`, `rar`.
    public let format: String?

    /// Physical size of the archive file on disk, in bytes.
    public let physicalSize: UInt64?

    /// Size of the archive headers, in bytes.
    public let headersSize: UInt64?

    /// The primary compression method, e.g. `LZMA2:6k`.
    public let method: String?

    /// Whether the archive is solid.
    public let isSolid: Bool?

    /// Number of compression blocks.
    public let blocks: UInt64?

    public init(
        format: String?,
        physicalSize: UInt64?,
        headersSize: UInt64?,
        method: String?,
        isSolid: Bool?,
        blocks: UInt64?
    ) {
        self.format = format
        self.physicalSize = physicalSize
        self.headersSize = headersSize
        self.method = method
        self.isSolid = isSolid
        self.blocks = blocks
    }

    public static let unknown = ArchiveProperties(
        format: nil, physicalSize: nil, headersSize: nil,
        method: nil, isSolid: nil, blocks: nil
    )
}

/// An opened archive: its location on disk, its properties, and its contents.
public struct Archive: Hashable, Sendable {
    /// The archive file's location on disk.
    public let url: URL

    /// Archive-level metadata.
    public let properties: ArchiveProperties

    /// Every entry contained in the archive, in the order 7-Zip listed them.
    public let entries: [ArchiveEntry]

    public init(url: URL, properties: ArchiveProperties, entries: [ArchiveEntry]) {
        self.url = url
        self.properties = properties
        self.entries = entries
    }

    /// Total uncompressed size of all file entries.
    public var totalSize: UInt64 {
        entries.reduce(0) { $0 + ($1.isDirectory ? 0 : $1.size) }
    }

    /// Number of file (non-directory) entries.
    public var fileCount: Int {
        entries.lazy.filter { !$0.isDirectory }.count
    }

    /// Number of directory entries.
    public var folderCount: Int {
        entries.lazy.filter(\.isDirectory).count
    }
}
