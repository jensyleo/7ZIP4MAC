import SwiftUI
import SevenZipKit

/// The Benchmark window. Presentational — renders `viewModel.state` and starts
/// or cancels the run.
struct BenchmarkView: View {
    @Bindable var viewModel: BenchmarkViewModel

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            placeholder(
                icon: "speedometer",
                title: "Benchmark",
                message: "Measure this Mac's compression and decompression speed using the 7-Zip engine."
            )
        case .running:
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Running benchmark…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            placeholder(icon: "exclamationmark.triangle", title: "Benchmark Failed", message: message)
        case .done(let result):
            results(result)
        }
    }

    private func results(_ result: BenchmarkResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let cpu = result.cpuModel {
                    HStack {
                        Label(cpu, systemImage: "cpu")
                        if let ram = result.ramSizeMB {
                            Spacer()
                            Label("\(ram) MB RAM", systemImage: "memorychip")
                        }
                    }
                    .foregroundStyle(.secondary)
                    .font(.callout)
                }

                HStack(spacing: 12) {
                    ratingCard("Compress", value: result.compressRatingMIPS, systemImage: "arrow.down.right.and.arrow.up.left")
                    ratingCard("Decompress", value: result.decompressRatingMIPS, systemImage: "arrow.up.left.and.arrow.down.right")
                    ratingCard("Total", value: result.totalRatingMIPS, systemImage: "gauge.with.dots.needle.67percent", prominent: true)
                }

                if !result.rows.isEmpty {
                    Text("By dictionary size")
                        .font(.headline)
                    Table(result.rows) {
                        TableColumn("Dict") { Text("\($0.dictionary) (\(dictMiB($0.dictionary)))") }
                        TableColumn("Compress MIPS") { Text("\($0.compressRatingMIPS)").monospacedDigit() }
                        TableColumn("Compress KiB/s") { Text("\($0.compressSpeedKiBs)").monospacedDigit().foregroundStyle(.secondary) }
                        TableColumn("Decompress MIPS") { Text("\($0.decompressRatingMIPS)").monospacedDigit() }
                        TableColumn("Decompress KiB/s") { Text("\($0.decompressSpeedKiBs)").monospacedDigit().foregroundStyle(.secondary) }
                    }
                    .frame(minHeight: 160)
                }
            }
            .padding(20)
        }
    }

    private func ratingCard(_ title: String, value: Int?, systemImage: String, prominent: Bool = false) -> some View {
        VStack(spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.map { "\($0)" } ?? "—")
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text("MIPS").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(prominent ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            if case .done(let r) = viewModel.state, let total = r.totalRatingMIPS {
                Text("Total rating: \(total) MIPS").foregroundStyle(.secondary).font(.callout)
            }
            Spacer()
            if viewModel.isRunning {
                Button("Cancel", role: .cancel) { viewModel.cancel() }
            } else {
                Button(viewModel.result == nil ? "Run Benchmark" : "Run Again") { viewModel.run() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private func placeholder(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func dictMiB(_ exponent: Int) -> String {
        let bytes = 1 << exponent
        return ByteFormatter.string(fromByteCount: Int64(bytes))
    }
}
