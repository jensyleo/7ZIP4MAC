import SwiftUI
import SevenZipKit

/// The progress panel shown while an archive is being extracted.
///
/// Presentational only: it renders a ``ProgressInfo`` and reports a cancel
/// intent. Percentage, throughput, ETA, the current file and byte totals are
/// all shown, as the design requires.
struct ProgressPanelView: View {
    let title: String
    let progress: ProgressInfo
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(progress.displayPercent)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)

            Text(progress.currentFile ?? " ")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 20) {
                metric("Speed", progress.displaySpeed, systemImage: "speedometer")
                metric("Remaining", progress.displayETA, systemImage: "clock")
                metric("Size", progress.displayBytes, systemImage: "internaldrive")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func metric(_ label: String, _ value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
