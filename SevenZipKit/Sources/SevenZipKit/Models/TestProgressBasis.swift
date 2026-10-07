import Foundation

/// What an integrity test needs to report real progress: the bytes it will
/// verify in total and each entry's size, so a finished file can be counted
/// as soon as the engine reports it.
public struct TestProgressBasis: Sendable, Equatable {
    public var totalBytes: UInt64
    public var entrySizes: [String: UInt64]

    public init(totalBytes: UInt64, entrySizes: [String: UInt64]) {
        self.totalBytes = totalBytes
        self.entrySizes = entrySizes
    }
}
