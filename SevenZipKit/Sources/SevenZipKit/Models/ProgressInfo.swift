import Foundation

/// A snapshot of a running operation's progress.
///
/// Reported repeatedly during extraction/compression so the UI can show a
/// percentage, throughput, ETA and the file currently being processed.
public struct ProgressInfo: Sendable, Equatable {
    /// Fraction complete, `0.0 ... 1.0`.
    public var fractionCompleted: Double

    /// Estimated bytes processed so far.
    public var processedBytes: UInt64

    /// Total bytes to process, when known (0 if unknown).
    public var totalBytes: UInt64

    /// Smoothed throughput in bytes per second (0 until enough samples exist).
    public var bytesPerSecond: Double

    /// Estimated time remaining, or nil when it cannot be computed yet.
    public var estimatedTimeRemaining: TimeInterval?

    /// The file currently being processed, when the engine reports it.
    public var currentFile: String?

    public init(
        fractionCompleted: Double,
        processedBytes: UInt64,
        totalBytes: UInt64,
        bytesPerSecond: Double,
        estimatedTimeRemaining: TimeInterval?,
        currentFile: String?
    ) {
        self.fractionCompleted = fractionCompleted
        self.processedBytes = processedBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.currentFile = currentFile
    }

    /// Bytes still to be processed.
    public var remainingBytes: UInt64 {
        totalBytes > processedBytes ? totalBytes - processedBytes : 0
    }

    public static let zero = ProgressInfo(
        fractionCompleted: 0, processedBytes: 0, totalBytes: 0,
        bytesPerSecond: 0, estimatedTimeRemaining: nil, currentFile: nil
    )
}
