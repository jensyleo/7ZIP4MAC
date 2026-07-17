import Foundation
import UniformTypeIdentifiers
import SevenZipKit

/// Builds drag item providers that extract an archive entry lazily — only when
/// the user actually drops it onto Finder (a file promise). Nothing is written
/// to disk if the drag is cancelled.
enum DragOut {

    /// Parent dir for all drag staging folders. Finder copies the promised
    /// file itself and never tells us when it's done, so we can't delete right
    /// after a drag — leftovers are reclaimed on launch via `sweepStaleStaging`.
    private static var stagingRoot: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "7ZIP4MAC-Drag", directoryHint: .isDirectory)
    }

    /// An item provider for dragging a single entry out of the archive.
    ///
    /// - Parameters:
    ///   - entry: The file or folder to drag out.
    ///   - archiveURL: The archive the entry lives in.
    ///   - password: Password for encrypted archives, if any (read live at
    ///     drag-start by the caller). Empty is treated as "no password".
    static func itemProvider(
        for entry: ArchiveEntry,
        archiveURL: URL,
        password rawPassword: String?
    ) -> NSItemProvider {
        // Treat "" as nil so the engine never gets a bare `-p` (which can make
        // it block on an interactive password prompt).
        let password = (rawPassword?.isEmpty == false) ? rawPassword : nil
        let provider = NSItemProvider()
        provider.suggestedName = entry.name

        let typeIdentifier = Self.typeIdentifier(for: entry)
        let entryPath = entry.path

        provider.registerFileRepresentation(
            forTypeIdentifier: typeIdentifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            let progress = Progress(totalUnitCount: 1)
            Task.detached {
                do {
                    let url = try await Self.extract(
                        entryPath: entryPath,
                        archiveURL: archiveURL,
                        password: password
                    )
                    progress.completedUnitCount = 1
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return progress
        }
        return provider
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
