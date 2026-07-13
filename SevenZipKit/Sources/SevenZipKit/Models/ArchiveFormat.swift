import Foundation

/// An archive container format the app can create.
public enum ArchiveFormat: String, CaseIterable, Sendable, Identifiable, Codable {
    case sevenZip
    case zip
    case tar

    public var id: String { rawValue }

    /// The `7zz -t` type token.
    public var typeArgument: String {
        switch self {
        case .sevenZip: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        }
    }

    /// The file extension (without a dot).
    public var fileExtension: String {
        switch self {
        case .sevenZip: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        }
    }

    /// Human-facing name.
    public var displayName: String {
        switch self {
        case .sevenZip: return "7-Zip"
        case .zip: return "ZIP"
        case .tar: return "TAR"
        }
    }

    /// Whether the format supports encryption with a password.
    public var supportsPassword: Bool {
        switch self {
        case .sevenZip, .zip: return true
        case .tar: return false
        }
    }

    /// Whether the format supports encrypting entry names (7-Zip only).
    public var supportsEncryptedHeaders: Bool {
        self == .sevenZip
    }
}

/// Compression effort, mapped to the `7zz -mx` level.
public enum CompressionLevel: Int, CaseIterable, Sendable, Identifiable, Codable {
    case store = 0
    case fastest = 1
    case fast = 3
    case normal = 5
    case maximum = 7
    case ultra = 9

    public var id: Int { rawValue }

    /// The `-mx=` value.
    public var mxValue: Int { rawValue }

    public var displayName: String {
        switch self {
        case .store: return "Store (no compression)"
        case .fastest: return "Fastest"
        case .fast: return "Fast"
        case .normal: return "Normal"
        case .maximum: return "Maximum"
        case .ultra: return "Ultra"
        }
    }
}
