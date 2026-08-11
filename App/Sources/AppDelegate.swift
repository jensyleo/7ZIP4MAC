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

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard AppURLRouter.command(for: url) != nil else { continue }
            if OpenArchiveWindowRegistry.focusIfOpen(url) { continue }
            openWindow?(value: url as URL?)
        }
    }
}
