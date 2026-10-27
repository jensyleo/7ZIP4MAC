import Foundation

/// Turns the progress 7-Zip prints while it rewrites an archive without some
/// entries (`7zz d -bsp1`) into a single steady ``ProgressInfo``.
///
/// 7-Zip works in two stretches, both reported as percentages:
///
///     "  42%"                                              building the new archive
///     "100%  : 37% : 40 MiB / 107 MiB : temporary archive moving ..."   putting it in place
///
/// Each counts for half of a batch, and a delete that runs in several batches
/// (each one rewrites the archive) spreads the whole bar over all of them. The
/// fraction never goes backwards.
final class DeleteProgressState: @unchecked Sendable {
    private let lock = NSLock()
    private var tracker: ProgressTracker
    private let batches: Int
    private let report: @Sendable (ProgressInfo) -> Void
    private var batch = 0
    private var rewrite = 0
    private var move = 0
    private var highest = 0.0
    private var buffer = ""

    /// - Parameters:
    ///   - archiveSize: Size of the archive in bytes, used for throughput and ETA.
    ///   - batches: How many `d` runs the delete is split into.
    init(archiveSize: UInt64, batches: Int, report: @escaping @Sendable (ProgressInfo) -> Void) {
        self.batches = max(1, batches)
        self.tracker = ProgressTracker(totalBytes: archiveSize * UInt64(max(1, batches)))
        self.report = report
    }

    /// Begins batch `index` (0-based); the previous one is counted as complete.
    func startBatch(_ index: Int) {
        lock.lock()
        batch = index
        rewrite = 0
        move = 0
        lock.unlock()
        emit(currentFile: nil)
    }

    func consume(_ chunk: String) {
        lock.lock()
        buffer += chunk
        var segments = buffer
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{08}", with: "\n")
            .components(separatedBy: "\n")
        buffer = segments.removeLast()
        lock.unlock()

        var changed = false
        var file: String?
        for segment in segments {
            guard let parsed = Self.parse(segment) else { continue }
            lock.lock()
            if let value = parsed.rewrite { rewrite = max(rewrite, value) }
            if let value = parsed.move { move = max(move, value) }
            lock.unlock()
            file = parsed.file ?? file
            changed = true
        }
        if changed { emit(currentFile: file) }
    }

    /// Marks the batch as fully done.
    func finishBatch() {
        lock.lock()
        rewrite = 100
        move = 100
        lock.unlock()
        emit(currentFile: nil)
    }

    private func emit(currentFile: String?) {
        lock.lock()
        let inBatch = (Double(rewrite) + Double(move)) / 200
        let overall = min(1, (Double(batch) + inBatch) / Double(batches))
        highest = max(highest, overall)
        let info = tracker.update(
            percent: Int((highest * 100).rounded(.down)),
            now: Date().timeIntervalSinceReferenceDate,
            currentFile: currentFile
        )
        lock.unlock()
        report(info)
    }

    struct Line: Equatable {
        var rewrite: Int?
        var move: Int?
        var file: String?
    }

    /// One redrawn progress line, or nil when it is not one.
    static func parse(_ segment: String) -> Line? {
        let text = segment.trimmingCharacters(in: .whitespaces)
        guard text.contains("%") else { return nil }
        let percents = text.matches(of: /(\d{1,3})%/).compactMap { Int($0.output.1) }
        guard let first = percents.first else { return nil }
        if text.contains("moving") {
            // "100%  : 37% : 40 MiB / 107 MiB : temporary archive moving ... name"
            let name = text.range(of: "moving ...").map { String(text[$0.upperBound...]).trimmingCharacters(in: .whitespaces) }
            return Line(rewrite: 100, move: percents.count > 1 ? min(percents[1], 100) : nil, file: name?.isEmpty == false ? name : nil)
        }
        return Line(rewrite: min(first, 100), move: nil, file: nil)
    }
}
