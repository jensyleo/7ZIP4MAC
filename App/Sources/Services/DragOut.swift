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
    ///
    /// - Parameter archiveURL: The archive's own on-disk location, as shown
    ///   in the window title — *not* necessarily where 7-Zip should read
    ///   from. Resolved through ``OpenArchiveWindowRegistry`` to that
    ///   window's live ``ArchiveViewModel/effectiveArchiveURL`` first, so a
    ///   drag-out or Quick Look on an unwrapped `.tar.bz2`/`.tar.gz`/… reads
    ///   from the real archive extracted inside it, not the single-stream
    ///   compressor 7-Zip can't select individual entries from.
    @MainActor
    static func extract(
        entryPath: String,
        archiveURL: URL,
        password: String?
    ) async throws -> URL {
        let effectiveURL = OpenArchiveWindowRegistry.viewModel(for: archiveURL)?.effectiveArchiveURL ?? archiveURL
        let executable = try BundledEngine.resolve()
        let service = ArchiveService(executable: executable)

        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let temp = stagingRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let request = ExtractionRequest(
            archiveURL: effectiveURL,
            destinationURL: temp,
            password: password,
            selectedPaths: [entryPath],
            overwritePolicy: .overwrite
        )
        try await service.extract(request) { _ in }
        return try locateExtractedItem(forEntryPath: entryPath, in: temp)
    }

    /// Finds the item 7-Zip actually extracted for `entryPath` inside `root`,
    /// without ever building a filesystem path by concatenating `entryPath`
    /// itself: that's an untrusted string from inside a possibly-malicious
    /// archive, and a name like "../../../../Users/me/.ssh/id_rsa" would
    /// resolve outside `root` to a real file on disk — which callers then
    /// *move*, silently relocating or exfiltrating whatever that traversal
    /// landed on (found in security audit, 2026-09-16).
    ///
    /// Instead this walks the real directories 7-Zip wrote under `root`, one
    /// level per path component of `entryPath`, requiring each ancestor to
    /// have exactly one child before descending into it. A malicious
    /// `entryPath` can't steer this anywhere unsafe: 7-Zip sanitizes `../`
    /// itself, so everything under `root` is already confined there, and
    /// this only ever *counts* `entryPath`'s components (to know how many
    /// levels an entry like "docs/reports/file.pdf" should nest) — never
    /// their content. Not comparing each level's name against the expected
    /// component too: entry names round-tripped through the archive can
    /// differ in Unicode normalization from what 7-Zip writes to an APFS
    /// volume, which would otherwise fail a perfectly legitimate extraction.
    ///
    /// Fixes a regression from that same audit fix, which returned `root`'s
    /// *only top-level* item — the first path component's directory — for
    /// any nested entry, dragging out the whole ancestor folder chain
    /// instead of the file itself ("se trae toda la ruta de directorios,
    /// los crea en vez de dejarlo donde yo le digo" — 2026-09-17). Shared
    /// with `ArchiveViewModel.copyEntry`, which extracts a single entry into
    /// a scratch folder the same way and has the same nesting problem.
    static func locateExtractedItem(forEntryPath entryPath: String, in root: URL) throws -> URL {
        let trimmed = entryPath.hasSuffix("/") ? String(entryPath.dropLast()) : entryPath
        let depth = trimmed.split(separator: "/").count
        var current = root
        for _ in 0..<max(depth, 1) {
            let children = try FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: nil)
            guard let onlyChild = children.first, children.count == 1 else {
                throw ArchiveError.operationFailed(code: -1, message: "Extraction did not produce the expected single item.")
            }
            current = onlyChild
        }
        return current
    }

    /// Deletes staging folders left over from previous drags. Call once at app
    /// startup — Finder never signals completion, so we sweep anything older
    /// than `age` instead. Use 24 hours (not 1 hour) to avoid race conditions
    /// where a drag is still in progress when the app restarts.
    static func sweepStaleStaging(olderThan age: TimeInterval = 86400) {
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
