import SwiftUI

/// Shown when no archive is open: invites the user to open or drop a file, and
/// lists recently opened archives for quick access.
struct EmptyStateView: View {
    let onOpen: () -> Void
    var recents: [URL] = []
    var onOpenRecent: (URL) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Image(systemName: "archivebox")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    Text("No Archive Open")
                        .font(.title2.weight(.semibold))
                    Text("Open a .7z, .zip, .rar or other archive to browse its contents.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button(action: onOpen) {
                    Label("Open Archive…", systemImage: "folder")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }

            if !recents.isEmpty {
                recentList
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(recents, id: \.self) { url in
                Button {
                    onOpenRecent(url)
                } label: {
                    Label {
                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    } icon: {
                        Image(systemName: "doc.zipper").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help(url.path)
            }
        }
        .frame(maxWidth: 320)
    }
}

/// Shown while an archive is being read.
struct LoadingStateView: View {
    let url: URL

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Reading \(url.lastPathComponent)…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown when opening an archive failed.
struct FailureStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.orange)
            Text("Couldn’t Open Archive")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open a Different Archive…", action: onRetry)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
