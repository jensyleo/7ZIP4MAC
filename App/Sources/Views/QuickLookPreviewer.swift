import AppKit
import Quartz

/// Presents a Quick Look panel for archive entries.
///
/// Entries live inside the archive, so the caller first extracts the chosen
/// entry to a temporary file (via `DragOut.extract`) and hands its URL here;
/// this type feeds that URL to the shared `QLPreviewPanel`.
@MainActor
final class QuickLookPreviewer: NSObject {
    static let shared = QuickLookPreviewer()

    // QLPreviewPanel invokes the data-source methods on the main thread, and we
    // only mutate this from the main actor, so the unchecked store is safe.
    nonisolated(unsafe) private var items: [NSURL] = []

    /// Shows (or refreshes) the Quick Look panel for the given file URLs.
    func preview(urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        items = urls.map { $0 as NSURL }
        panel.dataSource = self
        panel.delegate = self
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Whether the panel is currently on screen.
    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }
}

extension QuickLookPreviewer: QLPreviewPanelDataSource {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        items.count
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> (any QLPreviewItem)! {
        items[index]
    }
}

extension QuickLookPreviewer: QLPreviewPanelDelegate {}
