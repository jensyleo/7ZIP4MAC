import SwiftUI
import AppKit

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
    var extractFraction: Double = 0
    var moveFraction: Double = 0

    init(itemName: String) {
        self.itemName = itemName
    }
}

private struct DragTransferView: View {
    var state: DragTransferState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(state.itemName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            row(label: "Extracting", fraction: state.extractFraction, isActive: state.phase == .extracting)
            row(label: "Moving to destination", fraction: state.moveFraction, isActive: state.phase == .moving)
        }
        .padding(20)
        .frame(width: 340)
    }

    private func row(label: String, fraction: Double, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(isActive ? .primary : .secondary)
                Spacer()
                if isActive || fraction > 0 {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .opacity(isActive || fraction > 0 ? 1 : 0.35)
        }
    }
}

/// Shows a small floating, non-activating panel for the duration of a
/// drag-out's promise fulfillment — the user's mouse is over Finder for the
/// whole gesture, so this deliberately never becomes key/main and never
/// steals focus, unlike ``ProgressPanelView``'s sheet (which needs its own
/// window frontmost to make sense). One panel at a time is all a single
/// drag ever needs; a second concurrent drag gets its own instance instead
/// of sharing this one, so multi-item drags started close together don't
/// fight over the same window.
@MainActor
final class DragProgressPanelController {
    private var panel: NSPanel?

    /// Shows the panel and returns the state object driving it. Call
    /// ``finish()`` when the transfer ends (success or failure) to close it.
    func begin(itemName: String) -> DragTransferState {
        let state = DragTransferState(itemName: itemName)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .utilityWindow],
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
        panel.orderFrontRegardless()
        self.panel = panel
        return state
    }

    func finish() {
        panel?.close()
        panel = nil
    }
}
