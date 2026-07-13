import Foundation

/// The outcome of running the `7zz` engine once: its exit status and the
/// bytes it wrote to standard output and standard error.
public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data

    public init(exitCode: Int32, standardOutput: Data, standardError: Data) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    /// Standard output decoded as UTF-8.
    public var outputString: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    /// Standard error decoded as UTF-8.
    public var errorString: String {
        String(decoding: standardError, as: UTF8.self)
    }
}
