import Foundation

/// Parses the output of `7zz b` into a ``BenchmarkResult``.
public enum BenchmarkParser {

    public static func parse(_ output: String) -> BenchmarkResult {
        var result = BenchmarkResult()
        let lines = output.components(separatedBy: .newlines)

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("PageSize:") {
                // The CPU model is printed on the next non-empty line.
                if let model = lines[(index + 1)...].map({ $0.trimmingCharacters(in: .whitespaces) })
                    .first(where: { !$0.isEmpty }) {
                    result.cpuModel = model
                }
                continue
            }
            if line.hasPrefix("RAM size:") {
                result.ramSizeMB = firstInt(in: line)
                continue
            }
            if line.hasPrefix("RAM usage:") || line.contains("# Benchmark threads:") {
                if let threads = allInts(in: line).last { result.benchmarkThreads = threads }
                continue
            }
            if line.hasPrefix("Avr:") {
                let (left, right) = split(line.dropFirst("Avr:".count))
                if left.count >= 4 {
                    result.compressSpeedKiBs = left[0]
                    result.compressRatingMIPS = left[3]
                }
                if right.count >= 4 {
                    result.decompressSpeedKiBs = right[0]
                    result.decompressRatingMIPS = right[3]
                }
                continue
            }
            if line.hasPrefix("Tot:") {
                // "Tot:  <usage>  <R/U>  <rating>" — rating is the last number.
                result.totalRatingMIPS = allInts(in: line).last
                continue
            }
            // Dictionary rows look like "22:  <c...> | <d...>".
            if let colon = line.firstIndex(of: ":"),
               let dict = Int(line[..<colon]),
               line.contains("|") {
                let (left, right) = split(line[line.index(after: colon)...])
                if left.count >= 4, right.count >= 4 {
                    result.rows.append(BenchmarkRow(
                        dictionary: dict,
                        compressSpeedKiBs: left[0],
                        compressRatingMIPS: left[3],
                        decompressSpeedKiBs: right[0],
                        decompressRatingMIPS: right[3]
                    ))
                }
            }
        }
        return result
    }

    // MARK: - Helpers

    /// Splits a "left | right" segment into two integer token arrays.
    private static func split(_ segment: Substring) -> ([Int], [Int]) {
        let sides = segment.components(separatedBy: "|")
        let left = sides.first.map(ints(in:)) ?? []
        let right = sides.count > 1 ? ints(in: sides[1]) : []
        return (left, right)
    }

    private static func ints(in string: String) -> [Int] {
        string.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    private static func allInts(in string: String) -> [Int] {
        ints(in: string)
    }

    private static func firstInt(in string: String) -> Int? {
        ints(in: string).first
    }
}
