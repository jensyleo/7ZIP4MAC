import Foundation
import SwiftUI
import UniformTypeIdentifiers
import SevenZipKit

/// Presentation-only helpers for rendering an ``ArchiveEntry`` in the UI.
extension ArchiveEntry {
    /// Whether this is the synthetic ".." row used to go up one folder,
    /// Windows-Explorer / 7-Zip-for-Windows style.
    var isParentLink: Bool { path == ".." }

    /// Human-readable uncompressed size, e.g. "5 KB". Empty for folders.
    var displaySize: String {
        isDirectory ? "—" : ByteFormatter.string(fromByteCount: Int64(size))
    }

    /// Human-readable compressed size, or "—" when the engine omitted it.
    var displayPackedSize: String {
        guard let packedSize else { return "—" }
        return ByteFormatter.string(fromByteCount: Int64(packedSize))
    }

    /// Localised modified date, or "—" when unknown.
    var displayModified: String {
        guard let modified else { return "—" }
        return DateFormatterCache.medium.string(from: modified)
    }

    /// The SF Symbol that best represents this entry.
    var symbolName: String {
        if isDirectory { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "rtf", "log": return "doc.text.fill"
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp": return "photo.fill"
        case "mp3", "wav", "aac", "flac", "m4a": return "music.note"
        case "mp4", "mov", "avi", "mkv", "m4v": return "film.fill"
        case "zip", "7z", "rar", "gz", "tar", "bz2", "xz": return "doc.zipper"
        case "pdf": return "doc.richtext.fill"
        case "app", "dmg", "pkg": return "app.fill"
        case "swift", "c", "cpp", "h", "m", "py", "js", "ts", "rs", "go", "java": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.fill"
        }
    }
}

/// Shared byte formatter (allocating a `ByteCountFormatter` per row is wasteful).
///
/// Only ever touched from the main thread during SwiftUI rendering, so the
/// unchecked static is safe in practice.
enum ByteFormatter {
    nonisolated(unsafe) private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func string(fromByteCount count: Int64) -> String {
        formatter.string(fromByteCount: count)
    }
}

/// Cached date formatters. Accessed only on the main thread during rendering.
enum DateFormatterCache {
    static let medium: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
