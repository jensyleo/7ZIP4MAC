import SwiftUI
import AppKit
import SevenZipKit

/// Live state for one drag-out session: every item being extracted and then
/// moved into place, combined into a single steady progress figure. A plain
/// `@Observable` object rather than anything tied to a specific window, since
/// it has to be driven from `ArchiveEntryFilePromiseProvider`'s background
/// `Task`s, not a SwiftUI view's own lifecycle.
@MainActor
@Observable
final class DragTransferState {
    enum Phase {
        case extracting
        case moving
    }

    private struct ItemInfo {
        var name: String
        var phase: Phase = .extracting
        var onCancel: (() -> Void)?
    }

    private(set) var progress: ProgressInfo = .zero
    private(set) var title = ""

    private var items: [UUID: ItemInfo] = [:]
    private var aggregator = ProgressAggregator()
    private var finishedCount = 0
    private var latestFile: String?
    private var estimator = RateEstimator()

    func register(name: String) -> UUID {
        let id = UUID()
        items[id] = ItemInfo(name: name)
        // Every drag-out item goes through two phases: extract, then move.
        aggregator.register(id, phases: 2)
        refresh()
        return id
    }

    func setPhase(_ id: UUID, to phase: Phase) {
        guard items[id]?.phase != phase else { return }
        items[id]?.phase = phase
        if phase == .moving {
            aggregator.startNextPhase(id)
            // Moving has its own speed; don't let the faster extraction skew it.
            estimator.restart(processed: aggregator.snapshot().processed)
        }
        refresh()
    }

    func report(_ id: UUID, _ info: ProgressInfo) {
        aggregator.update(id, processed: info.processedBytes, total: info.totalBytes)
        if let file = info.currentFile { latestFile = file }
        refresh()
    }

    func setCancel(_ id: UUID, _ handler: (() -> Void)?) {
        items[id]?.onCancel = handler
    }

    func finish(_ id: UUID) {
        aggregator.finish(id)
        finishedCount += 1
        refresh()
    }

    /// The panel's single Cancel button stops every item of the drag.
    func cancelAll() {
        for item in items.values { item.onCancel?() }
    }

    private func refresh() {
        let snapshot = aggregator.snapshot()
        let rate = estimator.rate(processed: snapshot.processed)
        let remaining = RateEstimator.remaining(total: snapshot.total, processed: snapshot.processed, rate: rate)
        progress = ProgressInfo(
            fractionCompleted: snapshot.fraction,
            processedBytes: snapshot.processed,
            totalBytes: snapshot.total,
            bytesPerSecond: rate,
            estimatedTimeRemaining: remaining,
            currentFile: latestFile
        )
        let anyExtracting = items.values.contains { $0.phase == .extracting }
        if items.count == 1, let only = items.values.first {
            title = only.phase == .extracting
                ? "Extracting \(only.name)"
                : "Moving \(only.name) to destination"
        } else {
            let verb = anyExtracting ? "Extracting" : "Moving"
            let done = finishedCount > 0 ? " — \(finishedCount) done" : ""
            title = "\(verb) \(items.count) items\(done)"
        }
    }
}

/// One item's handle on the shared ``DragTransferState``.
@MainActor
final class DragTransferItem {
    private let id: UUID
    private let state: DragTransferState

    fileprivate init(name: String, state: DragTransferState) {
        self.state = state
        self.id = state.register(name: name)
    }

    /// Set once the underlying `Task` exists, so the panel's Cancel button
    /// can actually stop it instead of just sitting there unwired.
    var onCancel: (() -> Void)? {
        didSet { state.setCancel(id, onCancel) }
    }

    var phase: DragTransferState.Phase = .extracting {
        didSet { state.setPhase(id, to: phase) }
    }

    func report(_ info: ProgressInfo) {
        state.report(id, info)
    }

    fileprivate func finish() {
        state.finish(id)
    }
}

private struct DragTransferView: View {
    var state: DragTransferState

    var body: some View {
        ProgressPanelView(
            title: state.title,
            progress: state.progress,
            onCancel: { state.cancelAll() }
        )
    }
}

/// Shows the same `ProgressPanelView` Extract uses for the duration of a
/// drag-out's promise fulfillment, in a small floating panel instead of a
/// window sheet ("que se vea igual que el que se usa en el menú desplegable"
/// — 2026-09-21).
///
/// One instance is shared across every item of the *same* `beginMultiDrag`
/// call (see `MultiItemDragTriggerView`): Finder calls `writePromiseTo` once
/// per selected entry, and each one used to make its own panel and steal
/// focus independently. Items now share one panel, but each keeps its *own*
/// progress counters (see ``DragTransferState``) — an earlier version let all
/// items write one shared figure, so the bar jumped between whichever item
/// reported last (seen on a 60 GB multi-folder drag, 2026-10-05).
///
/// At most two items extract at once; the rest wait in
/// ``acquireSlot()``. Finder starts every promise simultaneously, and running
/// dozens of extractions against a network volume in parallel only makes each
/// one slower.
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

    private let limiter = SlotLimiter(limit: 2)

    /// Call once per item about to be extracted/moved. Creates and activates
    /// the panel for the first item of this drag; later items reuse it.
    func beginItem(itemName: String) -> DragTransferItem {
        activeCount += 1
        return DragTransferItem(name: itemName, state: state ?? makePanel())
    }

    /// Call once per item when its transfer ends (success or failure). Only
    /// closes the panel once every item this controller is tracking has
    /// finished.
    func finishItem(_ item: DragTransferItem) {
        item.finish()
        activeCount -= 1
        guard activeCount <= 0 else { return }
        panel?.close()
        panel = nil
        state = nil
        activeCount = 0
    }

    /// Waits for one of the extraction slots. Throws `CancellationError` —
    /// without holding a slot — if cancelled while waiting. Pair every
    /// successful call with ``releaseSlot()``.
    func acquireSlot() async throws {
        try await limiter.acquire()
    }

    func releaseSlot() {
        let limiter = limiter
        Task { await limiter.release() }
    }

    private func makePanel() -> DragTransferState {
        let state = DragTransferState()
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
}
