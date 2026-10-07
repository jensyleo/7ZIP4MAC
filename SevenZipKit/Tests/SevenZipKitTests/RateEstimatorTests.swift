import XCTest
@testable import SevenZipKit

final class RateEstimatorTests: XCTestCase {
    func testFollowsRecentSpeedAfterAFastPhaseSlowsDown() {
        var estimator = RateEstimator(window: 20, now: 0)
        // 10 s at 10 MB/s ...
        var processed: UInt64 = 0
        for second in 1...10 {
            processed += 10_000_000
            _ = estimator.rate(processed: processed, now: TimeInterval(second))
        }
        // ... then 30 s at 1 MB/s: a whole-run average would still say ~3.5 MB/s.
        var rate = 0.0
        for second in 11...40 {
            processed += 1_000_000
            rate = estimator.rate(processed: processed, now: TimeInterval(second))
        }
        XCTAssertEqual(rate, 1_000_000, accuracy: 100_000)
        let wholeRunAverage = Double(processed) / 40
        XCTAssertGreaterThan(wholeRunAverage, 3_000_000, "sanity: the old estimate would have been far too optimistic")
    }

    func testRemainingTimeGrowsHonestlyWhenSpeedDrops() {
        var estimator = RateEstimator(window: 20, now: 0)
        _ = estimator.rate(processed: 0, now: 0)
        let fast = estimator.rate(processed: 50_000_000, now: 5)          // 10 MB/s
        let etaFast = RateEstimator.remaining(total: 100_000_000, processed: 50_000_000, rate: fast)
        var processed: UInt64 = 50_000_000
        var rate = 0.0
        for second in 6...30 { processed += 500_000; rate = estimator.rate(processed: processed, now: TimeInterval(second)) }
        let etaSlow = RateEstimator.remaining(total: 100_000_000, processed: processed, rate: rate)
        XCTAssertNotNil(etaFast)
        XCTAssertGreaterThan(etaSlow ?? 0, (etaFast ?? 0) * 10)
    }

    func testRestartMeasuresANewPhaseOnItsOwn() {
        var estimator = RateEstimator(window: 20, now: 0)
        _ = estimator.rate(processed: 100_000_000, now: 10)                // fast first phase
        estimator.restart(processed: 100_000_000, now: 10)
        let rate = estimator.rate(processed: 101_000_000, now: 11)
        XCTAssertEqual(rate, 1_000_000, accuracy: 1, "average since the restart, not since the start")
    }

    func testNothingToMeasureYieldsNoEstimate() {
        var estimator = RateEstimator(window: 20, now: 0)
        XCTAssertEqual(estimator.rate(processed: 0, now: 0), 0)
        XCTAssertNil(RateEstimator.remaining(total: 100, processed: 0, rate: 0))
        XCTAssertNil(RateEstimator.remaining(total: 100, processed: 100, rate: 5))
    }
}
