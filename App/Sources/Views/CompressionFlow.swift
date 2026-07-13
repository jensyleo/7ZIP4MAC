import SwiftUI
import AppKit
import SevenZipKit

/// Hosts the sheets and alerts of the "create a new archive" flow, driven by
/// the ``CompressionViewModel`` phase. Kept as a modifier so `ContentView`
/// stays focused on the opened archive.
struct CompressionFlow: ViewModifier {
    @Bindable var compression: CompressionViewModel
    @Bindable var profileStore: ProfileStore
    /// Whether to reveal the created archive in Finder automatically.
    var revealWhenDone: Bool = false
    /// Called with the created archive when the user chooses to open it.
    let onOpenCreated: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: createdURL) { _, url in
                if let url, revealWhenDone {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .sheet(isPresented: configuringPresented) {
                CompressionOptionsView(
                    viewModel: compression,
                    profileStore: profileStore,
                    onCreate: presentSavePanel,
                    onCancel: compression.cancel
                )
            }
            .sheet(isPresented: runningPresented) {
                if case .running(let progress) = compression.phase {
                    ProgressPanelView(
                        title: "Creating \(compression.suggestedFileName)",
                        progress: progress,
                        onCancel: compression.cancel
                    )
                }
            }
            .alert("Archive Created", isPresented: finishedPresented, presenting: createdURL) { url in
                Button("Open") {
                    compression.dismissResult()
                    onOpenCreated(url)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    compression.dismissResult()
                }
                Button("Done", role: .cancel) { compression.dismissResult() }
            } message: { url in
                Text("“\(url.lastPathComponent)” was created.")
            }
            .alert("Couldn’t Create Archive", isPresented: failedPresented, presenting: failureMessage) { _ in
                Button("OK", role: .cancel) { compression.dismissResult() }
            } message: { message in
                Text(message)
            }
    }

    private func presentSavePanel() {
        guard let url = SavePanel.present(suggestedName: compression.suggestedFileName) else { return }
        compression.create(destination: url)
    }

    // MARK: - Phase → binding bridges

    private var configuringPresented: Binding<Bool> {
        Binding(get: { compression.isConfiguring }, set: { if !$0 { compression.cancel() } })
    }

    private var runningPresented: Binding<Bool> {
        Binding(get: { compression.isRunning }, set: { if !$0 { compression.cancel() } })
    }

    private var finishedPresented: Binding<Bool> {
        Binding(get: { createdURL != nil }, set: { if !$0 { compression.dismissResult() } })
    }

    private var failedPresented: Binding<Bool> {
        Binding(get: { failureMessage != nil }, set: { if !$0 { compression.dismissResult() } })
    }

    private var createdURL: URL? {
        if case .finished(let url) = compression.phase { return url }
        return nil
    }

    private var failureMessage: String? {
        if case .failed(let message) = compression.phase { return message }
        return nil
    }
}
