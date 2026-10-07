import SwiftUI
import SevenZipKit

/// Shown while an integrity test runs. Until the engine reports its first
/// finished file there is no progress to show, so it starts as an animated
/// bar; afterwards it is the same panel Extract uses, with real percentage,
/// current file and time remaining.
struct TestingPanelView: View {
    let archiveName: String
    let progress: ProgressInfo?
    let onCancel: () -> Void

    var body: some View {
        if let progress, progress.totalBytes > 0 {
            ProgressPanelView(
                title: "Testing “\(archiveName)”",
                progress: progress,
                onCancel: onCancel
            )
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Testing “\(archiveName)”")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                ProgressView()
                    .progressViewStyle(.linear)

                Text("Reading the archive… progress appears once the first files are checked. This can take a long time for large archives or archives on a network volume.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: 460)
        }
    }
}
