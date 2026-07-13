import Foundation

/// One progress update parsed from the engine's live output.
public struct ProgressLine: Sendable, Equatable {
    /// Percentage reported by the engine, `0 ... 100`.
    public let percent: Int
    /// The file the engine is currently working on, when present.
    public let currentFile: String?
}

/// Incrementally parses the live progress output of `7zz`.
///
/// The engine redraws its progress in place using backspace (`\u{08}`) and
/// carriage-return (`\r`) characters, emitting tokens such as:
///
///     " 42% 7 - folder/file.bin"
///
/// This parser is fed arbitrary chunks (which may split a token across chunk
/// boundaries) and yields a ``ProgressLine`` for every complete progress token
/// it recognises.
public struct ProgressParser: Sendable {
    private var buffer = ""

    public init() {}

    /// Feeds a chunk of engine output and returns any progress updates it completed.
    public mutating func consume(_ text: String) -> [ProgressLine] {
        buffer += text
        // Treat the in-place redraw characters as line separators so each
        // redraw becomes its own candidate line.
        let normalized = buffer
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{08}", with: "\n")
        var segments = normalized.components(separatedBy: "\n")
        // The last segment may be an incomplete token; keep it for next time.
        buffer = segments.removeLast()

        return segments.compactMap(Self.parse)
    }

    /// Parses whatever remains buffered once the stream ends.
    public mutating func finish() -> ProgressLine? {
        defer { buffer = "" }
        return Self.parse(buffer)
    }

    /// Parses a single candidate line into a ``ProgressLine``, if it is one.
    static func parse(_ line: String) -> ProgressLine? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let percentIndex = trimmed.firstIndex(of: "%") else { return nil }

        // The characters immediately before "%" must be digits.
        let digits = trimmed[..<percentIndex]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let percent = Int(digits) else {
            return nil
        }

        // Remainder after "%": optionally " <count> <op> <path>", where <op>
        // is "-" while extracting/testing and "+" while adding (compressing).
        let remainder = String(trimmed[trimmed.index(after: percentIndex)...])
            .trimmingCharacters(in: .whitespaces)

        var currentFile: String?
        for separator in [" - ", " + "] {
            if let range = remainder.range(of: separator) {
                let path = remainder[range.upperBound...].trimmingCharacters(in: .whitespaces)
                currentFile = path.isEmpty ? nil : path
                break
            }
        }

        return ProgressLine(percent: min(max(percent, 0), 100), currentFile: currentFile)
    }
}
