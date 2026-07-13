import Foundation

/// Describes an extraction to perform.
public struct ExtractionRequest: Sendable, Equatable {
    /// How to handle files that already exist at the destination.
    public enum OverwritePolicy: Sendable, Equatable {
        case overwrite
        case skip
        case rename

        /// The corresponding `7zz` switch.
        var switchArgument: String {
            switch self {
            case .overwrite: return "-aoa"
            case .skip: return "-aos"
            case .rename: return "-aou"
            }
        }
    }

    /// The archive to extract.
    public var archiveURL: URL

    /// The directory to extract into. It is created if it does not exist.
    public var destinationURL: URL

    /// Password for encrypted archives, if any. Never logged.
    public var password: String?

    /// Specific entry paths to extract. Empty extracts the whole archive.
    public var selectedPaths: [String]

    /// Overwrite behaviour at the destination.
    public var overwritePolicy: OverwritePolicy

    /// Total uncompressed size of what will be extracted, used to estimate
    /// throughput and ETA. Zero disables byte-based estimates.
    public var totalUncompressedSize: UInt64

    /// When true, extracts flat (7-Zip's `e` command) instead of preserving
    /// each entry's internal folder path (`x`) — e.g. extracting a single
    /// file that lives at "docs/report.pdf" inside the archive lands it
    /// directly at the destination, not under a re-created "docs/" folder.
    public var flattenPaths: Bool

    public init(
        archiveURL: URL,
        destinationURL: URL,
        password: String? = nil,
        selectedPaths: [String] = [],
        overwritePolicy: OverwritePolicy = .overwrite,
        totalUncompressedSize: UInt64 = 0,
        flattenPaths: Bool = false
    ) {
        self.archiveURL = archiveURL
        self.destinationURL = destinationURL
        self.password = password
        self.selectedPaths = selectedPaths
        self.overwritePolicy = overwritePolicy
        self.totalUncompressedSize = totalUncompressedSize
        self.flattenPaths = flattenPaths
    }
}
