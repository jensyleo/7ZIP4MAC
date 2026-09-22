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
    var itemName: String
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
/// — 2026-09-21).
///
/// One instance is shared across every item of the *same* `beginMultiDrag`
/// call (see `MultiItemDragTriggerView`), reference-counted via
/// ``beginItem(itemName:)``/``finishItem()``: Finder calls
/// `writePromiseTo` once per selected entry, and each one used to make its
/// own panel and steal focus independently, so a multi-item drag flashed a
/// new activating window per item instead of one steady one (found in
/// security/robustness audit, 2026-09-21). A *different*, separate drag
/// still gets its own controller instance, so two unrelated drags started
/// close together don't fight over the same window.
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
    private var state: DragTransferState?
    private var activeCount = 0

    /// Call once per item about to be extracted/moved. Creates and activates
    /// the panel for the first concurrently-active item in this drag; later
    /// items (running items 2...N of the same multi-selection drag) reuse
    /// the same panel/state instead of spawning their own.
    func beginItem(itemName: String) -> DragTransferState {
        activeCount += 1
        if let state {
            state.itemName = itemName
            state.phase = .extracting
            state.progress = .zero
            return state
        }
        let state = DragTransferState(itemName: itemName)
        self.state = state
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

    /// Call once per item when its transfer ends (success or failure). Only
    /// closes the panel once every item this controller is tracking has
    /// finished.
    func finishItem() {
        activeCount -= 1
        guard activeCount <= 0 else { return }
        panel?.close()
        panel = nil
        state = nil
        activeCount = 0
    }
}
