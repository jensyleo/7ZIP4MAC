import SwiftUI
import AppKit

/// Recognizes a drop from a *different* 7ZIP4MAC window's archive entry —
/// registered only for `DragOut.crossArchiveTypeIdentifier`, so it never
/// competes with SwiftUI's own `.onDrop(of: [.fileURL], ...)` handling plain
/// files from Finder (a drag that doesn't offer this type is invisible to
/// this view; AppKit resolves the destination to whichever registered view
/// underneath actually offers a matching type).
///
/// Exists because `NSDraggingInfo.itemProviders` — what `.onDrop` reads
/// incoming drops through — doesn't surface this type even though it's
/// genuinely on the drag pasteboard (confirmed by reading
/// `NSDraggingInfo.draggingPasteboard` directly here, which does see it).
final class CrossArchiveDropTargetView: NSView {
    var onDrop: (([DragOut.EntryTransfer]) -> Void)?

    private static let crossArchivePasteboardType = NSPasteboard.PasteboardType(DragOut.crossArchiveTypeIdentifier)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([Self.crossArchivePasteboardType])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([Self.crossArchivePasteboardType])
    }

    // Mouse clicks/scrolling on the archive list underneath must keep
    // working normally — only AppKit's separate drag-destination resolution
    // (frame + registered-types based, not this method) should ever "see"
    // this view.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.pasteboardItems else { return false }
        let transfers = items.compactMap { item -> DragOut.EntryTransfer? in
            guard let data = item.data(forType: Self.crossArchivePasteboardType) else { return nil }
            return try? JSONDecoder().decode(DragOut.EntryTransfer.self, from: data)
        }
        guard !transfers.isEmpty else { return false }
        onDrop?(transfers)
        return true
    }
}

/// SwiftUI wrapper for `CrossArchiveDropTargetView`. Overlay this on top of
/// the archive window's content, above the existing `.onDrop` — see
/// `ContentView`.
struct CrossArchiveDropTarget: NSViewRepresentable {
    let onDrop: ([DragOut.EntryTransfer]) -> Void

    func makeNSView(context: Context) -> CrossArchiveDropTargetView {
        let view = CrossArchiveDropTargetView()
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: CrossArchiveDropTargetView, context: Context) {
        nsView.onDrop = onDrop
    }
}
