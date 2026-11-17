import Foundation

public extension ProgressInfo {
    /// This snapshot if it is not behind `previous`, else nil.
    ///
    /// Updates reach the UI from background threads, each hopping to the main
    /// actor on its own, so they can arrive out of order — and a bar that
    /// jumps back to an older value looks like it is dancing. A caller applies
    /// only what this returns.
    func advancing(from previous: ProgressInfo?) -> ProgressInfo? {
        guard let previous else { return self }
        return fractionCompleted >= previous.fractionCompleted ? self : nil
    }

    /// The same snapshot with its fraction mapped into `lower ... upper`, for
    /// an operation made of several stages (copy: extract, then add) so that
    /// the whole runs one way from 0 to 1 instead of filling twice.
    func scaled(into lower: Double, _ upper: Double) -> ProgressInfo {
        var copy = self
        copy.fractionCompleted = lower + min(max(fractionCompleted, 0), 1) * (upper - lower)
        return copy
    }
}
