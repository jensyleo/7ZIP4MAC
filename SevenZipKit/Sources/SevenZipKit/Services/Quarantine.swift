import Foundation
import Darwin

/// macOS's "downloaded from the internet" marker (`com.apple.quarantine`).
///
/// The system's own unarchiver copies it from an archive to everything it
/// extracts, which is what makes Gatekeeper check a downloaded app before it
/// first runs. 7-Zip doesn't (verified: files extracted with `7zz` come out
/// unmarked), so an app unpacked from a downloaded archive would silently skip
/// that check. `unar` already copies it, so only the 7-Zip paths use this.
public enum Quarantine {
    static let attribute = "com.apple.quarantine"

    /// The marker on `url` itself, or nil when it has none.
    public static func value(of url: URL) -> Data? {
        let size = getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes {
            getxattr(url.path, attribute, $0.baseAddress, size, 0, XATTR_NOFOLLOW)
        }
        return read == size ? data : nil
    }

    /// Marks `root` and everything below it (symlinks are marked themselves,
    /// never followed). With `cutoff`, only items created at or after it are
    /// touched, so files that were already in a destination folder are left alone.
    public static func apply(_ value: Data, to root: URL, onlyCreatedSince cutoff: Date? = nil) {
        func mark(_ url: URL) {
            if let cutoff,
               let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
               created < cutoff { return }
            _ = value.withUnsafeBytes {
                setxattr(url.path, attribute, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW)
            }
        }
        mark(root)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        for case let url as URL in enumerator { mark(url) }
    }

    /// Carries an archive's marker onto what an extraction just produced.
    static func propagate(
        _ value: Data, for request: ExtractionRequest, destinationExisted: Bool, startedAt: Date
    ) {
        let destination = request.destinationURL
        let cutoff = destinationExisted ? startedAt.addingTimeInterval(-2) : nil
        guard !request.selectedPaths.isEmpty else {
            apply(value, to: destination, onlyCreatedSince: cutoff)
            return
        }
        for path in request.selectedPaths {
            let components = path.split(separator: "/").map(String.init).filter { $0 != "." && $0 != ".." && !$0.isEmpty }
            guard let leaf = components.last else { continue }
            let target = request.flattenPaths
                ? destination.appendingPathComponent(leaf)
                : components.reduce(destination) { $0.appendingPathComponent($1) }
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
            // A selected file is certainly one of the extracted items; a folder
            // may have merged into an existing one, so it keeps the cutoff.
            apply(value, to: target, onlyCreatedSince: isDirectory.boolValue ? cutoff : nil)
        }
    }
}
