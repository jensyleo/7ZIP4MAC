import Foundation
import Observation
import SevenZipKit

/// Drives the archive window: opening an archive, tracking load state, and
/// exposing the (sortable) list of entries to the UI.
///
/// All logic lives here; the Views only render `state`, `entries` and forward
/// user intents (`open`, `sort`) back to this model.
@MainActor
@Observable
public final class ArchiveViewModel {

    /// The lifecycle of the window's content.
    public enum State: Equatable {
        case empty
        case loading(URL)
        case loaded(Archive)
        case failed(message: String)
    }

    /// The lifecycle of an extraction operation.
    public enum ExtractionState: Equatable {
        case idle
        case running(ProgressInfo)
        /// `destination` is the folder extraction ran into; `revealTargets`
        /// are the specific item(s) Finder should select — for a flat
        /// single/multi-file extraction that's the extracted file(s), not
        /// the folder itself (selecting the folder would show it one level
        /// up, inside its parent, instead of opening straight to the file).
        case finished(destination: URL, revealTargets: [URL])
        case failed(message: String)
    }

    public private(set) var state: State = .empty

    public private(set) var extractionState: ExtractionState = .idle

    /// Entries of the currently loaded archive, in the current sort order.
    public private(set) var entries: [ArchiveEntry] = []

    /// The folder currently being browsed inside the archive ("" == root).
    public private(set) var currentFolder: String = ""

    /// The rows to show for `currentFolder`: its direct child files plus any
    /// subfolders (synthesized from entry paths when not listed explicitly).
    public private(set) var visibleEntries: [ArchiveEntry] = []

    /// Whether to show "hidden" entries (names starting with "." or "__",
    /// e.g. `.DS_Store`, `__MACOSX`) — off by default, mirrored from
    /// ``AppSettings/showHiddenEntries``.
    public var showHiddenEntries: Bool = false {
        didSet { recomputeVisible() }
    }

    /// The current sort order applied to `entries`.
    public var sortOrder: [KeyPathComparator<ArchiveEntry>] = [
        KeyPathComparator(\ArchiveEntry.name, order: .forward)
    ] {
        didSet { applySort() }
    }

    private let serviceProvider: @Sendable () throws -> ArchiveServing
    private var loadTask: Task<Void, Never>?
    private var extractTask: Task<Void, Never>?

    /// Called with the archive's URL whenever one is successfully opened.
    /// The app uses this to record recents.
    public var onArchiveOpened: ((URL) -> Void)?

    /// - Parameter serviceProvider: Produces the service used to open archives.
    ///   Injected so tests can supply a fake without the bundled engine.
    public init(serviceProvider: @escaping @Sendable () throws -> ArchiveServing) {
        self.serviceProvider = serviceProvider
    }

    /// Convenience initialiser wiring the production service over the bundled engine.
    public convenience init() {
        self.init(serviceProvider: {
            let executable = try BundledEngine.resolve()
            return ArchiveService(executable: executable)
        })
    }

    // MARK: - Derived state

    public var archiveURL: URL? {
        switch state {
        case .loaded(let archive): return archive.url
        case .loading(let url): return url
        case .empty, .failed: return nil
        }
    }

