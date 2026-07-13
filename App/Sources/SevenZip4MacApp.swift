import SwiftUI
import AppKit

/// Application entry point.
///
/// Owns the single ``ArchiveViewModel`` for the window and wires the File menu.
/// Finder double-click integration is a later phase (see ROADMAP); for now an
/// archive is opened via ⌘O or by dropping it onto the window.
@main
struct SevenZip4MacApp: App {
    @State private var viewModel = ArchiveViewModel()
    @State private var compression = CompressionViewModel()
    @State private var benchmark = BenchmarkViewModel()
    @State private var settings = AppSettings()
    @State private var profileStore = ProfileStore()
    @State private var recents = RecentsStore()

    @Environment(\.openWindow) private var openWindow

    init() {
        SingleInstance.enforceOrExit()
        // Reclaim any drag-out staging folders left behind by previous runs
        // (Finder copies the promised file itself and never signals us when
        // it's done, so leftovers are swept on launch instead).
        DragOut.sweepStaleStaging()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, compression: compression,
                        settings: settings, profileStore: profileStore, recents: recents)
                .onAppear { viewModel.onArchiveOpened = { recents.record($0) } }
                // Deliberately NOT auto-associating on first launch: macOS
                // shows a real confirmation dialog per format ("Do you want
                // .zip files to open with 7ZIP4MAC or keep using Archive
                // Utility?"), and firing all 32 at once on first launch would
                // ambush the user with a stack of system dialogs they didn't
                // ask for. Association only happens when the user explicitly
                // acts in Settings ▸ File Types (a toggle or "Associate All").
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
                .disabled(compression.isRunning)

                Button("Open Archive…") {
                    if let url = ArchiveOpenPanel.present() {
                        viewModel.open(url: url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    ForEach(recents.existing, id: \.self) { url in
                        Button(url.lastPathComponent) { viewModel.open(url: url) }
                    }
                    if !recents.existing.isEmpty {
                        Divider()
                        Button("Clear Menu") { recents.clear() }
                    }
                }
                .disabled(recents.existing.isEmpty)

                Button("Close Archive") {
                    viewModel.close()
                }
                .disabled(viewModel.archive == nil)

                Divider()

                Button("Extract All…") {
                    guard let archive = viewModel.archive,
                          let folder = DestinationPanel.present(suggestedName: archive.url.lastPathComponent)
                    else { return }
                    viewModel.extract(into: folder, intoSubfolder: settings.extractIntoSubfolder)
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(viewModel.archive == nil || viewModel.isExtracting)
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
