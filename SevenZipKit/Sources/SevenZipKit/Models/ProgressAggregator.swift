import Foundation

/// Combines the progress of several operations that run at the same time
/// (the items of one multi-item drag-out) into one steady figure.
///
/// Each item keeps its own byte counters, so one item's update can never
/// overwrite another's — which is what made a shared single bar jump between
/// items. The combined fraction never moves backwards: items register as they
/// start, so the grand total can grow mid-way, and a bar that dips would read
/// as a fault.
public struct ProgressAggregator: Sendable {
    private struct Item {
        /// Bytes of phases the item has already completed (e.g. extraction
        /// once it moves on to being moved into place).
        var carriedProcessed: UInt64 = 0
        var carriedTotal: UInt64 = 0
        var processed: UInt64 = 0
        var total: UInt64 = 0
        /// How many phases the item goes through. Later phases are assumed to
        /// weigh the same as the first, so the combined total counts them from
        /// the start and the bar doesn't hit 100% before the last one begins.
        var phases = 1
        var phaseIndex = 0
        var firstPhaseTotal: UInt64 = 0

        var contributionTotal: UInt64 {
            let remaining = max(0, phases - phaseIndex - 1)
            return carriedTotal + total + UInt64(remaining) * firstPhaseTotal
        }
    }

    private var items: [UUID: Item] = [:]
    private var highestFraction = 0.0

    public init() {}

    public mutating func register(_ id: UUID, phases: Int = 1) {
        var item = Item()
        item.phases = max(1, phases)
        items[id] = item
    }

    /// Records the current phase's counters for an item.
    public mutating func update(_ id: UUID, processed: UInt64, total: UInt64) {
        guard var item = items[id] else { return }
        item.processed = min(processed, total > 0 ? total : processed)
        item.total = total
        if item.phaseIndex == 0 { item.firstPhaseTotal = total }
        items[id] = item
    }

    /// Closes the item's current phase as fully done and starts a new one at 0.
    public mutating func startNextPhase(_ id: UUID) {
        guard var item = items[id] else { return }
        item.carriedProcessed += item.total
        item.carriedTotal += item.total
        item.phaseIndex += 1
        item.processed = 0
        // Until the new phase reports its own size, assume it matches the first.
        item.total = item.phaseIndex < item.phases ? item.firstPhaseTotal : 0
        items[id] = item
    }

    /// Marks the item as done so its share stays in the combined total.
    public mutating func finish(_ id: UUID) {
        guard var item = items[id] else { return }
        item.phaseIndex = item.phases - 1
        item.processed = item.total
        items[id] = item
    }

    public mutating func snapshot() -> (processed: UInt64, total: UInt64, fraction: Double) {
        var processed: UInt64 = 0
        var total: UInt64 = 0
        for item in items.values {
            processed += item.carriedProcessed + item.processed
            total += item.contributionTotal
        }
        let raw = total > 0 ? min(Double(processed) / Double(total), 1) : 0
        highestFraction = max(highestFraction, raw)
        return (processed, total, highestFraction)
    }
}
