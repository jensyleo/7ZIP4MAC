import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SevenZipKit

/// The archive window's root view. Composes the toolbar, the file list and the
/// status bar, and switches between empty / loading / loaded / failed states.
struct ContentView: View {
    @Bindable var viewModel: ArchiveViewModel
    @Bindable var compression: CompressionViewModel
    @Bindable var settings: AppSettings
    @Bindable var profileStore: ProfileStore
    @Bindable var recents: RecentsStore
    let quickLookController: QuickLookPanelController?
    @State private var selection: Set<ArchiveEntry.ID> = []
    @State private var isDropTargeted = false
    @State private var pendingDeletePaths: [String]?
    @State private var pendingDroppedURLs: [URL]?
    @State private var pendingCrossArchiveTransfers: [DragOut.EntryTransfer]?
    @AppStorage("showInspector") private var showInspector = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var toolbarController = SevenZip4MACToolbarController()

    var body: some View {
        contentWithExtractionUI
        .modifier(CompressionFlow(
            compression: compression,
            profileStore: profileStore,
            revealWhenDone: settings.revealInFinderWhenDone,
            onOpenCreated: { url in
                openRespectingCurrentArchive(url)
            }
        ))
        .onAppear { viewModel.showHiddenEntries = settings.showHiddenEntries }
        .onChange(of: settings.showHiddenEntries) { _, newValue in
            viewModel.showHiddenEntries = newValue
        }
        .onChange(of: finishedDestination) { _, destination in
            dismissExtractionResultIfQuiet(destination)
        }
        .alert("Archive Test", isPresented: testPresented, presenting: viewModel.testMessage) { _ in
            Button("OK", role: .cancel) { viewModel.dismissTest() }
        } message: { message in
            Text(message)
        }
        .modifier(EditAlerts(
            viewModel: viewModel,
            pendingDeletePaths: $pendingDeletePaths,
            selection: $selection,
            notifySuccess: settings.notifyOnDelete
        ))
        .modifier(DropAlerts(
            viewModel: viewModel,
            pendingDroppedURLs: $pendingDroppedURLs,
            selection: $selection,
            notifyOnAdd: settings.notifyOnAdd
        ))
        .modifier(CrossArchiveTransferAlert(
            viewModel: viewModel,
            pendingTransfers: $pendingCrossArchiveTransfers,
            notifyOnAdd: settings.notifyOnAdd
        ))
        .sheet(isPresented: passwordPromptPresented) {
            PasswordPromptView(
                archiveName: viewModel.pendingPasswordURL?.lastPathComponent ?? "archive",
                showError: viewModel.passwordAttemptFailed,
                attemptCount: viewModel.passwordAttemptCount,
                maxAttempts: viewModel.maxPasswordAttempts,
                onUnlock: { password in
                    viewModel.submitPassword(password)
                },
                onCancel: viewModel.cancelPasswordEntry
            )
        }
    }

