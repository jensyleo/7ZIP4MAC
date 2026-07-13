import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SevenZipKit

/// Renders the real macOS file-type icon for an archive entry — the same icon
/// Finder would show for that kind of file.
struct EntryIcon: View {
    let entry: ArchiveEntry

    var body: some View {
        if entry.isParentLink {
            Image(systemName: "arrow.turn.up.left")
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
        } else {
            Image(nsImage: IconProvider.icon(for: entry))
                .resizable()
                .frame(width: 16, height: 16)
        }
    }
}

/// Resolves and caches file-type icons by UTType.
enum IconProvider {
    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func icon(for entry: ArchiveEntry) -> NSImage {
        if entry.isDirectory {
            return workspaceIcon(for: .folder, key: "public.folder")
        }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
        return workspaceIcon(for: type, key: type.identifier)
    }

    private static func workspaceIcon(for type: UTType, key: String) -> NSImage {
        lock.lock()
        if let cached = cache[key] { lock.unlock(); return cached }
        lock.unlock()
        let image = NSWorkspace.shared.icon(for: type)
        lock.lock(); cache[key] = image; lock.unlock()
        return image
    }
}
