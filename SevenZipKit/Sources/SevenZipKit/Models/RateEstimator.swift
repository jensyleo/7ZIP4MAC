import Foundation

/// Transfer speed measured over the last few seconds instead of since the
/// start. A whole-run average stays optimistic after a fast phase gives way to
/// a slow one (extracting locally, then moving over the network), so the time
/// remaining barely moved for minutes; a recent window follows the real speed.
public struct RateEstimator: Sendable {
    private var samples: [(time: TimeInterval, bytes: UInt64)] = []
    private var startTime: TimeInterval
    private var startBytes: UInt64
    private let window: TimeInterval

    public init(window: TimeInterval = 20, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.window = window
        self.startTime = now
        self.startBytes = 0
    }

    /// Forgets the history so a new phase is measured on its own.
    public mutating func restart(processed: UInt64, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        samples.removeAll()
        startTime = now
        startBytes = processed
    }

    /// Records the byte count and returns the current speed in bytes/second
    /// (0 until there is something to measure).
    public mutating func rate(processed: UInt64, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
        samples.append((now, processed))
        samples.removeAll { now - $0.time > window }
        if let first = samples.first, now - first.time >= 2, processed >= first.bytes {
            return Double(processed - first.bytes) / (now - first.time)
        }
        let elapsed = now - startTime
        guard elapsed > 0, processed >= startBytes else { return 0 }
        return Double(processed - startBytes) / elapsed
    }

    /// Seconds left at `rate`, or nil when it can't be told.
    public static func remaining(total: UInt64, processed: UInt64, rate: Double) -> TimeInterval? {
        guard rate > 0, total > processed else { return nil }
        return Double(total - processed) / rate
    }
}