    /// `mainContent` plus the toolbar, inspector and extraction-related
    /// sheet/alerts — split out of `body` for the same type-checker reason
    /// as `mainContent` itself below.
    private var contentWithExtractionUI: some View {
        mainContent
        .background(ToolbarHost(actions: toolbarActions, controller: toolbarController))
        .onChange(of: selection) { _, _ in refreshQuickLookIfVisible() }
        .inspector(isPresented: $showInspector) {
            InspectorView(entry: singleSelectedEntry)
        }
        .sheet(isPresented: extractionSheetPresented) {
            if case .running(let progress) = viewModel.extractionState {
                ProgressPanelView(
                    title: "Extracting \(viewModel.archiveURL?.lastPathComponent ?? "archive")",
                    progress: progress,
                    onCancel: viewModel.cancelExtraction
                )
            }
        }
        .alert("Extraction Complete", isPresented: extractionFinishedPresented, presenting: finishedDestination) { destination in
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(finishedRevealTargets)
                viewModel.dismissExtractionResult()
            }
            Button("Done", role: .cancel) { viewModel.dismissExtractionResult() }
        } message: { destination in
            switch finishedOverwritePolicy {
            case .overwrite:
                Text("Files were extracted to “\(destination.lastPathComponent)”.")
            case .skip:
                Text("Files were extracted to “\(destination.lastPathComponent)”. Any file that already existed there was left untouched (Skip).")
            case .rename:
                Text("Files were extracted to “\(destination.lastPathComponent)”. Any file that already existed there was kept, and the newly extracted one was given a different name (Rename Extracted File).")
            }
        }
        .alert("Couldn’t Extract", isPresented: extractionFailedPresented, presenting: failureMessage) { _ in
            Button("OK", role: .cancel) { viewModel.dismissExtractionResult() }
        } message: { message in
            Text(message)
        }
    }

    /// The state switch plus its most basic modifiers, split out of `body` —
    /// combined with the rest of `body`'s modifier chain in one expression,
    /// the whole thing became too much for the type-checker to solve in
    /// reasonable time.
    private var mainContent: some View {
        Group {
            switch viewModel.state {
            case .empty:
                EmptyStateView(
                    onOpen: presentOpenPanel,
                    recents: recents.existing,
                    onOpenRecent: { url in openRespectingCurrentArchive(url) }
                )
            case .loading(let url):
                LoadingStateView(url: url)
            case .failed(let message):
                FailureStateView(message: message, onRetry: presentOpenPanel)
            case .loaded(let archive):
                VStack(spacing: 0) {
                    FileListView(viewModel: viewModel, selection: $selection,
                                 onQuickLook: performQuickLook, onExtractSelection: extract,
                                 onTestSelection: testArchiveOrSelection,
                                 onAdd: addFiles,
                                 onRenameSelection: renameSelected,
                                 onMoveSelection: moveSelected, onCopySelection: copySelected,
                                 onDeleteSelection: confirmDeleteSelected)
                    StatusBarView(archive: archive)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .overlay { dropOverlay }
        .overlay { CrossArchiveDropTarget(onDrop: handleCrossArchiveDrop) }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .navigationTitle(viewModel.archiveURL?.lastPathComponent ?? "7ZIP4MAC")
    }

    private var testPresented: Binding<Bool> {
        Binding(get: { viewModel.testMessage != nil }, set: { if !$0 { viewModel.dismissTest() } })
    }


    private var passwordPromptPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingPasswordURL != nil },
            set: { if !$0 { viewModel.cancelPasswordEntry() } }
        )
    }

    /// Focuses `url`'s window if it's already open somewhere; otherwise loads
    /// it into this window if it's empty, or opens a separate window for it —
    /// this window's archive, if any, is never silently replaced.
    private func openRespectingCurrentArchive(_ url: URL) {
        let focused = OpenArchiveWindowRegistry.focusIfOpen(url)
        if focused {
            // macOS opens a brand-new default (empty) window for every
            // "open this file" request that reaches an already-running app —
            // that's this window. Its job was only ever to route this
            // request; now that an existing window took it, an empty one
            // left behind would just be litter.
            if viewModel.archive == nil { dismissWindow() }
            return
        }
        if viewModel.archive != nil {
            openWindow(value: url as URL?)
        } else {
            selection = []
            viewModel.open(url: url)
        }
    }

    func startNewArchive() {
        let sources = SourceSelectionPanel.present()
        guard !sources.isEmpty else { return }
        compression.begin(
            sources: sources,
            format: settings.defaultFormat,
            level: settings.defaultLevel,
            encryptFileNames: settings.defaultEncryptFileNames
        )
    }

    /// Extracts the selected entries to temporary files and shows them in
    /// Quick Look — or, if the panel is already open for this window, closes
    /// it instead (Space/⌘Y toggle, matching Finder). Folders are skipped —
    /// Quick Look has nothing useful to show.
    func performQuickLook() {
        guard let quickLookController else { return }
        if quickLookController.isVisible {
            quickLookController.toggle(urls: [])
            return
        }
        extractSelectionForQuickLook { urls in
            quickLookController.toggle(urls: urls)
        }
    }

    /// While the panel is already open, a plain click on a different row
    /// never calls `performQuickLook()` — it only changes `selection`. This
    /// keeps the preview in sync with that selection instead of leaving it
    /// stale (or, worse, still showing an item the user has since
    /// deselected).
    private func refreshQuickLookIfVisible() {
        guard let quickLookController, quickLookController.isVisible else { return }
        // Nothing left to preview (selection cleared, or narrowed down to
        // only folders) — close instead of leaving the last-shown item
        // stuck on screen forever.
        guard viewModel.visibleEntries.contains(where: { selection.contains($0.id) && !$0.isDirectory }) else {
            quickLookController.toggle(urls: [])
            return
        }
        extractSelectionForQuickLook { urls in
            quickLookController.refresh(urls: urls)
        }
    }

    private func extractSelectionForQuickLook(then handle: @escaping ([URL]) -> Void) {
        guard let archiveURL = viewModel.archiveURL else { return }
        let entries = viewModel.visibleEntries.filter { selection.contains($0.id) && !$0.isDirectory }
        guard !entries.isEmpty else { return }
        let password = viewModel.sessionPassword
        Task {
            var urls: [URL] = []
            for entry in entries {
                do {
                    let url = try await DragOut.extract(
                        entryPath: entry.path, archiveURL: archiveURL, password: password
                    )
                    urls.append(url)
                } catch {
                    ArchiveLog.ui.error("Quick Look failed for \(entry.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            guard !urls.isEmpty else { return }
            handle(urls)
        }
    }

    private var canQuickLook: Bool {
        viewModel.visibleEntries.contains { selection.contains($0.id) && !$0.isDirectory }
    }

    private var singleSelectedEntry: ArchiveEntry? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return viewModel.visibleEntries.first { $0.id == id && !$0.isParentLink }
    }

    // MARK: - Extraction result bindings

    private var extractionSheetPresented: Binding<Bool> {
        Binding(get: { viewModel.isExtracting }, set: { if !$0 { viewModel.cancelExtraction() } })
    }

    // Always shown when files were skipped or renamed instead of overwritten
    // — that's not cosmetic "it's done" noise, it's information the user
    // needs to know their files (or the newly extracted ones) ended up
    // somewhere other than expected.
    private var shouldShowExtractionFinished: Bool {
        guard finishedDestination != nil else { return false }
        if settings.confirmAfterExtraction { return true }
        return finishedOverwritePolicy != .overwrite
    }

    private var extractionFinishedPresented: Binding<Bool> {
        Binding(
            get: { shouldShowExtractionFinished },
            set: { if !$0 { viewModel.dismissExtractionResult() } }
        )
    }

    private var extractionFailedPresented: Binding<Bool> {
        Binding(get: { failureMessage != nil }, set: { if !$0 { viewModel.dismissExtractionResult() } })
    }

    private var finishedDestination: URL? {
        if case .finished(let destination, _, _) = viewModel.extractionState { return destination }
        return nil
    }

    private var finishedRevealTargets: [URL] {
        if case .finished(_, let revealTargets, _) = viewModel.extractionState { return revealTargets }
        return []
    }

    private var finishedOverwritePolicy: ExtractionRequest.OverwritePolicy {
        if case .finished(_, _, let overwritePolicy) = viewModel.extractionState { return overwritePolicy }
        return .overwrite
    }

    private var failureMessage: String? {
        if case .failed(let message) = viewModel.extractionState { return message }
        return nil
    }

    // MARK: - Toolbar
    //
    // A hand-built `NSToolbar`, bridged in via `ToolbarHost` (see
    // SevenZip4MACToolbar.swift) instead of SwiftUI's own `.toolbar(id:)` —
    // that API crashes on macOS 26.6.2 the moment a second window opens,
    // because `CustomizableToolbarContent`'s saved layout restoration isn't
    // safe across multiple windows sharing one `toolbar(id:)`. Each action
    // below still declares its own enabled state and title exactly like the
    // old `ToolbarItem`s did; `ToolbarHost` re-syncs the real toolbar to
    // this list on every render without disturbing a user's manual reorder.

    private var toolbarActions: [ToolbarAction] {
        archiveToolbarActions + editToolbarActions + windowToolbarActions
    }

    /// Open/create/extract/test — the core archive-level actions.
    private var archiveToolbarActions: [ToolbarAction] {
        [
            ToolbarAction(
                id: "open", title: "Open", systemImage: "folder",
                help: "Open an archive", kind: .button(presentOpenPanel)
            ),
            ToolbarAction(
                id: "newArchive", title: "New Archive", systemImage: "doc.zipper",
                isEnabled: !compression.isRunning,
                help: "Create a new archive", kind: .button(startNewArchive)
            ),
            ToolbarAction(
                id: "extract", title: selection.isEmpty ? "Extract All" : "Extract Selected",
                systemImage: "arrow.up.bin",
                isEnabled: viewModel.archive != nil && !viewModel.isExtracting,
                help: selection.isEmpty ? "Extract the whole archive" : "Extract the selected items",
                kind: .button(extract)
            ),
            ToolbarAction(
                id: "test", title: selection.isEmpty ? "Test" : "Test Selected",
                systemImage: "checkmark.seal",
                isEnabled: viewModel.archive != nil,
                help: selection.isEmpty ? "Test the whole archive's integrity" : "Test the selected items' integrity",
                kind: .button(testArchiveOrSelection)
            ),
        ]
    }

    /// Add/Rename/Move/Copy/Delete — in-place edits on entries, each its own
    /// direct toolbar button (no longer tucked into an "Edit" dropdown) so
    /// they're one click away; the toolbar's own overflow chevron handles it
    /// if the window gets too narrow to show them all.
    private var editToolbarActions: [ToolbarAction] {
        [
            ToolbarAction(
                id: "add", title: "Add…", systemImage: "tray.and.arrow.down",
                isEnabled: viewModel.archive != nil,
                help: "Add files or folders into the archive", kind: .button(addFiles)
            ),
            ToolbarAction(
                id: "rename", title: "Rename…", systemImage: "pencil",
                isEnabled: selection.count == 1,
                help: "Rename the selected item", kind: .button(renameSelected)
            ),
            ToolbarAction(
                id: "move", title: "Move…", systemImage: "arrow.turn.up.right",
                isEnabled: selection.count == 1,
                help: "Move the selected item within the archive", kind: .button(moveSelected)
            ),
            ToolbarAction(
                id: "copy", title: "Copy…", systemImage: "doc.on.doc",
                isEnabled: selection.count == 1,
                help: "Copy the selected item within the archive", kind: .button(copySelected)
            ),
            ToolbarAction(
                id: "delete", title: selection.count > 1 ? "Delete Selected" : "Delete",
                systemImage: "trash", isEnabled: !selection.isEmpty, isDestructive: true,
                help: "Delete the selected item(s) from the archive", kind: .button(confirmDeleteSelected)
            ),
        ]
    }

    /// Up/Quick Look/Inspector/Close/More — window and navigation controls.
    private var windowToolbarActions: [ToolbarAction] {
        [
            ToolbarAction(
                id: "up", title: "Up", systemImage: "chevron.up",
                isEnabled: !viewModel.currentFolder.isEmpty,
                help: "Go up one folder", kind: .button(viewModel.goUp)
            ),
            ToolbarAction(
                id: "quickLook", title: "Quick Look", systemImage: "eye",
                isEnabled: canQuickLook,
                help: "Preview the selected item (Space)", kind: .button(performQuickLook)
            ),
            ToolbarAction(
                id: "inspector", title: "Inspector", systemImage: "sidebar.right",
                help: "Toggle inspector", kind: .button { showInspector.toggle() }
            ),
            ToolbarAction(
                id: "close", title: "Close", systemImage: "xmark.circle",
                isEnabled: viewModel.archive != nil,
                help: "Close the current archive", kind: .button(viewModel.close)
            ),
            ToolbarAction(
                id: "more", title: "More", systemImage: "ellipsis.circle",
                help: "More actions", kind: .menu { [settings] in
                    let menu = NSMenu()
                    menu.addItem(ClosureMenuItem(title: "Uninstall 7ZIP4MAC…") {
                        Uninstaller.confirmAndUninstall(settings: settings)
                    })
                    return menu
                }
            ),
        ]
    }

    // MARK: - Drag & drop feedback

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                .padding(8)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Intents

    private func presentOpenPanel() {
        guard let url = ArchiveOpenPanel.present() else { return }
        openRespectingCurrentArchive(url)
    }

    /// When the completion dialog is disabled, extraction just finishes
    /// quietly — clear the finished state so it doesn't linger. Files that
    /// were skipped/renamed instead of overwritten always show the dialog
    /// regardless (see `extractionFinishedPresented`), so don't dismiss those
    /// out from under the user.
    private func dismissExtractionResultIfQuiet(_ destination: URL?) {
        guard destination != nil else { return }
        let dialogIsOff: Bool = !settings.confirmAfterExtraction
        let policyWasDefault: Bool = finishedOverwritePolicy == .overwrite
        if dialogIsOff, policyWasDefault {
            viewModel.dismissExtractionResult()
        }
    }

    private func extract() {
        guard let archive = viewModel.archive else { return }
        guard let folder = DestinationPanel.present(
            suggestedName: archive.url.lastPathComponent
        ) else { return }
        // Selected file paths (folders are implied by their contents' paths).
        // ".." (the up-a-folder row) isn't a real archive entry, so it's
        // filtered out here the same way test/delete already do — otherwise
        // selecting it and hitting Extract would ask the engine to extract a
        // nonexistent ".." path.
        let paths = Array(selection).filter { $0 != ".." }
        let selectedEntries = archive.entries.filter { paths.contains($0.id) }
        let selectionHasFolder = selectedEntries.contains { $0.isDirectory }

        // The archive-name wrapper subfolder is only for whole-archive
        // extraction — there it keeps the archive's loose top-level files
        // from scattering into the destination. A selected folder is already
        // its own container, so wrapping it again just nests it needlessly;
        // and a pure file selection should land flat where the user pointed.
        let wholeArchive = paths.isEmpty
        viewModel.extract(into: folder, selectedPaths: paths,
                          intoSubfolder: wholeArchive && settings.extractIntoSubfolder,
                          flattenPaths: !wholeArchive && !selectionHasFolder,
                          overwritePolicy: settings.defaultOverwritePolicy)
    }

    private func testArchiveOrSelection() {
        let paths = selection.isEmpty ? [] : Array(selection).filter { $0 != ".." }
        // Test always confirms — it's the only action whose result isn't
        // otherwise visible anywhere (unlike Add/Delete/Move/Copy, which show
        // up in the file list), so it isn't user-configurable.
        viewModel.test(selectedPaths: paths, notifySuccess: true)
    }

    /// Lets the user pick files/folders to add into the already-open archive.
    private func addFiles() {
        let sources = SourceSelectionPanel.present()
        guard !sources.isEmpty else { return }
        viewModel.addFiles(sources, notifySuccess: settings.notifyOnAdd)
    }

    /// The single selected entry's archive path, for Move/Copy (both need
    /// exactly one source — there's no meaningful "move 3 items to the same
    /// single destination path" within an archive).
    private var singleSelectedPath: String? {
        guard selection.count == 1, let id = selection.first, id != ".." else { return nil }
        return id
    }

    /// Renames an entry in place — unlike Move, this only offers the last
    /// path component (the name), keeping it in the same folder, matching
    /// what "Rename" means in Finder.
    private func renameSelected() {
        guard let path = singleSelectedPath else { return }
        let currentName = (path as NSString).lastPathComponent
        let parent = (path as NSString).deletingLastPathComponent
        guard let newName = PathPromptPanel.present(
            title: "Rename Item",
            message: "Enter a new name for “\(currentName)”.",
            currentValue: currentName
        ) else { return }
        let newPath = parent.isEmpty ? newName : "\(parent)/\(newName)"
        viewModel.moveEntry(path: path, toPath: newPath, notifySuccess: settings.notifyOnMove)
    }

    private func moveSelected() {
        guard let path = singleSelectedPath else { return }
        guard let newPath = PathPromptPanel.present(
            title: "Move Item",
            message: "Enter the new path within the archive for “\((path as NSString).lastPathComponent)”.",
            currentValue: path
        ) else { return }
        viewModel.moveEntry(path: path, toPath: newPath, notifySuccess: settings.notifyOnMove)
    }

    private func copySelected() {
        guard let path = singleSelectedPath else { return }
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        let suggestedName = ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)"
        let parent = (path as NSString).deletingLastPathComponent
        let suggestedPath = parent.isEmpty ? suggestedName : "\(parent)/\(suggestedName)"
        guard let newPath = PathPromptPanel.present(
            title: "Copy Item",
            message: "Enter the path within the archive for the copy of “\(name)”.",
            currentValue: suggestedPath
        ) else { return }
        viewModel.copyEntry(path: path, toPath: newPath, notifySuccess: settings.notifyOnCopy)
    }

    private func confirmDeleteSelected() {
        let paths = Array(selection).filter { $0 != ".." }
        guard !paths.isEmpty else { return }
        pendingDeletePaths = paths
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.loadURL(from: provider) { urls.append(url) }
            }
            guard !urls.isEmpty else { return }

            if viewModel.archive != nil {
                // An archive is already open — ask whether the drop should be
                // added into it, rather than assuming (dropping a file onto an
                // open archive is ambiguous: "add this" vs "open this instead").
                pendingDroppedURLs = urls
            } else {
                selection = []
                viewModel.open(url: urls[0])
            }
        }
        return true
    }

    /// One or more entries dragged in from a *different* 7ZIP4MAC window,
    /// via `CrossArchiveDropTarget` (see its doc comment for why this isn't
    /// just another case in `handleDrop`) — unless it's a no-op drop onto
    /// the entries' own archive, asks whether to copy or move them in.
    private func handleCrossArchiveDrop(_ transfers: [DragOut.EntryTransfer]) {
        let filtered = transfers.filter { $0.archiveURL != viewModel.archiveURL }
        guard !filtered.isEmpty else { return }
        pendingCrossArchiveTransfers = filtered
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

/// The "edit archive" result alert plus the delete-confirmation alert,
/// factored out of `ContentView.body` — with everything else already in
/// that modifier chain, adding these two inline pushed the type-checker over
/// its complexity budget ("unable to type-check this expression").
private struct EditAlerts: ViewModifier {
    @Bindable var viewModel: ArchiveViewModel
    @Binding var pendingDeletePaths: [String]?
    @Binding var selection: Set<ArchiveEntry.ID>
    var notifySuccess: Bool

    func body(content: Content) -> some View {
        content
            .alert("Edit Archive", isPresented: editPresented, presenting: viewModel.editMessage) { _ in
                Button("OK", role: .cancel) { viewModel.dismissEdit() }
            } message: { message in
                Text(message)
            }
            .alert("Delete Item?", isPresented: deleteConfirmPresented, presenting: pendingDeletePaths) { paths in
                Button("Delete", role: .destructive) {
                    viewModel.deleteEntries(paths: paths, notifySuccess: notifySuccess)
                    selection = []
                    pendingDeletePaths = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletePaths = nil }
            } message: { paths in
                Text(deleteConfirmMessage(for: paths))
            }
    }

    private var editPresented: Binding<Bool> {
        Binding(get: { viewModel.editMessage != nil }, set: { if !$0 { viewModel.dismissEdit() } })
    }

    private var deleteConfirmPresented: Binding<Bool> {
        Binding(get: { pendingDeletePaths != nil }, set: { if !$0 { pendingDeletePaths = nil } })
    }

    private func deleteConfirmMessage(for paths: [String]) -> String {
        guard paths.count == 1 else { return "\(paths.count) items will be permanently removed from the archive." }
        let name = (paths[0] as NSString).lastPathComponent
        return "“\(name)” will be permanently removed from the archive."
    }
}

/// Asks what to do with file(s) dropped onto the window while an archive is
/// already open — "add to the open archive" vs "open this instead" — factored
/// out for the same type-checker-complexity reason as ``EditAlerts``.
private struct DropAlerts: ViewModifier {
    @Bindable var viewModel: ArchiveViewModel
    @Binding var pendingDroppedURLs: [URL]?
    @Binding var selection: Set<ArchiveEntry.ID>
    var notifyOnAdd: Bool
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Add to the open archive?",
            isPresented: presented,
            presenting: pendingDroppedURLs
        ) { urls in
            Button("Add to “\(viewModel.archiveURL?.lastPathComponent ?? "Archive")”") {
                viewModel.addFiles(urls, notifySuccess: notifyOnAdd)
                pendingDroppedURLs = nil
            }
            if urls.count == 1 {
                Button("Open “\(urls[0].lastPathComponent)” Instead") {
                    if !OpenArchiveWindowRegistry.focusIfOpen(urls[0]) {
                        openWindow(value: urls[0] as URL?)
                    }
                    pendingDroppedURLs = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDroppedURLs = nil }
        } message: { urls in
            Text(dropMessage(for: urls))
        }
    }

    private var presented: Binding<Bool> {
        Binding(get: { pendingDroppedURLs != nil }, set: { if !$0 { pendingDroppedURLs = nil } })
    }

    private func dropMessage(for urls: [URL]) -> String {
        guard urls.count == 1 else { return "You dropped \(urls.count) items." }
        return "You dropped “\(urls[0].lastPathComponent)”."
    }
}

