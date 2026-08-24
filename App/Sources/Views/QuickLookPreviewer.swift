import AppKit
import Quartz

/// Wires one window into macOS's single, app-wide `QLPreviewPanel` via the
/// standard `NSResponder` "preview panel controller" protocol
/// (`acceptsPreviewPanelControl`/`beginPreviewPanelControl`/
/// `endPreviewPanelControl`).
///
/// The previous implementation skipped that protocol entirely and just
/// called `panel.makeKeyAndOrderFront` directly, assigning `dataSource`
/// unconditionally. Since 7ZIP4MAC supports multiple windows sharing that
/// one panel, that meant nothing ever told AppKit which window currently
/// "owns" it — clicking a different row (which never touched Quick Look
/// code at all) left the panel showing a stale item with no way to
/// reconcile state, and closing/reopening it intermittently got the panel
/// into a state where Space/Close no longer worked ("no permite cerrar...
/// es aleatorio"). Implementing the real protocol lets AppKit hand control
/// between windows correctly, and `toggle(urls:)` below makes Space/⌘Y
/// behave like Finder's (press again to close) instead of only ever
/// reopening.
@MainActor
final class QuickLookPanelController: NSResponder {
    // QLPreviewPanel invokes the data-source methods on the main thread, and
    // we only mutate this from the main actor, so the unchecked store is safe.
    nonisolated(unsafe) private var items: [NSURL] = []
    private weak var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
        super.init()
        // NSWindow.nextResponder is nil by default and (unlike most responder
        // links) not retained — inserting ourselves here puts us on the
        // responder chain QLPreviewPanel walks to find a controller willing
        // to take charge of the shared panel. `ArchiveWindowRoot` holds the
        // strong reference that keeps this instance alive.
        //
        // Deferred one runloop tick: assigning this synchronously, while
        // `WindowAccessor` is still resolving the window during its own
        // early setup, lands inside AppKit's
        // `_setUpFirstResponderBeforeBecomingVisible` and crashes with
        // `NSInternalInconsistencyException` (confirmed by bisection — the
        // customizable toolbar was not the cause). The window is already
        // fully set up by the time this queued block runs.
        DispatchQueue.main.async { [weak window, weak self] in
            guard let window, let self else { return }
            // Splice in rather than overwrite: preserve whatever the window's
            // nextResponder already was (normally nil, but not guaranteed —
            // clobbering it would silently truncate the responder chain for
            // everything else that relies on it) by continuing the chain
            // through it after ourselves.
            self.nextResponder = window.nextResponder
            window.nextResponder = self
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows the panel for `urls`, or closes it if it's already open under
    /// this window's control — the Space-bar/⌘Y toggle, matching Finder.
    func toggle(urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if isVisible {
            panel.orderOut(nil)
            return
        }
        items = urls.map { $0 as NSURL }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Shows/refreshes the panel for `urls` without ever closing it — used
    /// when the user's selection changes while the panel is already open, so
    /// a plain click updates the preview instead of leaving it stale.
    func refresh(urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        items = urls.map { $0 as NSURL }
        if isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Whether the shared panel is on screen *and* currently under this
    /// window's control (not some other window's).
    var isVisible: Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(),
              panel.dataSource === self else { return false }
        return panel.isVisible
    }

    // MARK: - QLPreviewPanelController (NSResponder)

    // AppKit doesn't mark these NSResponder overrides `@MainActor` in the
    // Swift overlay, even though QLPreviewPanel only ever calls them on the
    // main thread — same reasoning as the `nonisolated` data-source methods
    // below, hopped onto the main actor explicitly to touch our state.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { window != nil }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            if panel.dataSource === self { panel.dataSource = nil }
            if panel.delegate === self { panel.delegate = nil }
        }
    }
}

extension QuickLookPanelController: QLPreviewPanelDataSource {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        items[index]
    }
}

extension QuickLookPanelController: QLPreviewPanelDelegate {}
