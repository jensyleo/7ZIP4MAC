import XCTest
@testable import SevenZipKit

private actor Tally {
    private(set) var current = 0
    private(set) var peak = 0
    private(set) var order: [Int] = []
    func enter(_ index: Int) { current += 1; peak = max(peak, current); order.append(index) }
    func leave() { current -= 1 }
}

final class SlotLimiterTests: XCTestCase {
    func testNeverExceedsTheLimitAndRunsEveryTask() async throws {
        let limiter = SlotLimiter(limit: 2)
        let tally = Tally()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<10 {
                group.addTask {
                    try await limiter.acquire()
                    await tally.enter(index)
                    try await Task.sleep(nanoseconds: 20_000_000)
                    await tally.leave()
                    await limiter.release()
                }
            }
            try await group.waitForAll()
        }
        let peak = await tally.peak
        let count = await tally.order.count
        XCTAssertEqual(peak, 2)
        XCTAssertEqual(count, 10)
    }

    func testCancelledWaiterStopsWaitingWithoutTakingASlot() async throws {
        let limiter = SlotLimiter(limit: 1)
        try await limiter.acquire()                    // slot is now held

        let waiter = Task { () -> Bool in
            do { try await limiter.acquire(); return true } catch { return false }
        }
        try await Task.sleep(nanoseconds: 50_000_000)  // let it queue up
        waiter.cancel()
        let acquired = await waiter.value
        XCTAssertFalse(acquired, "a cancelled waiter must throw, not acquire")

        // The held slot is released: the next caller must get it immediately,
        // proving the cancelled waiter left nothing behind.
        await limiter.release()
        let next = Task { () -> Bool in
            do { try await limiter.acquire(); return true } catch { return false }
        }
        let got = await next.value
        XCTAssertTrue(got)
        await limiter.release()
    }

    func testAlreadyCancelledTaskThrowsImmediately() async {
        let limiter = SlotLimiter(limit: 1)
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { try await limiter.acquire(); return true } catch { return false }
        }
        let acquired = await task.value
        XCTAssertFalse(acquired)
    }
}