    public var archive: Archive? {
        if case .loaded(let archive) = state { return archive }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    public var isExtracting: Bool {
        if case .running = extractionState { return true }
        return false
    }

    // MARK: - Intents

    /// The archive currently awaiting a password (drives the unlock prompt).
    public private(set) var pendingPasswordURL: URL?
    /// True when the last password attempt for `pendingPasswordURL` was wrong.
    public private(set) var passwordAttemptFailed = false

    /// Wrong-password attempts for the current unlock prompt. Resets back to
    /// the empty state after `maxPasswordAttempts` to avoid leaving the
    /// archive half-open in a confusing state (browsable but unusable).
    public private(set) var passwordAttemptCount = 0
    public let maxPasswordAttempts = 3

    /// The password used to open the current archive, if any — kept only in
    /// memory for this session (never persisted) so in-place edits
    /// (Add/Delete/Move/Copy), Quick Look, and drag-out on an encrypted
    /// archive don't need to re-prompt for every single operation. Cleared
    /// when the archive closes.
    public private(set) var sessionPassword: String?

    /// Opens an archive at the given URL, replacing any current content. If
    /// it turns out to be encrypted, the unlock prompt is shown.
    public func open(url: URL, password: String? = nil) {
        attemptOpen(url: url, password: password)
    }

    /// Submits a password entered in the unlock prompt.
    public func submitPassword(_ password: String) {
        guard let url = pendingPasswordURL else { return }
        attemptOpen(url: url, password: password)
    }

    /// Dismisses the unlock prompt without opening. An archive left "open but
    /// locked" invites mistakes (browsing without being able to extract), so
    /// cancelling — via the Cancel button or Escape, which are the same
    /// action — resets all the way back to the empty state, as if the app
    /// had just launched, rather than leaving it half-open.
    public func cancelPasswordEntry() {
        pendingPasswordURL = nil
        passwordAttemptFailed = false
        passwordAttemptCount = 0
        close()
    }

    private func attemptOpen(url: URL, password: String?) {
        loadTask?.cancel()
        extractTask?.cancel()
        extractionState = .idle
        state = .loading(url)
        entries = []
        currentFolder = ""
        visibleEntries = []

        loadTask = Task { [serviceProvider] in
            do {
                let service = try serviceProvider()
                let archive = try await service.open(archiveAt: url, password: password)
                if Task.isCancelled { return }
                self.state = .loaded(archive)
                self.applySort()
                self.pendingPasswordURL = nil
                self.passwordAttemptFailed = false
                self.passwordAttemptCount = 0
                self.sessionPassword = password
                self.onArchiveOpened?(archive.url)
                // Some archives encrypt only entry *content*, not names/headers
                // — listing such an archive succeeds without ever needing a
                // password (7-Zip only asks for one once it has to decrypt
                // actual bytes). If we let that slide, the first Extract/Add/
                // etc. on an encrypted entry runs with no password at all,
                // and the engine falls back to an interactive prompt that
                // hangs against our closed stdin ("Break signaled", exit 255).
                // Ask for the password proactively in that case — the
                // archive is already loaded and browsable underneath, so
                // cancelling just means "browse only, don't extract yet".
                if password == nil, archive.entries.contains(where: \.isEncrypted) {
                    self.pendingPasswordURL = url
                }
            } catch is CancellationError {
                return
            } catch ArchiveError.wrongPassword {
                // Count every real wrong-password result even if a newer
                // attempt superseded (cancelled) this Task in the meantime —
                // the engine still genuinely rejected this password, and a
                // user retyping quickly shouldn't get extra free attempts.
                if password?.isEmpty == false {
                    self.passwordAttemptCount += 1
                    if self.passwordAttemptCount >= self.maxPasswordAttempts {
                        self.cancelPasswordEntry()
                        return
                    }
                }
                if Task.isCancelled { return }
                self.passwordAttemptFailed = (password?.isEmpty == false)
                self.pendingPasswordURL = url
                self.state = .empty
            } catch let error as ArchiveError {
                if Task.isCancelled { return }
                self.state = .failed(message: error.localizedDescription)
            } catch {
                if Task.isCancelled { return }
                self.state = .failed(message: error.localizedDescription)
            }
        }
    }

    /// Clears the window back to its empty state.
    public func close() {
        loadTask?.cancel()
        loadTask = nil
        extractTask?.cancel()
        extractTask = nil
        extractionState = .idle
        state = .empty
        entries = []
        currentFolder = ""
        visibleEntries = []
        sessionPassword = nil
    }

    // MARK: - Extraction

    /// Extracts the loaded archive into `folder`, creating a subfolder named
    /// after the archive. When `selectedPaths` is non-empty, only those entries
    /// are extracted.
    public func extract(into folder: URL, selectedPaths: [String] = [], intoSubfolder: Bool = true, flattenPaths: Bool = false) {
        guard case .loaded(let archive) = state else { return }
        extractTask?.cancel()
        extractionState = .running(.zero)

        let destination = intoSubfolder
            ? folder.appending(
                path: archive.url.deletingPathExtension().lastPathComponent,
                directoryHint: .isDirectory
              )
            : folder
        let total = uncompressedSize(of: archive, paths: selectedPaths)
        let request = ExtractionRequest(
            archiveURL: archive.url,
            destinationURL: destination,
            password: sessionPassword,
            selectedPaths: selectedPaths,
            overwritePolicy: .overwrite,
            totalUncompressedSize: total,
            flattenPaths: flattenPaths
        )
        // What Finder should select afterwards:
        //  • whole archive → the destination folder itself;
        //  • flat file selection → the extracted file(s) (which sit directly
        //    in the destination);
        //  • preserved selection (a folder, or files with paths) → each
        //    selected item at its recreated location under the destination,
        //    so Finder opens right to it instead of showing the destination
        //    folder selected inside its own parent.
        let revealTargets: [URL]
        if selectedPaths.isEmpty {
            revealTargets = [destination]
        } else if flattenPaths {
            revealTargets = selectedPaths.map { destination.appendingPathComponent(($0 as NSString).lastPathComponent) }
        } else {
            revealTargets = selectedPaths.map { destination.appendingPathComponent($0) }
        }

        extractTask = Task { [serviceProvider] in
            do {
                let service = try serviceProvider()
                try await service.extract(request) { info in
                    Task { @MainActor in
                        if case .running = self.extractionState {
                            self.extractionState = .running(info)
                        }
                    }
                }
                if Task.isCancelled { return }
                self.extractionState = .finished(destination: destination, revealTargets: revealTargets)
            } catch is CancellationError {
                self.extractionState = .idle
            } catch ArchiveError.cancelled {
                self.extractionState = .idle
            } catch let error as ArchiveError {
                self.extractionState = .failed(message: error.localizedDescription)
            } catch {
                self.extractionState = .failed(message: error.localizedDescription)
            }
        }
    }

    /// Cancels a running extraction.
    public func cancelExtraction() {
        extractTask?.cancel()
        extractTask = nil
        extractionState = .idle
    }

    /// Dismisses the finished/failed extraction result, returning to idle.
    public func dismissExtractionResult() {
        extractionState = .idle
    }

    // MARK: - Test

    /// Message from the last integrity test, shown in an alert.
    public private(set) var testMessage: String?

    /// Tests the integrity of the loaded archive.
    /// Tests the whole archive, or just `selectedPaths` when given.
    ///
    /// - Parameter notifySuccess: Whether to show an alert when the test
    ///   passes. A failed/damaged result always shows, regardless.
    public func test(selectedPaths: [String] = [], notifySuccess: Bool = true) {
        guard case .loaded(let archive) = state else { return }
        Task { [serviceProvider] in
            do {
                let service = try serviceProvider()
                let password = self.sessionPassword
                let ok = try await service.test(archiveAt: archive.url, selectedPaths: selectedPaths, password: password)
                guard ok == false || notifySuccess else { return }
                let subject = selectedPaths.count == 1
                    ? "“\((selectedPaths[0] as NSString).lastPathComponent)”"
                    : selectedPaths.isEmpty
                        ? "“\(archive.url.lastPathComponent)”"
                        : "\(selectedPaths.count) selected items"
                self.testMessage = ok
                    ? "\(subject) tested OK — no errors were found."
                    : "\(subject) failed the integrity test. It may be damaged."
            } catch let error as ArchiveError {
                self.testMessage = error.localizedDescription
            } catch {
                self.testMessage = error.localizedDescription
            }
        }
    }

    public func dismissTest() {
        testMessage = nil
    }

    // MARK: - Edit (add / delete / move / copy)

    /// Message from the last add/delete/move/copy, shown in an alert.
    public private(set) var editMessage: String?

    /// Adds files/folders into the archive under the folder currently being
    /// browsed (appends via `compress`, which is `7zz a` — an append/update
    /// when the destination archive already exists) and refreshes the listing.
    ///
    /// To land items under `currentFolder` rather than always at the
    /// archive's root, each source is staged into a scratch folder that
    /// mirrors `currentFolder`'s path before compressing — `7zz a` has no
    /// "add under this internal path" option; it only takes the archive path
    /// from the source's own path relative to the working directory.
    public func addFiles(_ sources: [URL], notifySuccess: Bool = true) {
        guard case .loaded(let archive) = state, !sources.isEmpty else { return }
        guard let format = Self.writableFormat(for: archive) else {
            editMessage = Self.unwritableFormatMessage(for: archive)
            return
        }
        let folder = currentFolder
        Task { [serviceProvider] in
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("7ZIP4MAC-Add-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            do {
                let destRoot = folder.isEmpty ? scratch : scratch.appendingPathComponent(folder, isDirectory: true)
                try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
                for source in sources {
                    try FileManager.default.copyItem(at: source, to: destRoot.appendingPathComponent(source.lastPathComponent))
                }
                // Whatever ended up directly inside `scratch` is what gets
                // added — either the files themselves (root) or the first
                // folder segment of `currentFolder` (preserving its nesting).
                let topLevelItems = try FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil)

                let service = try serviceProvider()
                let password = self.sessionPassword
                try await service.compress(
                    CompressionRequest(destinationURL: archive.url, sourceURLs: topLevelItems, format: format, password: password),
                    progress: { _ in }
                )
                try await self.reload(url: archive.url, password: password)
                guard notifySuccess else { return }
                self.editMessage = sources.count == 1
                    ? "Added “\(sources[0].lastPathComponent)”."
                    : "Added \(sources.count) items."
            } catch {
                self.editMessage = Self.describe(error)
            }
        }
    }

