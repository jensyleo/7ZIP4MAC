import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SevenZipKit

/// Writes one archive entry to disk on demand, as an `NSFilePromiseProvider`
/// — the AppKit type Finder itself uses for multi-item drag-and-drop.
/// Unlike SwiftUI's `.onDrag`/`NSItemProvider`, a set of these handed to
/// `NSView.beginDraggingSession(with:event:source:)` lands as separate loose
/// files in Finder, one per provider — which is exactly the gap `.onDrag`
/// can't close for a `Table` multi-selection (only the row the drag started
/// from is ever included, regardless of how much else is selected).
private final class ArchiveEntryFilePromiseProvider: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    private let archiveURL: URL
    private let entryPath: String
    private let entryName: String
    private let password: String?

    init(archiveURL: URL, entryPath: String, entryName: String, password: String?, typeIdentifier: String) {
        self.archiveURL = archiveURL
        self.entryPath = entryPath
        self.entryName = entryName
        self.password = password
        super.init()
        fileType = typeIdentifier
        delegate = self
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        entryName
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        // Capture plain, Sendable values only — not `self` (an NSObject
        // subclass, not Sendable) — to satisfy Swift 6 strict concurrency.
        let entryPath = entryPath
        let archiveURL = archiveURL
        let password = password
        Task {
            do {
                let extractedURL = try await DragOut.extract(
                    entryPath: entryPath, archiveURL: archiveURL, password: password
                )
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.moveItem(at: extractedURL, to: url)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }
}

/// A transparent AppKit view overlaid on a `Table` row's Name cell — but
/// only for rows that are already part of a multi-selection (see
/// `EntryDragModifier`). It disambiguates the very same mouse-down between a
/// real drag (begins a genuine multi-item `NSDraggingSession`, one loose
/// file per selected entry) and a plain click (forwarded as an ordinary
/// single-selection click, matching what clicking an already-selected
/// `Table` row normally does) — the classic AppKit "wait past the drag
/// threshold, then decide" pattern, since SwiftUI's own `Table` never sees
/// this mouse-down at all while this view is on top of it.
final class MultiItemDragTriggerView: NSView, NSDraggingSource {
    var entries: [ArchiveEntry] = []
    var archiveURL: URL?
    var password: String?
    var onPlainClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only this view itself is ever hit — there's nothing beneath it to
        // delegate to (it exists purely to intercept the gesture).
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        guard let window, let archiveURL, !entries.isEmpty else {
            onPlainClick?()
            return
        }

        // Classic click-vs-drag disambiguation: keep pulling events until
        // either the pointer moves past the drag threshold (→ real drag) or
        // the button comes up first (→ plain click, no drag happened).
        let startLocation = event.locationInWindow
        let dragThreshold: CGFloat = 4
        var didDrag = false
        while let next = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            if next.type == .leftMouseUp { break }
            let dx = next.locationInWindow.x - startLocation.x
            let dy = next.locationInWindow.y - startLocation.y
            if hypot(dx, dy) > dragThreshold {
                didDrag = true
                break
            }
        }

        if didDrag {
            beginMultiDrag(with: event, archiveURL: archiveURL)
        } else {
            onPlainClick?()
        }
    }

    private func beginMultiDrag(with event: NSEvent, archiveURL: URL) {
        let icon = NSWorkspace.shared.icon(for: .data)
        let items: [NSDraggingItem] = entries.map { entry in
            let provider = ArchiveEntryFilePromiseProvider(
                archiveURL: archiveURL,
                entryPath: entry.path,
                entryName: entry.name,
                password: password,
                typeIdentifier: DragOut.typeIdentifier(for: entry)
            )
            let draggingItem = NSDraggingItem(pasteboardWriter: provider)
            draggingItem.setDraggingFrame(bounds, contents: icon)
            return draggingItem
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

/// SwiftUI wrapper for `MultiItemDragTriggerView`. Placed as an overlay only
/// on rows that are part of a multi-selection — see `EntryDragModifier`.
struct MultiItemDragTrigger: NSViewRepresentable {
    let entries: [ArchiveEntry]
    let archiveURL: URL
    let password: String?
    let onPlainClick: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> MultiItemDragTriggerView {
        let view = MultiItemDragTriggerView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: MultiItemDragTriggerView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: MultiItemDragTriggerView) {
        view.entries = entries
        view.archiveURL = archiveURL
        view.password = password
        view.onPlainClick = onPlainClick
        view.onDoubleClick = onDoubleClick
    }
}