/// An entry dragged in from another 7ZIP4MAC window — asks whether to copy
/// it into this archive or move it (copy here, then delete from the source).
/// Extraction from the source archive and adding into this one both go
/// through the same engine calls as any other extract/add, just chained.
private struct CrossArchiveTransferAlert: ViewModifier {
    @Bindable var viewModel: ArchiveViewModel
    @Binding var pendingTransfers: [DragOut.EntryTransfer]?
    var notifyOnAdd: Bool

    /// Set instead of proceeding directly, when one or more dragged entries
    /// would land on a path this archive already has.
    private struct OverwriteConflict: Identifiable {
        let id = UUID()
        let transfers: [DragOut.EntryTransfer]
        let conflictingPaths: Set<String>
        let existingPaths: Set<String>
        let move: Bool

        var conflictingCount: Int { conflictingPaths.count }
    }
    @State private var pendingConflict: OverwriteConflict?
    /// Set whenever extracting/renaming/adding fails for one or more items —
    /// `addFiles`/`deleteEntries` already report *their own* failures via
    /// `viewModel.editMessage`, but a failure earlier in this flow (pulling
    /// the entry out of the source archive, or renaming it locally) never
    /// reaches that; this covers it instead of letting it disappear silently.
    @State private var failureMessage: String?

