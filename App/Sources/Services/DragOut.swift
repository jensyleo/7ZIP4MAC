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
        password: String?,
        progress: @escaping @Sendable (ProgressInfo) -> Void = { _ in }
    ) async throws -> URL {
        let viewModel = OpenArchiveWindowRegistry.viewModel(for: archiveURL)
        let effectiveURL = viewModel?.effectiveArchiveURL ?? archiveURL
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
            overwritePolicy: .overwrite,
            totalUncompressedSize: Self.uncompressedSize(forEntryPath: entryPath, in: viewModel?.entries ?? [])
        )
        try await service.extract(request, progress: progress)
        let extracted = try locateExtractedItem(forEntryPath: entryPath, in: temp)
        try Self.rejectSymlinkEscapingScratch(extracted, scratch: temp)
        return extracted
    }

    /// Sums the uncompressed size of `entryPath` — itself if it's a file, or
    /// everything under it if it's a folder — so the extraction this drives
    /// can report a real percentage/ETA instead of an indeterminate one.
    /// `entries` comes from the source window's already-loaded listing, not
    /// a fresh read, so this is just arithmetic over what's already in memory.
    private static func uncompressedSize(forEntryPath entryPath: String, in entries: [ArchiveEntry]) -> UInt64 {
        let prefix = entryPath + "/"
        return entries.lazy
            .filter { !$0.isDirectory && ($0.path == entryPath || $0.path.hasPrefix(prefix)) }
            .reduce(0) { $0 + $1.size }
    }

    /// Moves `source` (inside our own scratch directory) to `destination`
    /// (the promise's real, Finder-chosen URL), reporting real progress —
    /// unlike a bare `FileManager.moveItem`, which is silent and, within a
    /// single volume, an instant metadata-only rename anyway (so there's
    /// nothing to show progress *for* in that common case: `progress(1)`
    /// fires essentially immediately, which is simply the truth, not a bug).
    /// Crossing volumes (an external drive, a network share) is where a move
    /// is actually a real byte-for-byte copy that can take real time —
    /// that's the case this reports on incrementally, by polling how much
    /// `FileManager.copyItem` has written so far rather than reimplementing
    /// file I/O by hand (still using Foundation's own, already-correct
    /// copy for directories/symlinks/permissions/resource forks).
    static func moveWithProgress(
        from source: URL,
        to destination: URL,
        progress: @escaping @Sendable (_ copiedBytes: UInt64, _ totalBytes: UInt64) -> Void
    ) async throws {
        guard !Self.isSameVolume(source, destination) else {
            try FileManager.default.moveItem(at: source, to: destination)
            progress(1, 1)
            return
        }
        let total = Self.totalSize(of: source)
        guard total > 0 else {
            try FileManager.default.copyItem(at: source, to: destination)
            try? FileManager.default.removeItem(at: source)
            progress(1, 1)
            return
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try FileManager.default.copyItem(at: source, to: destination)
            }
            group.addTask {
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    let copied = Self.totalSize(of: destination)
                    progress(min(copied, total), total)
                }
            }
            try await group.next()  // the copy task, in practice — the poller never finishes on its own
            group.cancelAll()
        }
        progress(total, total)
        try? FileManager.default.removeItem(at: source)
    }

    /// Whether `source` and the folder `destination` will land in are on the
    /// same volume — `destination` itself may not exist yet (it's the
    /// promise's target path), so this checks its *parent* instead. Errors
    /// (an unreadable volume identifier) are treated as "different volumes",
    /// the safer assumption: it only costs a redundant copy+delete instead
    /// of silently skipping real progress reporting that was needed.
    private static func isSameVolume(_ source: URL, _ destination: URL) -> Bool {
        guard
            let sourceID = try? source.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? AnyHashable,
            let destID = try? destination.deletingLastPathComponent()
                .resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? AnyHashable
        else { return false }
        return sourceID == destID
    }

    /// Recursively sums the byte size of `url` (itself if a file, everything
    /// under it if a folder) — used both to size `moveWithProgress`'s total
    /// and, while a cross-volume copy is running, to poll how much of
    /// `destination` has been written so far.
    private static func totalSize(of url: URL) -> UInt64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if isDirectory.boolValue {
            var total: UInt64 = 0
            let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
            while let child = enumerator?.nextObject() as? URL {
                let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true {
                    total += UInt64(values?.fileSize ?? 0)
                }
            }
            return total
        }
        return UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// Refuses an extracted item that's a symlink pointing outside `scratch`
    /// — 7-Zip recreates a symlink entry's target verbatim, and that target
    /// is just as untrusted as the entry's own name. Unlike a crafted
    /// *name* (already handled by never building paths from `entryPath`),
    /// a crafted *target* like "/Users/me/.ssh/id_rsa" is the resolved
    /// result the OS itself will follow the moment anything reads through
    /// this link — most immediately Quick Look, which `DragOut.extract`
    /// also feeds: pressing Space on an entry that looks like an innocuous
    /// file would silently render the real target file's content instead
    /// (found in security audit, 2026-09-18). A symlink whose target
    /// resolves *inside* `scratch` (pointing at another file 7-Zip also
    /// just extracted) is harmless and left alone.
    private static func rejectSymlinkEscapingScratch(_ url: URL, scratch: URL) throws {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return
        }
        let resolvedTarget = URL(fileURLWithPath: target, relativeTo: url.deletingLastPathComponent())
            .standardizedFileURL
        let scratchPath = scratch.standardizedFileURL.path
        guard resolvedTarget.path == scratchPath || resolvedTarget.path.hasPrefix(scratchPath + "/") else {
            throw ArchiveError.operationFailed(
                code: -1,
                message: "This entry is a symbolic link pointing outside the archive's extracted contents and can't be opened this way."
            )
        }
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
        let ext = (entry.name as NSString).pathExtension
        if entry.isDirectory {
            // A directory whose name is a known package extension (.app,
            // .bundle, .framework, …) needs that real UTI declared, not a
            // generic "public.folder": Finder silently refused the drop
            // entirely for one of these when it was promised as a plain
            // folder while ending in ".app" — no error, the drag just did
            // nothing ("con un archivo y carpeta funciona bien, pero con una
            // carpeta con extensión .app no pasa nada" — 2026-09-17).
            // `conformingTo: .package` synthesizes a placeholder "dyn.*"
            // identifier for any extension it doesn't actually recognize as
            // a package type — never nil — so that has to be filtered back
            // out, or *every* folder with a dot in its name (a plain folder
            // named "notes.2024", say) would wrongly take this branch too.
            if !ext.isEmpty, let type = UTType(filenameExtension: ext, conformingTo: .package),
               !type.identifier.hasPrefix("dyn.") {
                return type.identifier
            }
            return UTType.folder.identifier
        }
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
