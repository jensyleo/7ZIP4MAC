import Foundation

/// Turns raw percentage updates into a rich ``ProgressInfo`` with smoothed
/// throughput and an ETA.
///
/// Time is passed in explicitly (`now:`) rather than read from the clock, so
/// the tracker is fully deterministic in unit tests.
public struct ProgressTracker: Sendable {
    private let totalBytes: UInt64

    /// Exponential-moving-average smoothing factor for throughput.
    private let smoothing: Double

    private var startTime: TimeInterval?
    private var lastTime: TimeInterval?
    private var lastProcessedBytes: UInt64 = 0
    private var smoothedBytesPerSecond: Double = 0

    public init(totalBytes: UInt64, smoothing: Double = 0.3) {
        self.totalBytes = totalBytes
        self.smoothing = smoothing
    }

    /// Records a new percentage and returns the corresponding progress snapshot.
    ///
    /// - Parameters:
    ///   - percent: Latest percentage from the engine, `0 ... 100`.
    ///   - now: Current time as an absolute interval (e.g. `Date().timeIntervalSinceReferenceDate`).
    ///   - currentFile: File the engine is processing, if known.
    public mutating func update(percent: Int, now: TimeInterval, currentFile: String?) -> ProgressInfo {
        let fraction = min(max(Double(percent) / 100.0, 0), 1)
        let processed = totalBytes > 0 ? UInt64(fraction * Double(totalBytes)) : 0

        if startTime == nil {
            startTime = now
            lastTime = now
            lastProcessedBytes = processed
        }

        if let last = lastTime, now > last, processed >= lastProcessedBytes {
            let deltaBytes = Double(processed - lastProcessedBytes)
            let deltaTime = now - last
            if deltaTime > 0 {
                let instantaneous = deltaBytes / deltaTime
                smoothedBytesPerSecond = smoothedBytesPerSecond == 0
                    ? instantaneous
                    : smoothing * instantaneous + (1 - smoothing) * smoothedBytesPerSecond
            }
            lastTime = now
            lastProcessedBytes = processed
        }

        let eta: TimeInterval?
        if totalBytes > 0, smoothedBytesPerSecond > 0, fraction < 1 {
            eta = Double(totalBytes - processed) / smoothedBytesPerSecond
        } else {
            eta = nil
        }

        return ProgressInfo(
            fractionCompleted: fraction,
            processedBytes: processed,
            totalBytes: totalBytes,
            bytesPerSecond: smoothedBytesPerSecond,
            estimatedTimeRemaining: eta,
            currentFile: currentFile
        )
    }
}
