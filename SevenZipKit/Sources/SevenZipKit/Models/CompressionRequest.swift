import Foundation

/// Describes an archive to create.
public struct CompressionRequest: Sendable, Equatable {
    /// The archive file to create.
    public var destinationURL: URL

    /// The files and/or folders to add to the archive.
    public var sourceURLs: [URL]

    /// The container format.
    public var format: ArchiveFormat

    /// Compression effort.
    public var level: CompressionLevel

    /// Optional password. Ignored for formats that do not support it. Never logged.
    public var password: String?

    /// Encrypt entry names as well (7-Zip only; requires a password).
    public var encryptFileNames: Bool

    /// Total size of the sources, used to estimate throughput and ETA.
    public var totalSourceSize: UInt64

    /// Split the output into volumes of this many bytes each (nil = single file).
    public var volumeSize: UInt64?

    public init(
        destinationURL: URL,
        sourceURLs: [URL],
        format: ArchiveFormat = .sevenZip,
        level: CompressionLevel = .normal,
        password: String? = nil,
        encryptFileNames: Bool = false,
        totalSourceSize: UInt64 = 0,
        volumeSize: UInt64? = nil
    ) {
        self.destinationURL = destinationURL
        self.sourceURLs = sourceURLs
        self.format = format
        self.level = level
        self.password = password
        self.encryptFileNames = encryptFileNames
        self.totalSourceSize = totalSourceSize
        self.volumeSize = volumeSize
    }

    /// The directory the engine should run in so that source paths are stored
    /// relative to it — the deepest common ancestor of all sources.
    public var workingDirectory: URL? {
        guard let first = sourceURLs.first else { return nil }
        var common = first.deletingLastPathComponent().standardizedFileURL.pathComponents
        for url in sourceURLs.dropFirst() {
            let parent = url.deletingLastPathComponent().standardizedFileURL.pathComponents
            var shared: [String] = []
            for (a, b) in zip(common, parent) where a == b { shared.append(a) }
            common = shared
        }
        guard common.count > 1 else { return URL(fileURLWithPath: "/") }
        // pathComponents starts with "/"; rejoin without producing "//".
        let path = "/" + common.dropFirst().joined(separator: "/")
        return URL(fileURLWithPath: path)
    }

    /// The source arguments to pass to the engine: paths relative to
    /// ``workingDirectory`` when possible, otherwise absolute.
    public var sourceArguments: [String] {
        guard let base = workingDirectory?.standardizedFileURL.pathComponents else {
            return sourceURLs.map(\.path)
        }
        return sourceURLs.map { url in
            let parts = url.standardizedFileURL.pathComponents
            if parts.count > base.count, Array(parts.prefix(base.count)) == base {
                return parts.dropFirst(base.count).joined(separator: "/")
            }
            return url.path
        }
    }
}
