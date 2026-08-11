import Foundation
import UniformTypeIdentifiers
import SevenZipKit

/// Extracts an archive entry lazily on drop — used by `MultiItemDragTrigger`'s
/// file promises (drag out to Finder or into another 7ZIP4MAC window) and by
/// Quick Look. Nothing is written to disk if the drag is cancelled.
enum DragOut {

    /// Identifies a drag item as "an entry from one of our own archive
    /// windows" — declared alongside the normal file-promise types on the
    /// same `NSFilePromiseProvider` (see `MultiItemDragTrigger`), so a
    /// *different* 7ZIP4MAC window can recognize the drop as a cross-archive
    /// transfer instead of a plain file from Finder. The password isn't
    /// included (it never touches the pasteboard); the destination window
    /// looks up the source archive's live session password through
    /// ``OpenArchiveWindowRegistry`` instead.
    ///
    /// Read on the receiving end via `NSDraggingInfo.draggingPasteboard`
    /// directly (see `CrossArchiveDropTarget`), not through SwiftUI's
    /// `.onDrop` — that reads incoming drops through
    /// `NSDraggingInfo.itemProviders`, which doesn't bridge a type declared
    /// by a `NSFilePromiseProvider` the way it does one declared by a plain
    /// `NSPasteboardItem`, even though the data is genuinely on the
    /// pasteboard either way.
    static let crossArchiveTypeIdentifier = "com.jensyleo.sevenzip4mac.archive-entry"

    struct EntryTransfer: Codable {
        let archiveURL: URL
        let entryPath: String
        let isDirectory: Bool
    }

    /// Parent dir for all drag staging folders. Finder copies the promised
    /// file itself and never tells us when it's done, so we can't delete right
    /// after a drag — leftovers are reclaimed on launch via `sweepStaleStaging`.
    private static var stagingRoot: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "7ZIP4MAC-Drag", directoryHint: .isDirectory)
    }

    /// Extracts a single entry (a folder is extracted with its whole subtree)
    /// into a unique staging directory and returns the extracted item's URL.
    static func extract(
        entryPath: String,
        archiveURL: URL,
        password: String?
    ) async throws -> URL {
        let executable = try BundledEngine.resolve()
        let service = ArchiveService(executable: executable)

        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let temp = stagingRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let request = ExtractionRequest(
            archiveURL: archiveURL,
            destinationURL: temp,
            password: password,
            selectedPaths: [entryPath],
            overwritePolicy: .overwrite
        )
        try await service.extract(request) { _ in }

        // 7-Zip preserves the entry's path, so it lands at temp/<entryPath>.
        // Drop any trailing slash so a folder URL resolves to the real directory.
        let trimmed = entryPath.hasSuffix("/") ? String(entryPath.dropLast()) : entryPath
        return temp.appending(path: trimmed)
    }

    /// Deletes staging folders left over from previous drags. Call once at app
    /// startup — Finder never signals completion, so we sweep anything older
    /// than `age` instead.
    static func sweepStaleStaging(olderThan age: TimeInterval = 3600) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: stagingRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for url in items {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    static func typeIdentifier(for entry: ArchiveEntry) -> String {
        if entry.isDirectory {
            return UTType.folder.identifier
        }
        let ext = (entry.name as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext), !type.conforms(to: .text) {
            return type.identifier
        }
        // Text-conforming UTIs (plain text, source code, etc.) make Finder
        // treat the drop as a text clipping instead of accepting our file
        // promise, so the drop silently does nothing. A generic data type
        // still lets Finder land the file with its real name/extension.
        return UTType.data.identifier
    }
}
