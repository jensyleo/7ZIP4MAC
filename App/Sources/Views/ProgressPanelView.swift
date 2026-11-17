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
    /// `nil` hides the Cancel button, for work that cannot be stopped safely.
    var onCancel: (() -> Void)?

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

            ExactProgressBar(fraction: progress.fractionCompleted)

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

            if let onCancel {
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
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


/// A progress bar drawn at exactly the fraction it is given, with no
/// animation of its own.
///
/// The system `ProgressView` (an `NSProgressIndicator`) animates every change
/// by itself, on its own clock, and cannot be told not to: with updates
/// arriving many times a second it trailed far behind the percentage printed
/// beside it (15% beside a bar at 2%) and, when a new stage started again
/// from zero, swept visibly backwards. This one is always where the number is
/// and snaps when the value drops.
struct ExactProgressBar: View {
    var fraction: Double

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(geometry.size.height, geometry.size.width * clamped))
                    .opacity(clamped > 0 ? 1 : 0)
            }
        }
        .frame(height: 6)
        .transaction { $0.animation = nil }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}
