import Foundation

/// Ties the ``ProgressParser`` and ``ProgressTracker`` together while an engine
/// operation streams output.
///
/// The streaming runner calls `consume` from a single background thread, but
/// the mutable parser/tracker state is guarded by a lock so the type is safely
/// `Sendable`.
final class ProgressReportingState: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = ProgressParser()
    private var tracker: ProgressTracker
    private let report: @Sendable (ProgressInfo) -> Void

    init(totalBytes: UInt64, report: @escaping @Sendable (ProgressInfo) -> Void) {
        self.tracker = ProgressTracker(totalBytes: totalBytes)
        self.report = report
    }

    /// Parses a chunk of engine output and reports any resulting progress.
    func consume(_ chunk: String) {
        let lines: [ProgressLine]
        lock.lock()
        lines = parser.consume(chunk)
        lock.unlock()

        for line in lines {
            emit(percent: line.percent, currentFile: line.currentFile)
        }
    }

    /// Flushes any trailing buffered progress once the stream ends.
    func finish() {
        let last: ProgressLine?
        lock.lock()
        last = parser.finish()
        lock.unlock()
        if let last {
            emit(percent: last.percent, currentFile: last.currentFile)
        }
    }

    private func emit(percent: Int, currentFile: String?) {
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock()
        let info = tracker.update(percent: percent, now: now, currentFile: currentFile)
        lock.unlock()
        report(info)
    }
}
