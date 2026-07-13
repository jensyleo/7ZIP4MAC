import SwiftUI
import SevenZipKit

/// The bottom status bar: a concise summary of the loaded archive.
struct StatusBarView: View {
    let archive: Archive

    var body: some View {
        HStack(spacing: 12) {
            Label("\(archive.fileCount) files", systemImage: "doc")
            Label("\(archive.folderCount) folders", systemImage: "folder")
            if let format = archive.properties.format {
                Label(format.uppercased(), systemImage: "shippingbox")
            }
            Spacer()
            Text("\(ByteFormatter.string(fromByteCount: Int64(archive.totalSize))) uncompressed")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
