import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SevenZipKit

/// Renders the real macOS file-type icon for an archive entry — the same icon
/// Finder would show for that kind of file.
struct EntryIcon: View {
    let entry: ArchiveEntry

    /// Slightly larger than a real file-type icon (16pt) — jensyleo's own
    /// request (2026-09-16) to make the ".." row read more clearly as a
    /// clickable "go up" control, since it's the one row with no real name
    /// alongside its icon (every other row's own hit area already covers
    /// the whole row, not just its icon — see `.contentShape` on the Name
    /// column's button).
    private static let parentLinkIconSize: CGFloat = 20

    var body: some View {
        if entry.isParentLink {
            Image(systemName: "arrow.turn.up.left")
                .font(.system(size: 13, weight: .medium))
                .frame(width: Self.parentLinkIconSize, height: Self.parentLinkIconSize)
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
    /// The size every icon here is ever displayed at (`EntryIcon`'s own
    /// `.frame(width: 16, height: 16)`).
    private static let displaySize = NSSize(width: 16, height: 16)

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
        // `NSWorkspace.shared.icon(for:)` returns a large (often 512×512)
        // multi-representation image. Handing that straight to a resizable
        // SwiftUI `Image` means AppKit has to pick/rescale a representation
        // on every single redraw — including the extra redraws a `Table`
        // row's hover-highlight state triggers — which showed up as visible
        // icon flicker on hover ("los iconos... parpadean... más cuando les
        // acerco el cursor", 2026-09-16). Resizing once here, at cache time,
        // means every later redraw just blits the same already-16×16 bitmap.
        let source = NSWorkspace.shared.icon(for: type)
        let resized = NSImage(size: displaySize)
        resized.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: displaySize),
            from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high]
        )
        resized.unlockFocus()
        lock.lock(); cache[key] = resized; lock.unlock()
        return resized
    }
}
