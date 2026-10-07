import Foundation

/// Splits streamed text into complete lines, holding back a trailing partial
/// line until the rest of it arrives.
struct LineBuffer {
    private var pending = ""

    mutating func feed(_ chunk: String) -> [String] {
        pending += chunk
        var lines = pending.components(separatedBy: "\n")
        pending = lines.removeLast()
        return lines
    }

    /// The unterminated last line, if any (call once the stream has ended).
    mutating func flush() -> String? {
        defer { pending = "" }
        return pending.isEmpty ? nil : pending
    }
}
