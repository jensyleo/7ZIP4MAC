import SwiftUI
import AppKit

/// Tracks whether any window has already been shown in this launch of the
/// app — see the "orphan scaffold window" comment in `ArchiveWindowRoot`
/// below for why this exists instead of checking `NSApp.windows.count` at
/// the moment each window resolves.
private enum WindowLaunchTracker {
    nonisolated(unsafe) static var hasShownAnyWindow = false
}

/// One per window: owns that window's own `ArchiveViewModel` and
/// `CompressionViewModel` so every window is fully independent — opening a
/// second archive never touches whatever the first window is showing.
/// `settings`/`profileStore`/`recents` are app-wide and shared across every
/// window instead.
struct ArchiveWindowRoot: View {
    let archiveURL: URL?
    @Bindable var settings: AppSettings
    @Bindable var profileStore: ProfileStore
    @Bindable var recents: RecentsStore

    @State private var viewModel = ArchiveViewModel()
    @State private var compression = CompressionViewModel()
    @State private var hostWindow: NSWindow?
    // Wires this window into the shared QLPreviewPanel; created once the
    // window resolves and held here for the window's whole lifetime (its
    // link into the responder chain isn't a retaining one — see
    // `QuickLookPanelController.init`).
    @State private var quickLookController: QuickLookPanelController?
    // Set while this window is provisionally hidden pending the orphan check
    // below — cleared (and the window revealed) the moment it turns out to
    // be receiving real content after all.
    @State private var isHiddenPendingOrphanCheck = false
    // A small/fast archive can finish opening (and call `onArchiveOpened`)
    // before `WindowAccessor` has resolved `hostWindow` — registration would
    // silently no-op in that race, leaving this window undetectable as
    // "already open" until it's closed and reopened. Remembering the URL
    // here lets whichever of the two resolves *second* complete it instead.
    @State private var pendingRegistrationURL: URL?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ContentView(viewModel: viewModel, compression: compression,
                    settings: settings, profileStore: profileStore, recents: recents,
                    quickLookController: quickLookController)
            .focusedValue(\.archiveViewModel, viewModel)
            .focusedValue(\.compressionViewModel, compression)
            .background(WindowAccessor { window in
                hostWindow = window
                if quickLookController == nil {
                    quickLookController = QuickLookPanelController(window: window)
                }
                if let urlToRegister = pendingRegistrationURL {
                    OpenArchiveWindowRegistry.register(urlToRegister, window: window, viewModel: viewModel)
                    pendingRegistrationURL = nil
                }
                // macOS opens a fresh default (empty) window as scaffolding
                // for every "open this file" request that reaches an
                // already-running app, on top of however many other windows
                // already exist — sometimes more than one for a single
                // request. Rather than let it flash on screen and close it a
                // moment later (visible, looks like a bug — this is the
                // "app seems slow to show the file" symptom reported
                // 2026-09-13), hide it before it ever gets shown; it's
                // revealed again immediately below if it turns out to be a
                // genuine new window after all.
                //
                // Checking `NSApp.windows.count > 1` here used to decide
                // this, but that's a race: it only catches the scaffold
                // window if some *other* window has already finished
                // resolving by the time this one's callback runs — with no
                // guaranteed order, the scaffold's own callback often ran
                // *first*, saw a count of 1, and never got hidden at all
                // (confirmed by screen-capturing an actual open — the empty
                // window was plainly visible before the real one appeared on
                // top of it). `WindowLaunchTracker` instead orders this by
                // *when* each window is first shown in this launch: only the
                // very first window shown (the normal single-window case, or
                // this app's own initial empty window at launch) is ever
                // exempt: everything after it that arrives empty is treated
                // as a scaffold candidate, independent of how many other
                // windows exist at that exact instant.
                let isFirstWindowThisLaunch = !WindowLaunchTracker.hasShownAnyWindow
                WindowLaunchTracker.hasShownAnyWindow = true
                // Being first doesn't make this legitimate when the app was
                // launched specifically to open a file (`AppDelegate` sets
                // this before SwiftUI ever creates this window): that real
                // archive window is on its way regardless of window order,
                // so an empty one showing up "first" here is still a
                // scaffold, not the normal single-window-on-plain-launch
                // case ("la app se abre 2 veces" — 2026-09-17).
                let isOrphanCandidate = archiveURL == nil
                    && (!isFirstWindowThisLaunch || AppDelegate.isOpeningFileAtLaunch)
                if isOrphanCandidate {
                    window.orderOut(nil)
                    isHiddenPendingOrphanCheck = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // `.empty` (not `.loading`/`.loaded`/`.failed`) means
                        // nothing ever tried to open anything here — a real
                        // open call sets `.loading` synchronously, so a
                        // window that's merely slow to finish loading is
                        // never mistaken for an orphan.
                        if viewModel.state == .empty {
                            window.close()
                        }
                    }
                }
            })
            .onChange(of: viewModel.state) { _, newState in
                // This window turned out to be receiving real content (either
                // loading its own archive, or about to be dismissed in favor
                // of an existing window for the same one) — either way it's
                // no longer an orphan candidate, so let it be seen again.
                if isHiddenPendingOrphanCheck, newState != .empty, let hostWindow {
                    hostWindow.makeKeyAndOrderFront(nil)
                    isHiddenPendingOrphanCheck = false
                }
            }
            .onAppear {
                viewModel.onArchiveOpened = { url in
                    recents.record(url)
                    if let hostWindow {
                        OpenArchiveWindowRegistry.register(url, window: hostWindow, viewModel: viewModel)
                    } else {
                        pendingRegistrationURL = url
                    }
                }
                if let archiveURL, viewModel.archive == nil {
                    viewModel.open(url: archiveURL)
                }
                // Point the user at Settings ▸ File Types once, on first
                // launch — but never associate anything automatically: macOS
                // shows a real confirmation dialog per format ("Do you want
                // .zip files to open with 7ZIP4MAC or keep using Archive
                // Utility?"), and firing all of them at once would ambush the
                // user with a stack of system dialogs they didn't ask for.
                // The "Associate Recommended Files…" button there warns
                // about that before doing anything.
                if !settings.hasShownFileTypesOnboarding {
                    openSettings()
                }
            }
            .onDisappear {
                if let url = viewModel.archiveURL {
                    OpenArchiveWindowRegistry.unregister(url)
                }
            }
    }
}
