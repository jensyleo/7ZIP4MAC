import Foundation

extension FileManager {
    /// Creates (and returns) a fresh, uniquely-named directory under the
    /// system temporary directory, for scratch use during one operation
    /// (staging files to add/copy, unwrapping a single-stream archive,
    /// building an App Intent's output) — the caller owns cleaning it up
    /// afterward (typically via `defer { try? FileManager.default.removeItem(at:) }`).
    ///
    /// - Parameter tag: A short label identifying the caller, folded into the
    ///   directory name (e.g. "Add", "Copy", "Unwrap") purely to make a stray
    ///   leftover recognizable in Finder/Console — never parsed back.
    public func makeScratchDirectory(tag: String) throws -> URL {
        let url = temporaryDirectory
            .appendingPathComponent("7ZIP4MAC-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