    /// Deletes entries from the archive in place and refreshes the listing.
    /// - Parameter notifySuccess: Whether to show a confirmation alert once
    ///   done. Failures always show, regardless.
    public func deleteEntries(paths: [String], notifySuccess: Bool = true) {
        guard case .loaded(let archive) = state, !paths.isEmpty else { return }
        Task { [serviceProvider] in
            do {
                let service = try serviceProvider()
                let password = self.sessionPassword
                try await service.delete(archiveAt: archive.url, paths: paths, password: password)
                try await self.reload(url: archive.url, password: password)
                guard notifySuccess else { return }
                self.editMessage = paths.count == 1
                    ? "Deleted “\((paths[0] as NSString).lastPathComponent)”."
                    : "Deleted \(paths.count) items."
            } catch {
                self.editMessage = Self.describe(error)
            }
        }
    }

    /// Moves (or renames) an entry to a new path within the same archive.
    public func moveEntry(path: String, toPath newPath: String, notifySuccess: Bool = true) {
        guard case .loaded(let archive) = state, path != newPath else { return }
        Task { [serviceProvider] in
            do {
                let service = try serviceProvider()
                let password = self.sessionPassword
                try await service.rename(archiveAt: archive.url, from: path, to: newPath, password: password)
                try await self.reload(url: archive.url, password: password)
                guard notifySuccess else { return }
                self.editMessage = "Moved “\((path as NSString).lastPathComponent)”."
            } catch {
                self.editMessage = Self.describe(error)
            }
        }
    }

