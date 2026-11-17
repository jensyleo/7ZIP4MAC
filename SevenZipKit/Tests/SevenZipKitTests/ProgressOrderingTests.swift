import Foundation
import Testing
@testable import SevenZipKit

@Suite("Progress ordering")
struct ProgressOrderingTests {
    private func info(_ fraction: Double) -> ProgressInfo {
        ProgressInfo(fractionCompleted: fraction, processedBytes: 0, totalBytes: 0, bytesPerSecond: 0, estimatedTimeRemaining: nil, currentFile: nil)
    }

    @Test("a snapshot behind the current one is dropped, one level or ahead is kept")
    func advancing() {
        #expect(info(0.4).advancing(from: nil) != nil)
        #expect(info(0.4).advancing(from: info(0.5)) == nil)
        #expect(info(0.5).advancing(from: info(0.5)) != nil)
        #expect(info(0.6).advancing(from: info(0.5))?.fractionCompleted == 0.6)
    }

    @Test("stages map into their share of the bar")
    func scaling() {
        #expect(info(0).scaled(into: 0, 0.5).fractionCompleted == 0)
        #expect(info(1).scaled(into: 0, 0.5).fractionCompleted == 0.5)
        #expect(info(0).scaled(into: 0.5, 1).fractionCompleted == 0.5)
        #expect(info(0.5).scaled(into: 0.5, 1).fractionCompleted == 0.75)
        #expect(info(1.7).scaled(into: 0.5, 1).fractionCompleted == 1)
    }

    @Test("the tracker never reports a lower fraction than before")
    func trackerIsMonotonic() {
        var tracker = ProgressTracker(totalBytes: 1_000_000)
        var last = 0.0
        for (i, percent) in [10, 40, 35, 60, 20, 100, 90].enumerated() {
            let value = tracker.update(percent: percent, now: Double(i), currentFile: nil).fractionCompleted
            #expect(value >= last)
            last = value
        }
        #expect(last == 1.0)
    }
}

@Suite("Aggregator with known sizes")
struct AggregatorExpectedTotalTests {
    @Test("registered up front, the total is steady and the bar tracks finished items")
    func steadyTotal() {
        var aggregator = ProgressAggregator()
        let ids = (0..<10).map { _ in UUID() }
        for id in ids { aggregator.register(id, phases: 2, expectedTotal: 1_000) }
        #expect(aggregator.snapshot().total == 20_000)
        #expect(aggregator.snapshot().fraction == 0)

        var seen: [Double] = []
        for (index, id) in ids.enumerated() {
            aggregator.update(id, processed: 500, total: 1_000)
            seen.append(aggregator.snapshot().fraction)
            aggregator.update(id, processed: 1_000, total: 1_000)
            aggregator.startNextPhase(id)
            aggregator.update(id, processed: 1_000, total: 1_000)
            aggregator.finish(id)
            let fraction = aggregator.snapshot().fraction
            seen.append(fraction)
            #expect(abs(fraction - Double(index + 1) / 10) < 0.0001, "after \(index + 1) of 10 the bar is at \(Double(index + 1) / 10)")
        }
        #expect(seen == seen.sorted())
        #expect(aggregator.snapshot().fraction == 1)
    }
}
