import SwiftUI
import SevenZipKit

/// Trailing inspector: entry detail for the selected row.
struct InspectorView: View {
    let entry: ArchiveEntry?

    var body: some View {
        Group {
            if let entry {
                content(entry)
            } else {
                ContentUnavailableView("No Selection",
                                       systemImage: "sidebar.right",
                                       description: Text("Select a single item to see its details."))
            }
        }
        .frame(minWidth: 260)
    }

    private func content(_ entry: ArchiveEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    EntryIcon(entry: entry)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading) {
                        Text(entry.name).font(.headline)
                        Text(entry.parentPath.isEmpty ? "/" : entry.parentPath)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                section("Entry") {
                    row("Type", entry.isDirectory ? "Folder" : "File")
                    row("Path", entry.path, mono: true)
                    row("Attributes", entry.attributes ?? "—", mono: true)
                }

                section("Size") {
                    row("Uncompressed", entry.displaySize)
                    row("Compressed", entry.displayPackedSize)
                    row("Ratio", ratioText(entry))
                }

                section("Details") {
                    row("Modified", entry.displayModified)
                    row("CRC", entry.crc ?? "—", mono: true)
                    row("Method", entry.method ?? "—")
                    row("Encrypted", entry.isEncrypted ? "Yes" : "No",
                        tint: entry.isEncrypted ? .orange : nil)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ratioText(_ entry: ArchiveEntry) -> String {
        guard let packed = entry.packedSize, entry.size > 0 else { return "—" }
        let pct = (Double(packed) / Double(entry.size)) * 100
        return String(format: "%.0f%%", pct)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String, tint: Color? = nil, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value)
                .foregroundStyle(tint ?? .primary)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}
