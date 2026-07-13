import Foundation

/// One dictionary-size row of a 7-Zip benchmark.
public struct BenchmarkRow: Identifiable, Hashable, Sendable {
    /// The dictionary size exponent (e.g. 22 == 4 MiB).
    public let dictionary: Int
    public let compressSpeedKiBs: Int
    public let compressRatingMIPS: Int
    public let decompressSpeedKiBs: Int
    public let decompressRatingMIPS: Int

    public var id: Int { dictionary }

    public init(
        dictionary: Int,
        compressSpeedKiBs: Int,
        compressRatingMIPS: Int,
        decompressSpeedKiBs: Int,
        decompressRatingMIPS: Int
    ) {
        self.dictionary = dictionary
        self.compressSpeedKiBs = compressSpeedKiBs
        self.compressRatingMIPS = compressRatingMIPS
        self.decompressSpeedKiBs = decompressSpeedKiBs
        self.decompressRatingMIPS = decompressRatingMIPS
    }
}

/// The parsed outcome of a `7zz b` benchmark run.
public struct BenchmarkResult: Hashable, Sendable {
    public var cpuModel: String?
    public var ramSizeMB: Int?
    public var benchmarkThreads: Int?

    /// Average compression speed / rating (the `Avr:` line, left side).
    public var compressSpeedKiBs: Int?
    public var compressRatingMIPS: Int?

    /// Average decompression speed / rating (the `Avr:` line, right side).
    public var decompressSpeedKiBs: Int?
    public var decompressRatingMIPS: Int?

    /// Overall rating (the `Tot:` line) — the headline MIPS number.
    public var totalRatingMIPS: Int?

    /// Per-dictionary-size rows.
    public var rows: [BenchmarkRow]

    public init(
        cpuModel: String? = nil,
        ramSizeMB: Int? = nil,
        benchmarkThreads: Int? = nil,
        compressSpeedKiBs: Int? = nil,
        compressRatingMIPS: Int? = nil,
        decompressSpeedKiBs: Int? = nil,
        decompressRatingMIPS: Int? = nil,
        totalRatingMIPS: Int? = nil,
        rows: [BenchmarkRow] = []
    ) {
        self.cpuModel = cpuModel
        self.ramSizeMB = ramSizeMB
        self.benchmarkThreads = benchmarkThreads
        self.compressSpeedKiBs = compressSpeedKiBs
        self.compressRatingMIPS = compressRatingMIPS
        self.decompressSpeedKiBs = decompressSpeedKiBs
        self.decompressRatingMIPS = decompressRatingMIPS
        self.totalRatingMIPS = totalRatingMIPS
        self.rows = rows
    }
}