    func body(content: Content) -> some View {
        content
            .alert("Couldn’t Add Everything", isPresented: failurePresented, presenting: failureMessage) { _ in
                Button("OK", role: .cancel) { failureMessage = nil }
            } message: { message in
                Text(message)
            }
            .confirmationDialog(
                "Add to This Archive?",
                isPresented: presented,
                presenting: pendingTransfers
            ) { transfers in
                Button(copyTitle(transfers)) { proceed(transfers, move: false) }
                Button(moveTitle(transfers)) { proceed(transfers, move: true) }
                Button("Cancel", role: .cancel) { pendingTransfers = nil }
            } message: { transfers in
                Text(message(for: transfers))
            }
            .confirmationDialog(
                "Replace Existing Items?",
                isPresented: conflictPresented,
                presenting: pendingConflict
            ) { conflict in
                Button("Overwrite", role: .destructive) {
                    perform(conflict.transfers, move: conflict.move)
                }
                Button("Rename…") {
                    let choices = promptRenames(for: conflict)
                    // Conflicting items the user cancelled the prompt for are
                    // left out entirely — cancelling means "don't add this
                    // one", not "use some name I never agreed to".
                    let toProcess = conflict.transfers.filter { transfer in
                        let path = destinationPath(for: transfer)
                        return !conflict.conflictingPaths.contains(path) || choices[path] != nil
                    }
                    guard !toProcess.isEmpty else { return }
                    perform(toProcess, move: conflict.move, renameChoices: choices)
                }
                Button(skipTitle(conflict), role: .cancel) {
                    let toKeep = conflict.transfers.filter { !conflict.conflictingPaths.contains(destinationPath(for: $0)) }
                    if !toKeep.isEmpty { perform(toKeep, move: conflict.move) }
                }
            } message: { conflict in
                Text(conflictMessage(for: conflict))
            }
    }

