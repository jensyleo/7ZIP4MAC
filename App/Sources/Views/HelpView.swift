import SwiftUI

/// "7ZIP4MAC Help" window — searchable sidebar of topics rather than one long
/// scrolling page, so a question has a place to be looked up rather than
/// scrolled to. Mirrored from jensyleo's own ROMForge.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var topics: [HelpTopic] = HelpLibrary.topics
    @State private var selection: HelpTopic.ID? = HelpLibrary.topics.first?.id
    @State private var query = ""

    private var matches: [HelpTopic] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return topics }
        return topics.filter { topic in
            if topic.title.lowercased().contains(needle) { return true }
            return topic.sections.contains { section in
                (section.heading?.lowercased().contains(needle) ?? false)
                    || section.paragraphs.contains { $0.lowercased().contains(needle) }
                    || section.rows.contains {
                        $0.term.lowercased().contains(needle) || $0.detail.lowercased().contains(needle)
                    }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(matches) { topic in
                        Label(topic.title, systemImage: topic.symbol).tag(topic.id)
                    }
                }
                .searchable(text: $query, placement: .sidebar, prompt: "Search help")
                .navigationSplitViewColumnWidth(min: 220, ideal: 240)
                .overlay {
                    if matches.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
            } detail: {
                if let topic = topics.first(where: { $0.id == selection }) {
                    TopicPage(topic: topic)
                } else {
                    ContentUnavailableView("Pick a topic", systemImage: "book")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

private struct TopicPage: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(topic.title)
                    .font(.largeTitle.weight(.semibold))
                    .textSelection(.enabled)

                ForEach(topic.sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        if let heading = section.heading {
                            Text(heading).font(.title3.weight(.semibold))
                        }

                        ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !section.rows.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                    if index > 0 { Divider() }
                                    TermRow(row: row)
                                }
                            }
                            .background(.quinary, in: .rect(cornerRadius: 8))
                        }
                    }
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .textSelection(.enabled)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TermRow: View {
    let row: HelpSection.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.term).font(.body.weight(.medium))
                if let note = row.note {
                    Text(note)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                }
            }
            Text(row.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HelpView()
}
