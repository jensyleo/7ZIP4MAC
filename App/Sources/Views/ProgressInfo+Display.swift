import Foundation
import SevenZipKit

/// Presentation-only formatting for ``ProgressInfo``.
extension ProgressInfo {
    /// Whole-percentage string, e.g. "42%".
    var displayPercent: String {
        "\(Int((fractionCompleted * 100).rounded()))%"
    }

    /// Throughput, e.g. "12.4 MB/s", or "—" when not yet known.
    var displaySpeed: String {
        guard bytesPerSecond > 0 else { return "—" }
        return ByteFormatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    /// Estimated time remaining, e.g. "about 2 min", or "—".
    var displayETA: String {
        guard let eta = estimatedTimeRemaining, eta.isFinite, eta > 0 else { return "—" }
        return RelativeTimeFormatterCache.duration.string(from: eta) ?? "—"
    }

    /// "12 MB of 340 MB", using known totals.
    var displayBytes: String {
        guard totalBytes > 0 else { return "—" }
        let processed = ByteFormatter.string(fromByteCount: Int64(processedBytes))
        let total = ByteFormatter.string(fromByteCount: Int64(totalBytes))
        return "\(processed) of \(total)"
    }
}

enum RelativeTimeFormatterCache {
    static let duration: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f
    }()
}
