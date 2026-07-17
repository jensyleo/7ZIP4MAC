import SwiftUI
import AppKit
import SevenZipKit

/// The explorer: a breadcrumb bar plus a sortable, multi-selectable table of the
/// entries in the current folder. Double-click (or Return) enters a folder.
struct FileListView: View {
    @Bindable var viewModel: ArchiveViewModel
    @Binding var selection: Set<ArchiveEntry.ID>
    var onQuickLook: () -> Void = {}
    var onExtractSelection: () -> Void = {}
    var onTestSelection: () -> Void = {}
    var onAdd: () -> Void = {}
    var onRenameSelection: () -> Void = {}
    var onMoveSelection: () -> Void = {}
    var onCopySelection: () -> Void = {}
    var onDeleteSelection: () -> Void = {}

    /// The last explicitly clicked row, used as the anchor for Shift-click
    /// range selection (standard macOS/Windows convention).
    @State private var selectionAnchor: ArchiveEntry.ID?

    /// Tracks the last click's target/time to detect double-clicks ourselves.
    /// More reliable than reading `NSEvent.currentEvent?.clickCount` inside a
    /// Button action, which occasionally raced SwiftUI's event dispatch and
    /// missed the second click ("a veces falla" — 2026-07-09 user report).
    @State private var lastClickedID: ArchiveEntry.ID?
    @State private var lastClickTime: Date = .distantPast