    private var presented: Binding<Bool> {
        Binding(get: { pendingTransfers != nil }, set: { if !$0 { pendingTransfers = nil } })
    }

    private var conflictPresented: Binding<Bool> {
        Binding(get: { pendingConflict != nil }, set: { if !$0 { pendingConflict = nil } })
    }

    private var failurePresented: Binding<Bool> {
        Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } })
    }

    private func entryName(_ transfer: DragOut.EntryTransfer) -> String {
        let trimmed = transfer.entryPath.hasSuffix("/") ? String(transfer.entryPath.dropLast()) : transfer.entryPath
        return (trimmed as NSString).lastPathComponent
    }

    /// Where `transfer` would land in *this* archive: the current folder
    /// plus its own name — matching how `ArchiveViewModel.addFiles` places
    /// whatever it's given.
    private func destinationPath(for transfer: DragOut.EntryTransfer) -> String {
        let name = entryName(transfer)
        return viewModel.currentFolder.isEmpty ? name : "\(viewModel.currentFolder)/\(name)"
    }

    private func copyTitle(_ transfers: [DragOut.EntryTransfer]) -> String {
        transfers.count == 1 ? "Copy Here" : "Copy \(transfers.count) Items Here"
    }

    private func moveTitle(_ transfers: [DragOut.EntryTransfer]) -> String {
        transfers.count == 1 ? "Move Here" : "Move \(transfers.count) Items Here"
    }

    private func message(for transfers: [DragOut.EntryTransfer]) -> String {
        let sourceName = transfers.first?.archiveURL.lastPathComponent ?? "the other archive"
        if transfers.count == 1 {
            return "“\(entryName(transfers[0]))” will be added from “\(sourceName)”. Move Here also removes it from that archive."
        }
        return "\(transfers.count) items will be added from “\(sourceName)”. Move Here also removes them from that archive."
    }

    private func skipTitle(_ conflict: OverwriteConflict) -> String {
        conflict.transfers.count > conflict.conflictingCount ? "Skip Conflicting, Add Rest" : "Skip"
    }

    private func conflictMessage(for conflict: OverwriteConflict) -> String {
        if conflict.conflictingCount == 1, let onlyPath = conflict.conflictingPaths.first {
            return "“\((onlyPath as NSString).lastPathComponent)” already exists here. Overwrite replaces it; Rename adds the incoming one alongside it under a new name; Skip leaves the existing one untouched."
        }
        return "\(conflict.conflictingCount) of the \(conflict.transfers.count) items already exist here. Overwrite replaces them; Rename adds the incoming ones alongside under new names; Skip leaves the existing ones untouched and adds only the rest."
    }

    /// Checks for name collisions with what's already in this archive before
    /// touching anything — asks Overwrite/Rename/Skip only if there actually
    /// are any, otherwise proceeds immediately.
    private func proceed(_ transfers: [DragOut.EntryTransfer], move: Bool) {
        pendingTransfers = nil
        let existingPaths = Set((viewModel.archive?.entries ?? []).map {
            $0.path.hasSuffix("/") ? String($0.path.dropLast()) : $0.path
        })
        let conflictingPaths = Set(transfers.map(destinationPath(for:)).filter { existingPaths.contains($0) })
        guard !conflictingPaths.isEmpty else {
            perform(transfers, move: move)
            return
        }
        pendingConflict = OverwriteConflict(
            transfers: transfers, conflictingPaths: conflictingPaths, existingPaths: existingPaths, move: move
        )
    }

    /// The first available "name copy N.ext" that collides with neither
    /// `taken` (this archive's existing entries) nor anything already
    /// reserved earlier in the same batch.
    private func uniqueLocalName(for originalName: String, avoiding taken: Set<String>) -> String {
        let ext = (originalName as NSString).pathExtension
        let base = (originalName as NSString).deletingPathExtension
        func candidate(_ suffix: String) -> String { ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)" }
        var name = candidate(" copy")
        var counter = 2
        while taken.contains(name) {
            name = candidate(" copy \(counter)")
            counter += 1
        }
        return name
    }

    /// This archive's existing entry names that are direct children of the
    /// current folder — the pool a new local name must avoid colliding with.
    private func existingLocalNames(in existingPaths: Set<String>) -> Set<String> {
        let folder = viewModel.currentFolder
        return Set(existingPaths.compactMap { path -> String? in
            let trimmed = path.hasPrefix(folder.isEmpty ? "" : folder + "/")
                ? String(path.dropFirst(folder.isEmpty ? 0 : folder.count + 1)) : path
            return trimmed.contains("/") ? nil : trimmed
        })
    }

    /// Asks for a new name for each conflicting item, one prompt at a time,
    /// pre-filled with a suggested unique one. If the typed name *also*
    /// collides — with an existing entry or with a name already chosen
    /// earlier in this same batch — re-prompts instead of silently going
    /// ahead with a name that would just create another conflict. Cancelling
    /// a given prompt leaves that item out of the returned map — `perform`
    /// skips it entirely rather than falling back to an unrequested auto-name.
    private func promptRenames(for conflict: OverwriteConflict) -> [String: String] {
        var reserved = existingLocalNames(in: conflict.existingPaths)
        var choices: [String: String] = [:]
        for transfer in conflict.transfers {
            let path = destinationPath(for: transfer)
            guard conflict.conflictingPaths.contains(path) else { continue }
            var suggested = uniqueLocalName(for: entryName(transfer), avoiding: reserved)
            var message = "“\(entryName(transfer))” already exists here. Enter a new name for the incoming item."
            while true {
                guard let chosen = PathPromptPanel.present(
                    title: "Rename Item", message: message, currentValue: suggested
                ) else { break }
                guard reserved.contains(chosen) else {
                    choices[path] = chosen
                    reserved.insert(chosen)
                    break
                }
                // What they typed collides too — a plain re-prompt instead
                // of silently accepting it (which would just trade one
                // overwrite for another) or silently dropping the item.
                message = "“\(chosen)” also already exists here. Enter a different name."
                suggested = uniqueLocalName(for: chosen, avoiding: reserved)
            }
        }
        return choices
    }

    private func perform(
        _ transfers: [DragOut.EntryTransfer], move: Bool, renameChoices: [String: String] = [:]
    ) {
        pendingConflict = nil
        // A `Table` selection is always within one open archive, so in
        // practice every transfer shares the same source — grouped
        // defensively in case that's ever not true.
        let bySource = Dictionary(grouping: transfers, by: \.archiveURL)
        Task {
            var allFailures: [(name: String, reason: String)] = []
            for (sourceURL, group) in bySource {
                // The source archive's password, if any, lives only in that
                // window's own in-memory session — never written to the
                // pasteboard — so it's looked up live through the registry
                // rather than carried with the drag.
                let sourceViewModel = OpenArchiveWindowRegistry.viewModel(for: sourceURL)
                let password = sourceViewModel?.sessionPassword
                // Paired with its source transfer, not just the bare URL —
                // needed so a failure partway through never causes a Move to
                // delete a source entry that was never actually copied over.
                var succeeded: [(transfer: DragOut.EntryTransfer, url: URL)] = []
                for transfer in group {
                    do {
                        var extractedURL = try await DragOut.extract(
                            entryPath: transfer.entryPath, archiveURL: sourceURL, password: password
                        )
                        if let newName = renameChoices[destinationPath(for: transfer)] {
                            let renamedURL = extractedURL.deletingLastPathComponent().appendingPathComponent(newName)
                            try FileManager.default.moveItem(at: extractedURL, to: renamedURL)
                            extractedURL = renamedURL
                        }
                        succeeded.append((transfer, extractedURL))
                    } catch {
                        let name = entryName(transfer)
                        ArchiveLog.ui.error("Cross-archive transfer failed for \"\(name, privacy: .public)\": \(error.localizedDescription, privacy: .public)")
                        allFailures.append((name, error.localizedDescription))
                    }
                }
                guard !succeeded.isEmpty else { continue }
                // Awaited deliberately, not fire-and-forget: a Move must
                // never delete the source entries unless they genuinely
                // landed in this archive first. If the add itself fails
                // (unwritable format, disk full, the archive closed
                // mid-drop…), none of `group` gets deleted from its source —
                // otherwise a failed Move would just destroy data.
                do {
                    try await viewModel.addFilesAwaiting(succeeded.map(\.url))
                    if move {
                        await MainActor.run {
                            sourceViewModel?.deleteEntries(paths: succeeded.map { $0.transfer.entryPath }, notifySuccess: false)
                        }
                    }
                } catch {
                    ArchiveLog.ui.error("Adding to destination archive failed: \(error.localizedDescription, privacy: .public)")
                    for (transfer, _) in succeeded {
                        allFailures.append((entryName(transfer), error.localizedDescription))
                    }
                }
            }
            if allFailures.isEmpty {
                guard notifyOnAdd else { return }
                await MainActor.run {
                    viewModel.reportEditResult(
                        transfers.count == 1
                            ? "Added “\(entryName(transfers[0]))”."
                            : "Added \(transfers.count) items."
                    )
                }
                return
            }
            await MainActor.run {
                failureMessage = Self.failureSummary(allFailures)
            }
        }
    }

    private static func failureSummary(_ failures: [(name: String, reason: String)]) -> String {
        if failures.count == 1 {
            return "Couldn’t add “\(failures[0].name)”: \(failures[0].reason)"
        }
        let names = failures.map(\.name).joined(separator: ", ")
        return "Couldn’t add \(failures.count) items (\(names)). The rest were added normally."
    }
}
