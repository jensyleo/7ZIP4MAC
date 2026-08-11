import AppKit

/// Tracks which window (if any) already has a given archive URL open, so a
/// second "open this file" request can focus that window instead of opening
/// a duplicate.
///
/// SwiftUI's own per-`WindowGroup` value dedup only tracks windows created
/// via `openWindow(value:)` *within that specific group* — it has no memory
/// of a URL that ended up loaded into the default, value-less window (e.g.
/// the empty window every launch starts with), so a second open of the same
/// file went to a *different* group and never matched. This fills that gap
/// with a registry that spans every window regardless of which group made it.
@MainActor
enum OpenArchiveWindowRegistry {
    private final class WeakWindowBox {
        weak var window: NSWindow?
        init(_ window: NSWindow) { self.window = window }
    }

    private final class WeakViewModelBox {
        weak var viewModel: ArchiveViewModel?
        init(_ viewModel: ArchiveViewModel) { self.viewModel = viewModel }
    }

    private static var windowsByURL: [URL: WeakWindowBox] = [:]
    private static var viewModelsByURL: [URL: WeakViewModelBox] = [:]

    // The same file can arrive as different (but equivalent) URLs — e.g.
    // `/tmp/...` is a symlink to `/private/tmp/...` on macOS — depending on
    // which code path resolved it. Resolving symlinks before using the URL as
    // a dictionary key makes those all collapse to the same entry.
    private static func canonical(_ url: URL) -> URL {
        url.resolvingSymlinksInPath()
    }

    static func register(_ url: URL, window: NSWindow, viewModel: ArchiveViewModel) {
        let key = canonical(url)
        windowsByURL[key] = WeakWindowBox(window)
        viewModelsByURL[key] = WeakViewModelBox(viewModel)
    }

    static func unregister(_ url: URL) {
        let key = canonical(url)
        windowsByURL.removeValue(forKey: key)
        viewModelsByURL.removeValue(forKey: key)
    }

    /// The live `ArchiveViewModel` for `url`'s window, if it's still open —
    /// used for a cross-archive move to delete the entry from its source
    /// archive with that window's own state (so its list refreshes
    /// immediately) instead of behind its back.
    static func viewModel(for url: URL) -> ArchiveViewModel? {
        viewModelsByURL[canonical(url)]?.viewModel
    }

    /// If `url` is already showing in a still-open window, brings it to front
    /// and returns `true`. Otherwise leaves everything untouched and returns
    /// `false` (a stale entry left by a window that closed without
    /// unregistering — shouldn't happen, but the weak reference makes it
    /// harmless either way — is pruned in the process).
    @discardableResult
    static func focusIfOpen(_ url: URL) -> Bool {
        let key = canonical(url)
        guard let window = windowsByURL[key]?.window else {
            windowsByURL.removeValue(forKey: key)
            return false
        }
        // Activate the app *before* ordering the specific window front:
        // macOS's own app-activation (bringing whichever window was last
        // frontmost forward) runs as part of dispatching the "open this
        // file" event to begin with — doing our own activation first, then
        // immediately layering the correct window on top, leaves the
        // smallest possible gap for the wrong one to be seen.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        closeEmptyWindows(except: window)
        return true
    }

    /// macOS opens a brand-new default (empty) window for every "open this
    /// file" request that reaches an already-running app — sometimes more
    /// than one for a single request — purely to have somewhere to route it.
    /// Once the file has actually landed in `keep` (an existing or
    /// newly-opened window), any other still-empty window was only ever
    /// scaffolding for that routing and would otherwise linger as clutter.
    private static func closeEmptyWindows(except keep: NSWindow) {
        for window in NSApp.windows where window !== keep && window.title == "7ZIP4MAC" && window.isVisible {
            window.close()
        }
    }
}
