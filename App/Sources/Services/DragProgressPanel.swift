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

    func register(name: String, expectedBytes: UInt64 = 0) -> UUID {
        let id = UUID()
        items[id] = ItemInfo(name: name)
        // Every drag-out item goes through two phases: extract, then move.
        aggregator.register(id, phases: 2, expectedTotal: expectedBytes)
        refresh(force: true)
        return id
    }

    func setPhase(_ id: UUID, to phase: Phase) {
        guard items[id]?.phase != phase else { return }
        items[id]?.phase = phase
        if phase == .moving {
            aggregator.startNextPhase(id)
        }
        refresh(force: true)
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
        refresh(force: true)
    }

    /// The panel's single Cancel button stops every item of the drag.
    func cancelAll() {
        for item in items.values { item.onCancel?() }
    }

    /// How often the panel redraws while bytes are flowing. Dozens of items
    /// each report many times a second; publishing every one kept the main
    /// thread so busy that the bar painted late — the number said 85% while
    /// the bar was still near the start ("la barra baila").
    private static let publishInterval: TimeInterval = 0.1
    private var lastPublish = Date.distantPast
    private var pendingPublish: Task<Void, Never>?

    /// Publishes now when `force` (a structural change) or when enough time
    /// has passed; otherwise schedules one trailing publish so the last
    /// figure is never lost.
    private func refresh(force: Bool = false) {
        let elapsed = Date.now.timeIntervalSince(lastPublish)
        if force || elapsed >= Self.publishInterval {
            pendingPublish?.cancel()
            pendingPublish = nil
            publish()
            return
        }
        guard pendingPublish == nil else { return }
        pendingPublish = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int((Self.publishInterval - elapsed) * 1000) + 1))
            guard !Task.isCancelled, let self else { return }
            self.pendingPublish = nil
            self.publish()
        }
    }

    private func publish() {
        lastPublish = .now
        let snapshot = aggregator.snapshot()
        // Every item is counted twice (extract, then move). The bar needs that;
        // the sizes and the speed shown are the data itself — half — so "Size"
        // reads 2.4 GB of 2.4 GB, not a total that shrinks as phases are
        // measured, and the time left follows the end-to-end speed.
        let processed = snapshot.processed / 2
        let total = snapshot.total / 2
        let rate = estimator.rate(processed: processed)
        let remaining = RateEstimator.remaining(total: total, processed: processed, rate: rate)
        progress = ProgressInfo(
            fractionCompleted: snapshot.fraction,
            processedBytes: processed,
            totalBytes: total,
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

    /// An item that was registered up front.
    fileprivate init(id: UUID, state: DragTransferState) {
        self.state = state
        self.id = id
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
    private var finishedCount = 0

    /// Every item of this drag — path, name and size — known when the drag
    /// starts. Finder asks for the files one after another, so without this a
    /// quick item could finish before the next had begun, the panel would
    /// close with it, and the next item would open a new panel with the bar
    /// back at zero ("la barra regresa a cero con cada archivo").
    private let expected: [(path: String, name: String, bytes: UInt64)]
    private var preregistered: [String: UUID] = [:]

    private let limiter = SlotLimiter(limit: 2)

    init(expected: [(path: String, name: String, bytes: UInt64)] = []) {
        self.expected = expected
    }

    /// Call once per item about to be extracted/moved. Creates and activates
    /// the panel for the first item of this drag; later items reuse it.
    func beginItem(path: String, itemName: String) -> DragTransferItem {
        activeCount += 1
        let state = state ?? makePanel()
        if let id = preregistered[path] {
            return DragTransferItem(id: id, state: state)
        }
        return DragTransferItem(name: itemName, state: state)
    }

    /// Call once per item when its transfer ends (success or failure). Only
    /// closes the panel once every item of the drag has finished.
    func finishItem(_ item: DragTransferItem) {
        item.finish()
        activeCount -= 1
        finishedCount += 1
        let allDone = expected.isEmpty ? activeCount <= 0 : finishedCount >= expected.count
        guard allDone else { return }
        // Leave the finished panel — at 100% — up for a moment before it goes,
        // so the end of the transfer is seen to reach the end.
        let closing = panel
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            closing?.close()
        }
        panel = nil
        state = nil
        activeCount = 0
        finishedCount = 0
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
        preregistered = [:]
        for item in expected {
            preregistered[item.path] = state.register(name: item.name, expectedBytes: item.bytes)
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // Above this app's own windows, but not above other apps': a normal
        // window level (not `.floating`, which sits over every app and stayed
        // there when the user put another app on top — "la ventana de
        // progreso queda por encima de todo", 2026-11-05) plus being a child
        // of an archive window, which keeps it just above its parent.
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: DragTransferView(state: state))
        let parent = NSApp.keyWindow ?? NSApp.mainWindow
            ?? NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
        if let parent {
            // Centre over the window it belongs to, then follow it.
            panel.setFrameOrigin(NSPoint(
                x: parent.frame.midX - panel.frame.width / 2,
                y: parent.frame.midY - panel.frame.height / 2
            ))
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        parent?.addChildWindow(panel, ordered: .above)
        self.panel = panel
        return state
    }
}
