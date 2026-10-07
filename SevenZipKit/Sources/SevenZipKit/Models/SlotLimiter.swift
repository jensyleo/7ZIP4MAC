import Foundation

/// Lets at most `limit` tasks hold a slot at once; the rest wait their turn in
/// arrival order. A task cancelled while waiting stops waiting right away,
/// throws `CancellationError`, and never holds a slot.
public actor SlotLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// Waits for a slot. Pair every successful call with ``release()``.
    public func acquire() async throws {
        if Task.isCancelled { throw CancellationError() }
        if running < limit {
            running += 1
            return
        }
        let id = UUID()
        let ownsSlot = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
        if !ownsSlot { throw CancellationError() }
    }

    public func release() {
        if waiters.isEmpty {
            running = max(0, running - 1)
        } else {
            // Hand the slot straight to the next waiter; the count stays.
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }
}
