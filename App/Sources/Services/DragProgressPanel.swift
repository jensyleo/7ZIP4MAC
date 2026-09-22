import SwiftUI
import AppKit
import SevenZipKit

/// Live state for a single drag-out's two phases — extracting the entry into
/// scratch, then moving it into place at the promised destination. A plain
/// `@Observable` object rather than anything tied to a specific window, since
/// this has to be driven from `ArchiveEntryFilePromiseProvider`'s background
/// `Task`, not a SwiftUI view's own lifecycle.
@MainActor
@Observable
final class DragTransferState {
    enum Phase {
        case extracting
        case moving
    }
    let itemName: String
    var phase: Phase = .extracting
    var progress: ProgressInfo = .zero
    /// Set by the caller once the underlying `Task` exists, so the panel's
    /// own Cancel button (the same `ProgressPanelView` Extract uses) can
    /// actually stop it instead of just sitting there unwired.
    var onCancel: (() -> Void)?

    init(itemName: String) {
        self.itemName = itemName
    }

    var title: String {
        switch phase {
        case .extracting: "Extracting \(itemName)"
        case .moving: "Moving \(itemName) to destination"
        }
    }
}

private struct DragTransferView: View {
    var state: DragTransferState

    var body: some View {
        ProgressPanelView(
            title: state.title,
            progress: state.progress,
            onCancel: { state.onCancel?() }
        )
    }
}

/// Shows the same `ProgressPanelView` Extract uses for the duration of a
/// drag-out's promise fulfillment, in a small floating panel instead of a
/// window sheet ("que se vea igual que el que se usa en el menú desplegable"
/// — 2026-09-21). One panel at a time is all a single drag ever needs; a
/// second concurrent drag gets its own instance instead of sharing this one,
/// so multi-item drags started close together don't fight over the same
/// window.
///
/// Made key/active, not a non-activating panel: AppKit renders a
/// `ProgressView`'s bar (and every other control) in a dimmed gray, not the
/// real accent color, in any window that isn't key — matching how Extract's
/// own sheet looks means this panel has to actually become key too ("la
/// barra de progreso se ve gris, no azul" — 2026-09-21). This only runs
/// after `writePromiseTo` starts, i.e. after the drop already landed and the
/// drag gesture itself is over — the mouse isn't held over Finder anymore at
/// that point, so activating here doesn't interrupt anything.
@MainActor
final class DragProgressPanelController {
    private var panel: NSPanel?

    /// Shows the panel and returns the state object driving it. Call
    /// ``finish()`` when the transfer ends (success or failure) to close it.
    func begin(itemName: String) -> DragTransferState {
        let state = DragTransferState(itemName: itemName)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: DragTransferView(state: state))
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        return state
    }

    func finish() {
        panel?.close()
        panel = nil
    }
}
