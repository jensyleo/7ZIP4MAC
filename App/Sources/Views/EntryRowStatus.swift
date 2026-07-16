import SwiftUI
import SevenZipKit

/// Visual status of an archive entry row: a small, meaningful set of tints
/// rather than one per property.
enum EntryRowStatus: CaseIterable {
    case encrypted
    case folder
    case normal

    static func of(_ entry: ArchiveEntry) -> EntryRowStatus {
        if entry.isEncrypted { return .encrypted }
        if entry.isDirectory { return .folder }
        return .normal
    }

    /// Legend label.
    var label: String {
        switch self {
        case .encrypted: return "Encrypted"
        case .folder: return "Folder"
        case .normal: return "File"
        }
    }

    /// Tint applied to the row's name text. `nil` means the default color.
    var tint: Color? {
        switch self {
        case .encrypted: return .orange
        case .folder: return .accentColor
        case .normal: return nil
        }
    }
}