    /// Local `NSEvent` monitor backing the Delete/Backspace shortcut.
    @State private var deleteKeyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbBar(viewModel: viewModel)
            Divider()
            table
        }
    }

    private var table: some View {
        Table(viewModel.visibleEntries, selection: $selection, sortOrder: $viewModel.sortOrder) {
            TableColumn("Name", value: \.name) { entry in
                // A plain-style Button (not `.onTapGesture`) reading the real
                // click count/modifier keys from NSEvent: this is what makes
                // single-click selection, Cmd/Shift multi-select and
                // double-click-to-activate all reliable at once, instead of
                // racing a custom gesture recognizer against Table's own.
                Button {
                    handleClick(on: entry)
                } label: {
                    Label {
                        Text(entry.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(EntryRowStatus.of(entry).tint ?? .primary)
                    } icon: {
                        EntryIcon(entry: entry)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help(entry.path)
                .onDrag {
                    guard !entry.isParentLink, let archiveURL = viewModel.archiveURL else {
                        return NSItemProvider()
                    }
                    return DragOut.itemProvider(for: entry, archiveURL: archiveURL, password: viewModel.sessionPassword)
                }
            }
            .width(min: 200, ideal: 320)

            TableColumn("Size", value: \.size) { entry in
                Text(entry.displaySize).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            .alignment(.trailing)

            TableColumn("Compressed") { entry in
                Text(entry.displayPackedSize).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
            .alignment(.trailing)

            TableColumn("Modified") { entry in
                Text(entry.displayModified).foregroundStyle(.secondary)
            }
            .width(min: 130, ideal: 170)

            TableColumn("CRC") { entry in
                Text(entry.crc ?? "—").monospaced().foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 90)
        }
        .tableStyle(.inset)
        .contextMenu(forSelectionType: ArchiveEntry.ID.self) { ids in
            contextMenuContent(for: ids)
        }
        .onAppear { installDeleteKeyMonitor() }
        .onDisappear { removeDeleteKeyMonitor() }
    }

    /// Space (Quick Look), Return (Rename) and Delete/Backspace, all via an
    /// `NSEvent` local monitor rather than `.onKeyPress` — `Table` swallows
    /// these keys internally before SwiftUI's key-press modifiers ever see
    /// them, so `.onKeyPress` intermittently just doesn't fire. Concretely:
    /// Delete/Backspace silently never worked at all ("Delete/Backspace no
    /// funciona" — 2026-07-09), and Space/Return worked *most* of the time
    /// but not always — e.g. right after opening the Inspector, whose
    /// `.textSelection(.enabled)` fields are focusable and can steal the
    /// table's keyboard focus, so `.onKeyPress` silently stopped firing
    /// until the window was defocused and refocused ("me molestó el Quick
    /// Look" — 2026-07-10). A local monitor intercepts the key event before
    /// normal focus-based dispatch, so none of this affects it — the
    /// keyboard shortcut works regardless of which view currently has focus.
    private func installDeleteKeyMonitor() {
        guard deleteKeyMonitor == nil else { return }
        deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't hijack these keys while the user is typing in a text
            // field elsewhere (e.g. the Rename/Move prompt, or a Settings field).
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }

            switch event.keyCode {
            case 0 where event.modifierFlags.contains(.command): // kVK_ANSI_A, ⌘A
                selection = Set(viewModel.visibleEntries.filter { !$0.isParentLink }.map(\.id))
                return nil
            case 49 where !selection.isEmpty: // kVK_Space
                onQuickLook()
                return nil
            case 36: // kVK_Return
                if let entry = singleSelectedEntry, !entry.isParentLink {
                    onRenameSelection()
                    return nil
                }
                return event
            case 51, 117 where !selection.isEmpty: // kVK_Delete, kVK_ForwardDelete
                onDeleteSelection()
                return nil
            default:
                return event
            }
        }
    }

    private func removeDeleteKeyMonitor() {
        if let deleteKeyMonitor { NSEvent.removeMonitor(deleteKeyMonitor) }
        deleteKeyMonitor = nil
    }

    private var singleSelectedEntry: ArchiveEntry? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return viewModel.visibleEntries.first { $0.id == id }
    }

    /// Enters a folder (or the ".." row, which goes up), or previews a file.
    private func activate(_ entry: ArchiveEntry) {
        if entry.isParentLink {
            selection = []
            viewModel.goUp()
        } else if entry.isDirectory {
            selection = []
            viewModel.enter(entry)
        } else {
            onQuickLook()
        }
    }

    /// Replicates the standard macOS/Windows click-selection conventions:
    /// plain click selects only this row, Cmd-click toggles it in/out of the
    /// selection, Shift-click extends a contiguous range from the last
    /// clicked row, and a second click within the double-click interval
    /// activates the row instead of just selecting it.
    private func handleClick(on entry: ArchiveEntry) {
        // Double-click detection: our own clock, not `NSEvent.clickCount`.
        let now = Date()
        let isDoubleClick = entry.id == lastClickedID
            && now.timeIntervalSince(lastClickTime) < NSEvent.doubleClickInterval
        lastClickedID = isDoubleClick ? nil : entry.id  // reset so clicks 3/4 start a fresh pair
        lastClickTime = now

        if isDoubleClick {
            activate(entry)
            return
        }

        guard let event = NSApp.currentEvent else {
            selection = [entry.id]
            selectionAnchor = entry.id
            return
        }

        let rows = viewModel.visibleEntries
        if event.modifierFlags.contains(.command) {
            if selection.contains(entry.id) {
                selection.remove(entry.id)
            } else {
                selection.insert(entry.id)
            }
            selectionAnchor = entry.id
        } else if event.modifierFlags.contains(.shift),
                  let anchor = selectionAnchor,
                  let anchorIndex = rows.firstIndex(where: { $0.id == anchor }),
                  let clickedIndex = rows.firstIndex(where: { $0.id == entry.id }) {
            let range = anchorIndex < clickedIndex ? anchorIndex...clickedIndex : clickedIndex...anchorIndex
            selection = Set(rows[range].map(\.id))
        } else {
            selection = [entry.id]
            selectionAnchor = entry.id
        }
    }

    /// Right-click menu for the given (possibly multi-)selection.
    @ViewBuilder
    private func contextMenuContent(for ids: Set<ArchiveEntry.ID>) -> some View {
        let entries = viewModel.visibleEntries.filter { ids.contains($0.id) && !$0.isParentLink }
        let hasFile = entries.contains { !$0.isDirectory }

        Button { onAdd() } label: {
            Label("Add…", systemImage: "tray.and.arrow.down")
        }

        if !entries.isEmpty {
            Divider()
            if hasFile {
                Button { selection = ids; onQuickLook() } label: {
                    Label("Quick Look", systemImage: "eye")
                }
            }
            Button { selection = ids; onExtractSelection() } label: {
                Label(ids.count > 1 ? "Extract Selected…" : "Extract…", systemImage: "arrow.up.bin")
            }
            Button { selection = ids; onTestSelection() } label: {
                Label(ids.count > 1 ? "Test Selected" : "Test", systemImage: "checkmark.seal")
            }
            Divider()
            if ids.count == 1 {
                Button { selection = ids; onRenameSelection() } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                Button { selection = ids; onMoveSelection() } label: {
                    Label("Move…", systemImage: "arrow.turn.up.right")
                }
                Button { selection = ids; onCopySelection() } label: {
                    Label("Copy…", systemImage: "doc.on.doc")
                }
            }
            Button(role: .destructive) { selection = ids; onDeleteSelection() } label: {
                Label(ids.count > 1 ? "Delete Selected" : "Delete", systemImage: "trash")
            }
            Divider()
            Button { copyToPasteboard(entries.map(\.name).joined(separator: "\n")) } label: {
                Label("Copy Name", systemImage: "textformat")
            }
            Button { copyToPasteboard(entries.map(\.path).joined(separator: "\n")) } label: {
                Label("Copy Path", systemImage: "arrow.right.doc.on.clipboard")
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// The path bar showing the current location inside the archive.
private struct BreadcrumbBar: View {
    @Bindable var viewModel: ArchiveViewModel

    var body: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.navigateToBreadcrumb(count: 0)
            } label: {
                Image(systemName: "house")
            }
            .buttonStyle(.plain)
            // Clickable crumbs are tinted like a link; only the current
            // (last) location is plain text, matching Finder's path bar.
            .foregroundStyle(viewModel.currentFolder.isEmpty ? Color.secondary : Color.accentColor)
            .disabled(viewModel.currentFolder.isEmpty)
            .help("Go to the top of the archive")

            ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.offset) { index, name in
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                let isCurrent = index == viewModel.breadcrumbs.count - 1
                Button(name) {
                    viewModel.navigateToBreadcrumb(count: index + 1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isCurrent ? Color.primary : Color.accentColor)
                .fontWeight(isCurrent ? .semibold : .regular)
                .disabled(isCurrent)
                .help(isCurrent ? "Current folder" : "Go to “\(name)”")
            }

            Spacer()
        }
        .lineLimit(1)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
