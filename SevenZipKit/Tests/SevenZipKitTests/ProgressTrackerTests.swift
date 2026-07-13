import Foundation
import Testing
@testable import SevenZipKit

@Suite("ProgressTracker")
struct ProgressTrackerTests {

    @Test("computes fraction and processed bytes from percent")
    func computesProcessedBytes() {
        var tracker = ProgressTracker(totalBytes: 1000)
        let info = tracker.update(percent: 25, now: 0, currentFile: nil)
        #expect(info.fractionCompleted == 0.25)
        #expect(info.processedBytes == 250)
        #expect(info.totalBytes == 1000)
    }

    @Test("estimates throughput and ETA across samples")
    func estimatesThroughputAndETA() {
        var tracker = ProgressTracker(totalBytes: 1000)
        _ = tracker.update(percent: 0, now: 0, currentFile: nil)
        // At t=1s, 50% => 500 bytes in 1s => 500 B/s.
        let mid = tracker.update(percent: 50, now: 1, currentFile: nil)
        #expect(mid.bytesPerSecond > 0)
        // Remaining 500 bytes at ~500 B/s => ~1s ETA (order of magnitude).
        let eta = try? #require(mid.estimatedTimeRemaining)
        #expect((eta ?? 0) > 0)
    }

    @Test("reports nil ETA at completion")
    func nilETAAtCompletion() {
        var tracker = ProgressTracker(totalBytes: 1000)
        _ = tracker.update(percent: 0, now: 0, currentFile: nil)
        let done = tracker.update(percent: 100, now: 2, currentFile: nil)
        #expect(done.fractionCompleted == 1.0)
        #expect(done.estimatedTimeRemaining == nil)
    }

    @Test("passes through the current file name")
    func passesCurrentFile() {
        var tracker = ProgressTracker(totalBytes: 0)
        let info = tracker.update(percent: 10, now: 0, currentFile: "x/y.bin")
        #expect(info.currentFile == "x/y.bin")
        // With unknown total, byte-based estimates stay zero.
        #expect(info.processedBytes == 0)
    }
}
