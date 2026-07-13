import Foundation
import Observation

/// Tracks recently opened archives, persisted in `UserDefaults`.
@MainActor
@Observable
public final class RecentsStore {
    private let defaults: UserDefaults
    private let key = "recentArchives"
    private let maxCount = 10

    /// Most-recent-first list of archive URLs (may include missing files).
    public private(set) var urls: [URL] = []

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        urls = (defaults.array(forKey: key) as? [String] ?? []).map { URL(fileURLWithPath: $0) }
    }

    /// The recents that still exist on disk.
    public var existing: [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Records an archive as most-recently opened.
    public func record(_ url: URL) {
        let standardized = url.standardizedFileURL
        urls.removeAll { $0 == standardized }
        urls.insert(standardized, at: 0)
        if urls.count > maxCount { urls.removeLast(urls.count - maxCount) }
        save()
    }

    /// Clears the entire history.
    public func clear() {
        urls = []
        save()
    }

    private func save() {
        defaults.set(urls.map(\.path), forKey: key)
    }
}