    /// Duplicates an entry to a new path within the same archive.
    ///
    /// 7-Zip's CLI has no "copy within archive" command, so this extracts the
    /// entry to a scratch folder, restages it under `newPath`, and appends it
    /// back into the same archive via `compress` (which is `7zz a`, an append
    /// when the destination already exists).
    public func copyEntry(path: String, toPath newPath: String, notifySuccess: Bool = true) {
        guard case .loaded(let archive) = state, path != newPath else { return }
        guard let format = Self.writableFormat(for: archive) else {
            editMessage = Self.unwritableFormatMessage(for: archive)
            return
        }
        Task { [serviceProvider] in
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("7ZIP4MAC-Copy-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            do {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                let service = try serviceProvider()
                let password = self.sessionPassword

                try await service.extract(
                    ExtractionRequest(archiveURL: archive.url, destinationURL: scratch, password: password, selectedPaths: [path]),
                    progress: { _ in }
                )

                let extractedURL = scratch.appendingPathComponent(path)
                let stagedURL = scratch.appendingPathComponent(newPath)
                try FileManager.default.createDirectory(at: stagedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if extractedURL.standardizedFileURL != stagedURL.standardizedFileURL {
                    try FileManager.default.moveItem(at: extractedURL, to: stagedURL)
                }

                // The source handed to `compress` must be the top-level item
                // directly inside `scratch`, so its computed working directory
                // lands on `scratch` itself — otherwise `newPath`'s folder
                // structure would be lost (collapsed into just a filename).
                let topSegment = newPath.split(separator: "/", maxSplits: 1).first.map(String.init) ?? newPath
                try await service.compress(
                    CompressionRequest(
                        destinationURL: archive.url,
                        sourceURLs: [scratch.appendingPathComponent(topSegment)],
                        format: format,
                        password: password
                    ),
                    progress: { _ in }
                )

                try await self.reload(url: archive.url, password: password)
                guard notifySuccess else { return }
                self.editMessage = "Copied to “\(newPath)”."
            } catch {
                self.editMessage = Self.describe(error)
            }
        }
    }

    public func dismissEdit() {
        editMessage = nil
    }

    private static func describe(_ error: Error) -> String {
        (error as? ArchiveError)?.localizedDescription ?? error.localizedDescription
    }

    /// The container format to use when writing back into `archive` (Add,
    /// Copy), or nil if this archive's format can't be modified in place.
    ///
    /// Matching by file extension against `ArchiveFormat.allCases` and
    /// falling back to `.sevenZip` when there's no match was a real bug: for
    /// any archive that isn't actually .7z/.zip/.tar (RAR, ISO, GZip, and the
    /// ~30 other read-only-for-writing formats this app can open), it forced
    /// `-t7z` onto a file that isn't a 7z archive — silently failing or doing
    /// nothing instead of adding/copying anything. This requires an exact
    /// match; there is no guessing fallback.
    private static func writableFormat(for archive: Archive) -> ArchiveFormat? {
        ArchiveFormat.allCases.first { $0.fileExtension == archive.url.pathExtension.lowercased() }
    }

    private static func unwritableFormatMessage(for archive: Archive) -> String {
        "\(archive.properties.format ?? archive.url.pathExtension.uppercased()) archives can't be modified in place — only .7z, .zip and .tar support Add/Copy. (RAR in particular is read-only here, per the bundled engine's unRAR license.)"
    }

    /// Re-lists the archive after an in-place edit (delete/move/copy).
    private func reload(url: URL, password: String?) async throws {
        let service = try serviceProvider()
        let archive = try await service.open(archiveAt: url, password: password)
        self.state = .loaded(archive)
        self.applySort()
    }

    private func uncompressedSize(of archive: Archive, paths: [String]) -> UInt64 {
        guard !paths.isEmpty else { return archive.totalSize }
        let set = Set(paths)
        return archive.entries.lazy
            .filter { !$0.isDirectory && set.contains($0.path) }
            .reduce(0) { $0 + $1.size }
    }

    // MARK: - Sorting

    private func applySort() {
        guard case .loaded(let archive) = state else { return }
        // Directories first, then apply the user's comparator within each group,
        // matching Finder's default grouping behaviour.
        let sorted = archive.entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            for comparator in sortOrder {
                switch comparator.compare(lhs, rhs) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return false
        }
        entries = sorted
        recomputeVisible()
    }

    // MARK: - Navigation

    /// Path components of the current folder, for a breadcrumb bar.
    public var breadcrumbs: [String] {
        currentFolder.isEmpty ? [] : currentFolder.split(separator: "/").map(String.init)
    }

    /// Enters a subfolder row.
    public func enter(_ entry: ArchiveEntry) {
        guard entry.isDirectory else { return }
        currentFolder = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
        recomputeVisible()
    }

    /// Goes up one folder level.
    public func goUp() {
        guard !currentFolder.isEmpty else { return }
        var parts = currentFolder.split(separator: "/").map(String.init)
        parts.removeLast()
        currentFolder = parts.joined(separator: "/")
        recomputeVisible()
    }

    /// Navigates to the folder made of the first `count` breadcrumb components
    /// (0 == root).
    public func navigateToBreadcrumb(count: Int) {
        let parts = currentFolder.split(separator: "/").map(String.init)
        currentFolder = parts.prefix(count).joined(separator: "/")
        recomputeVisible()
    }

    /// Whether a name is macOS/Unix "hidden" noise: dotfiles (`.DS_Store`,
    /// `.git`) and zip-tool artifacts (`__MACOSX`).
    private static func isHiddenName(_ name: String) -> Bool {
        name.hasPrefix(".") || name.hasPrefix("__")
    }

    /// Rebuilds `visibleEntries` for `currentFolder` from the full `entries`.
    private func recomputeVisible() {
        let prefix = currentFolder.isEmpty ? "" : currentFolder + "/"
        var folderOrder: [String] = []
        var explicitFolders: [String: ArchiveEntry] = [:]
        var seenFolder = Set<String>()
        var files: [ArchiveEntry] = []

        for entry in entries {
            guard entry.path.hasPrefix(prefix) else { continue }
            let rest = String(entry.path.dropFirst(prefix.count))
            if rest.isEmpty { continue }
            if let slash = rest.firstIndex(of: "/") {
                let name = String(rest[..<slash])
                guard showHiddenEntries || !Self.isHiddenName(name) else { continue }
                if seenFolder.insert(name).inserted { folderOrder.append(name) }
            } else if entry.isDirectory {
                guard showHiddenEntries || !Self.isHiddenName(rest) else { continue }
                if seenFolder.insert(rest).inserted { folderOrder.append(rest) }
                explicitFolders[rest] = entry
            } else {
                guard showHiddenEntries || !Self.isHiddenName(entry.name) else { continue }
                files.append(entry)
            }
        }

        let folderRows: [ArchiveEntry] = folderOrder.map { name in
            explicitFolders[name] ?? ArchiveEntry(
                path: prefix + name, isDirectory: true, size: 0, packedSize: nil,
                modified: nil, crc: nil, isEncrypted: false, method: nil, attributes: nil
            )
        }

        // A ".." row to go up one level, Windows-Explorer / 7-Zip-for-Windows
        // style, in addition to the toolbar Up button.
        var rows = folderRows + files
        if !currentFolder.isEmpty {
            let parentLink = ArchiveEntry(
                path: "..", isDirectory: true, size: 0, packedSize: nil,
                modified: nil, crc: nil, isEncrypted: false, method: nil, attributes: nil
            )
            rows.insert(parentLink, at: 0)
        }
        visibleEntries = rows
    }
}
