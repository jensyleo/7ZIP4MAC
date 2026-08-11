import SwiftUI
import AppKit

/// Application entry point.
///
/// Each window owns its own `ArchiveViewModel`/`CompressionViewModel` (see
/// ``ArchiveWindowRoot``) — opening a second archive opens a second window,
/// the same as Preview or TextEdit, instead of replacing whatever the first
/// window was already showing. `Settings`, `ProfileStore` and `RecentsStore`
/// are app-wide preferences, shared across every window.
@main
struct SevenZip4MacApp: App {
    @State private var benchmark = BenchmarkViewModel()
    @State private var settings = AppSettings()
    @State private var profileStore = ProfileStore()
    @State private var recents = RecentsStore()

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    @FocusedValue(\.archiveViewModel) private var focusedViewModel
    @FocusedValue(\.compressionViewModel) private var focusedCompression

    init() {
        SingleInstance.enforceOrExit()
        // Reclaim any drag-out staging folders left behind by previous runs
        // (Finder copies the promised file itself and never signals us when
        // it's done, so leftovers are swept on launch instead).
        DragOut.sweepStaleStaging()
    }

    var body: some Scene {
        // A single `WindowGroup(for: URL?.self)`: one empty window opens
        // automatically at launch (value `nil`), and `openWindow(value:)`
        // opens (or focuses, if that URL is already open) a window for a
        // specific archive. A second, separate group for the same content
        // was tried first and caused macOS to spin up an extra scaffold
        // window — visibly flashing on screen — for every file-open request
        // that reached an already-running instance; one group avoids that.
        WindowGroup(id: "main", for: URL?.self) { $archiveURL in
            ArchiveWindowRoot(archiveURL: archiveURL ?? nil, settings: settings,
                              profileStore: profileStore, recents: recents)
                .onAppear { appDelegate.openWindow = openWindow }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About 7ZIP4MAC") { showAboutPanel() }
            }
            CommandGroup(replacing: .help) {
                Button("7ZIP4MAC Help") { showHelp() }
            }
            CommandMenu("Tools") {
                Button("Benchmark…") { openWindow(id: "benchmark") }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .newItem) {
                Button("New Archive…") {
                    guard let compression = focusedCompression else { return }
                    let sources = SourceSelectionPanel.present()
                    if !sources.isEmpty {
                        compression.begin(
                            sources: sources,
                            format: settings.defaultFormat,
                            level: settings.defaultLevel,
                            encryptFileNames: settings.defaultEncryptFileNames
                        )
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(focusedCompression?.isRunning ?? true)

                Button("Open Archive…") {
                    guard let url = ArchiveOpenPanel.present() else { return }
                    openArchiveRespectingFocusedWindow(url)
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    ForEach(recents.existing, id: \.self) { url in
                        Button(url.lastPathComponent) { openArchiveRespectingFocusedWindow(url) }
                    }
                    if !recents.existing.isEmpty {
                        Divider()
                        Button("Clear Menu") { recents.clear() }
                    }
                }
                .disabled(recents.existing.isEmpty)

                Button("Close Archive") {
                    focusedViewModel?.close()
                }
                .disabled(focusedViewModel?.archive == nil)

                Divider()

                Button("Extract All…") {
                    guard let viewModel = focusedViewModel, let archive = viewModel.archive,
                          let folder = DestinationPanel.present(suggestedName: archive.url.lastPathComponent)
                    else { return }
                    viewModel.extract(into: folder, intoSubfolder: settings.extractIntoSubfolder)
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(focusedViewModel?.archive == nil || (focusedViewModel?.isExtracting ?? false))
            }
        }

        Settings {
            SettingsView(settings: settings, profileStore: profileStore)
        }

        Window("Benchmark", id: "benchmark") {
            BenchmarkView(viewModel: benchmark)
        }
        .windowResizability(.contentMinSize)
    }

    /// Loads `url` into the focused window if it's empty; otherwise opens (or
    /// focuses, if already open) a separate window for it — an already-loaded
    /// window's archive should never be silently replaced.
    private func openArchiveRespectingFocusedWindow(_ url: URL) {
        if OpenArchiveWindowRegistry.focusIfOpen(url) { return }
        if let viewModel = focusedViewModel, viewModel.archive == nil {
            viewModel.open(url: url)
        } else {
            openWindow(value: url as URL?)
        }
    }
}

/// Concise help shown from the Help menu.
@MainActor
func showHelp() {
    let alert = NSAlert()
    alert.messageText = "How 7ZIP4MAC works"
    alert.informativeText = """
    7ZIP4MAC is a native interface for the official 7-Zip engine, bundled unmodified inside the app.

    • Open (⌘O) or drop an archive to browse its contents; double-click a folder to enter it.
    • New Archive (⌘N) creates a 7z / ZIP / TAR archive — pick a profile or your own \
    format, compression level and password.
    • Extract All (⌘E) extracts everything; select items first to extract only those.
    • Drag any entry straight to Finder to extract just that item there.
    • Select an item and press Space for a Quick Look preview.
    • Test verifies an archive's integrity without extracting it.
    • Encrypted archives prompt for a password when opened.
    • Tools ▸ Benchmark measures this Mac's compression speed.

    This app performs no compression itself — all archive operations run through the \
    official 7-Zip engine (see About for its license).
    """
    alert.runModal()
}

/// Standard About panel with 7-Zip engine credits.
/// (Name, version and copyright come from the Info.plist automatically.)
@MainActor
func showAboutPanel() {
    let credits = NSMutableAttributedString(
        string: "A native macOS interface for 7-Zip.\n\nThis app is a frontend only — all compression, extraction and encryption is performed by the official, unmodified 7-Zip engine, bundled with this app.\n\nBundles 7-Zip, Copyright © 1999–2026 Igor Pavlov, under the GNU LGPL (with unRAR restrictions and BSD-licensed components for some code).\n",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
    )
    credits.append(NSAttributedString(
        string: "gnu.org/licenses/lgpl-3.0",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .link: URL(string: "https://www.gnu.org/licenses/lgpl-3.0.html")!,
        ]
    ))
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    NSApp.activate(ignoringOtherApps: true)
}
