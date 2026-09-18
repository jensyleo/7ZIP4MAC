import AppKit
import SwiftUI

/// Intercepts every "open this file" request (Finder double-click, Open
/// With, `open -a`) at the AppKit level, before SwiftUI's own automatic
/// per-document window handling gets a chance to run.
///
/// SwiftUI's `WindowGroup(for:)` opens a window automatically whenever such a
/// request arrives, with no way to ask first whether that URL is already
/// open elsewhere — for a repeat request it briefly created (and had to
/// close) a visible, empty scaffold window before this delegate existed.
/// Deciding here, first, means a duplicate request never gets as far as
/// creating a window at all.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openWindow: OpenWindowAction?

    /// Set as soon as this delegate is asked to open a file — which AppKit
    /// does before `applicationDidFinishLaunching`, i.e. before SwiftUI's
    /// `WindowGroup` creates its own automatic launch window. Read by
    /// `ArchiveWindowRoot` to recognize *that* automatic window as a
    /// scaffold too, on a cold launch by double-clicking an archive: it
    /// resolves as this launch's *first* window (normally the signal that
    /// it's the real, single empty window a plain launch shows), but a real
    /// archive window for `urls` is already known to be on its way, so
    /// there's no legitimate reason for an empty one to stay open here too
    /// ("la app se abre 2 veces" — 2026-09-17).
    nonisolated(unsafe) static var isOpeningFileAtLaunch = false

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        Self.isOpeningFileAtLaunch = true
        for url in urls {
            guard AppURLRouter.command(for: url) != nil else { continue }
            if OpenArchiveWindowRegistry.focusIfOpen(url) { continue }
            openWindow?(value: url as URL?)
        }
    }
}
