import XCTest
@testable import SevenZipKit

final class ProgressAggregatorTests: XCTestCase {
    func testItemsDoNotOverwriteEachOther() {
        var aggregator = ProgressAggregator()
        let (a, b) = (UUID(), UUID())
        aggregator.register(a)
        aggregator.register(b)
        aggregator.update(a, processed: 100, total: 100)
        aggregator.update(b, processed: 50, total: 300)
        let snapshot = aggregator.snapshot()
        XCTAssertEqual(snapshot.processed, 150)
        XCTAssertEqual(snapshot.total, 400)
        XCTAssertEqual(snapshot.fraction, 0.375, accuracy: 0.0001)
    }

    func testFractionNeverMovesBackwardsWhenALargerItemJoins() {
        var aggregator = ProgressAggregator()
        let (small, large) = (UUID(), UUID())
        aggregator.register(small)
        aggregator.update(small, processed: 90, total: 100)
        XCTAssertEqual(aggregator.snapshot().fraction, 0.9, accuracy: 0.0001)

        aggregator.register(large)
        aggregator.update(large, processed: 0, total: 10_000)
        XCTAssertEqual(aggregator.snapshot().fraction, 0.9, accuracy: 0.0001, "must hold, not drop to ~0.009")

        aggregator.update(large, processed: 10_000, total: 10_000)
        aggregator.update(small, processed: 100, total: 100)
        XCTAssertEqual(aggregator.snapshot().fraction, 1, accuracy: 0.0001)
    }

    func testNextPhaseKeepsCompletedBytes() {
        var aggregator = ProgressAggregator()
        let id = UUID()
        aggregator.register(id)
        aggregator.update(id, processed: 500, total: 500)
        aggregator.startNextPhase(id)
        var snapshot = aggregator.snapshot()
        XCTAssertEqual(snapshot.processed, 500)
        XCTAssertEqual(snapshot.total, 500)

        aggregator.update(id, processed: 1, total: 1)
        snapshot = aggregator.snapshot()
        XCTAssertEqual(snapshot.processed, 501)
        XCTAssertEqual(snapshot.total, 501)
    }

    func testFinishedItemKeepsItsShare() {
        var aggregator = ProgressAggregator()
        let (a, b) = (UUID(), UUID())
        aggregator.register(a)
        aggregator.register(b)
        aggregator.update(a, processed: 40, total: 100)
        aggregator.finish(a)
        aggregator.update(b, processed: 0, total: 100)
        XCTAssertEqual(aggregator.snapshot().processed, 100)
        XCTAssertEqual(aggregator.snapshot().total, 200)
    }

    func testUnknownTotalsAreIgnoredAndUnregisteredIDsDoNothing() {
        var aggregator = ProgressAggregator()
        let id = UUID()
        aggregator.update(UUID(), processed: 5, total: 10)
        aggregator.register(id)
        let snapshot = aggregator.snapshot()
        XCTAssertEqual(snapshot.total, 0)
        XCTAssertEqual(snapshot.fraction, 0)
    }

    func testTwoPhaseItemDoesNotReachOneHundredPercentBeforeTheSecondPhase() {
        var aggregator = ProgressAggregator()
        let id = UUID()
        aggregator.register(id, phases: 2)
        aggregator.update(id, processed: 100, total: 100)
        var snapshot = aggregator.snapshot()
        XCTAssertEqual(snapshot.total, 200, "the move phase is counted from the start")
        XCTAssertEqual(snapshot.fraction, 0.5, accuracy: 0.0001)

        aggregator.startNextPhase(id)
        snapshot = aggregator.snapshot()
        XCTAssertEqual(snapshot.fraction, 0.5, accuracy: 0.0001, "starting the move must not jump to 100%")

        aggregator.update(id, processed: 50, total: 100)
        XCTAssertEqual(aggregator.snapshot().fraction, 0.75, accuracy: 0.0001)
        aggregator.update(id, processed: 100, total: 100)
        XCTAssertEqual(aggregator.snapshot().fraction, 1, accuracy: 0.0001)
    }

    func testInstantSecondPhaseJumpsToDone() {
        var aggregator = ProgressAggregator()
        let id = UUID()
        aggregator.register(id, phases: 2)
        aggregator.update(id, processed: 100, total: 100)
        aggregator.startNextPhase(id)
        aggregator.update(id, processed: 1, total: 1)   // a same-volume rename reports (1, 1)
        XCTAssertEqual(aggregator.snapshot().fraction, 1, accuracy: 0.0001)
    }

    func testFinishingEarlyClosesAllPhases() {
        var aggregator = ProgressAggregator()
        let id = UUID()
        aggregator.register(id, phases: 2)
        aggregator.update(id, processed: 40, total: 100)
        aggregator.finish(id)
        let snapshot = aggregator.snapshot()
        XCTAssertEqual(snapshot.processed, snapshot.total, "a failed item must not leave the bar short forever")
    }
}
