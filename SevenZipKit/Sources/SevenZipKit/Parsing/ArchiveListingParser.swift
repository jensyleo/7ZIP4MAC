import Foundation

/// Parses the technical listing produced by `7zz l -slt <archive>`.
///
/// The `-slt` ("show technical information") format is stable and
/// machine-friendly: an archive-properties block introduced by a `--` line,
/// followed by one `Key = Value` block per entry after a `----------` line.
/// Blocks are separated by blank lines.
public enum ArchiveListingParser {
    /// Parses raw `7zz -slt` standard output into archive properties and entries.
    ///
    /// - Parameter output: The full UTF-8 standard output of the listing command.
    /// - Returns: The parsed archive properties and its entries.
    /// - Throws: ``ArchiveError/parsingFailed(reason:)`` if the entries section
    ///   is absent (which indicates an unexpected or truncated output).
    public static func parse(_ output: String) throws -> (ArchiveProperties, [ArchiveEntry]) {
        let lines = output.components(separatedBy: .newlines)

        // The header block sits between the `--` separator and the first
        // `----------` separator; entries follow the latter.
        guard let entriesSeparatorIndex = lines.firstIndex(where: { isEntrySeparator($0) }) else {
            throw ArchiveError.parsingFailed(reason: "no entries section found in listing")
        }

        let headerLines = Array(lines[..<entriesSeparatorIndex])
        let entryLines = Array(lines[(entriesSeparatorIndex + 1)...])

        let properties = parseProperties(from: headerLines)
        let entries = parseEntries(from: entryLines)
        return (properties, entries)
    }

    // MARK: - Header

    private static func parseProperties(from lines: [String]) -> ArchiveProperties {
        // Take the block after the last `--` header separator, if present.
        var fields: [String: String] = [:]
        var seenHeaderSeparator = false
        for line in lines {
            if isHeaderSeparator(line) {
                seenHeaderSeparator = true
                fields.removeAll(keepingCapacity: true)
                continue
            }
            guard seenHeaderSeparator, let (key, value) = keyValue(from: line) else { continue }
            // Skip the archive's own `Path`; it is not a meaningful property here.
            if key == "Path" { continue }
            fields[key] = value
        }

        return ArchiveProperties(
            format: fields["Type"],
            physicalSize: fields["Physical Size"].flatMap { UInt64($0) },
            headersSize: fields["Headers Size"].flatMap { UInt64($0) },
            method: fields["Method"],
            isSolid: fields["Solid"].map { $0 == "+" },
            blocks: fields["Blocks"].flatMap { UInt64($0) }
        )
    }

    // MARK: - Entries

    private static func parseEntries(from lines: [String]) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        var current: [String: String] = [:]

        func flush() {
            guard let path = current["Path"], !path.isEmpty else {
                current.removeAll(keepingCapacity: true)
                return
            }
            entries.append(makeEntry(path: path, fields: current))
            current.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
                continue
            }
            // A stray separator inside the entries region ends the current block.
            if isEntrySeparator(line) || isHeaderSeparator(line) {
                flush()
                continue
            }
            if let (key, value) = keyValue(from: line) {
                current[key] = value
            }
        }
        flush()
        return entries
    }

    private static func makeEntry(path: String, fields: [String: String]) -> ArchiveEntry {
        let attributes = fields["Attributes"]
        let folderField = fields["Folder"]
        let isDirectory = (folderField == "+") || (attributes?.first == "D")

        return ArchiveEntry(
            path: path,
            isDirectory: isDirectory,
            size: fields["Size"].flatMap { UInt64($0) } ?? 0,
            packedSize: fields["Packed Size"].flatMap { UInt64($0) },
            modified: fields["Modified"].flatMap(parseDate),
            crc: fields["CRC"].flatMap { $0.isEmpty ? nil : $0 },
            isEncrypted: fields["Encrypted"] == "+",
            method: fields["Method"].flatMap { $0.isEmpty ? nil : $0 },
            attributes: attributes
        )
    }

    // MARK: - Primitives

    /// A `Key = Value` line, split on the first `" = "`.
    private static func keyValue(from line: String) -> (String, String)? {
        guard let range = line.range(of: " = ") else {
            // 7-Zip emits keys with empty values as `Key =` (trailing space
            // trimmed by some terminals); handle that form too.
            if line.hasSuffix(" =") {
                let key = String(line.dropLast(2))
                return (key, "")
            }
            return nil
        }
        let key = String(line[..<range.lowerBound])
        let value = String(line[range.upperBound...])
        return (key, value)
    }

    /// 7-Zip timestamps look like `2026-07-08 10:04:47.0167269`. We keep
    /// whole-second precision, which is all the UI needs.
    private static func parseDate(_ raw: String) -> Date? {
        let seconds = raw.split(separator: ".").first.map(String.init) ?? raw
        return Self.dateFormatter.date(from: seconds)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func isHeaderSeparator(_ line: String) -> Bool {
        line == "--"
    }

    private static func isEntrySeparator(_ line: String) -> Bool {
        line.count >= 10 && line.allSatisfy { $0 == "-" }
    }
}
