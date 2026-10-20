import Foundation

/// The clutter macOS adds to archives it creates (`__MACOSX/`, `._*` resource
/// forks, `.DS_Store`, and a few volume-metadata folders). It's the
/// archive-side counterpart of what Finder hides: never content the user put
/// there, and usually unwanted once the archive leaves a Mac.
public enum MacOSJunk {
    /// Folders whose entire contents are junk.
    static let folderNames: Set<String> = [
        "__MACOSX", ".AppleDouble", ".Spotlight-V100", ".Trashes",
        ".fseventsd", ".TemporaryItems", ".DocumentRevisions-V100",
    ]
    /// Individual junk files, by exact name (plus any `._*` file).
    static let fileNames: Set<String> = [".DS_Store", ".apdisk", ".VolumeIcon.icns", "Icon\r"]

    /// Whether `path` is junk, or lives inside a junk folder.
    public static func isJunk(path: String) -> Bool {
        isJunk(components: components(of: path))
    }

    private static func components(of path: String) -> [String] {
        path.trimmingTrailingSlash.split(separator: "/").map(String.init)
    }

    private static func isJunk(components: [String]) -> Bool {
        guard let last = components.last else { return false }
        if components.contains(where: folderNames.contains) { return true }
        return fileNames.contains(last) || (last.hasPrefix("._") && last.count > 2)
    }

    /// Whether a single row name stays out of the way while browsing by
    /// default: dotfiles, plus `__MACOSX` itself. Other names that merely start
    /// with `__` (`__init__.py`, `__tests__`) are real content and stay visible.
    public static func isHiddenName(_ name: String) -> Bool {
        name.hasPrefix(".") || name == "__MACOSX"
    }

    /// What a cleanup would remove from an archive.
    public struct Summary: Equatable, Sendable {
        /// The minimal paths to delete: a junk folder stands for everything
        /// under it, so there is one root per folder instead of one per file.
        public let roots: [String]
        /// How many junk files that is (folders themselves aren't counted).
        public let fileCount: Int

        public static let none = Summary(roots: [], fileCount: 0)
        public var isEmpty: Bool { roots.isEmpty }

        /// A few root names, for the confirmation text.
        public var exampleNames: [String] {
            var seen = Set<String>()
            let names = roots.map { ($0 as NSString).lastPathComponent }.filter { seen.insert($0).inserted }
            return Array(names.prefix(4))
        }
    }

    /// What a cleanup would remove. A path containing `*` or `?` is left out:
    /// 7-Zip reads those as wildcards when deleting, so such a name could
    /// match entries it was never meant to.
    public static func summary(of entries: [ArchiveEntry]) -> Summary {
        var roots: [String] = []
        var seen = Set<String>()
        var files = 0
        for entry in entries {
            let components = components(of: entry.path)
            guard isJunk(components: components) else { continue }
            let root = components.firstIndex(where: folderNames.contains)
                .map { components[...$0].joined(separator: "/") } ?? components.joined(separator: "/")
            guard !root.contains(where: { "*?".contains($0) }) else { continue }
            if !entry.isDirectory { files += 1 }
            if seen.insert(root).inserted { roots.append(root) }
        }
        return Summary(roots: roots, fileCount: files)
    }
}
