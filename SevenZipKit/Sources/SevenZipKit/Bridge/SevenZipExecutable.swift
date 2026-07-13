import Foundation

/// A validated reference to the official `7zz` engine binary.
///
/// The UI never constructs the path itself; the App supplies the location of
/// the bundled engine and every service receives it through this value.
public struct SevenZipExecutable: Sendable, Hashable {
    /// Location of the `7zz` executable on disk.
    public let url: URL

    /// Creates a reference to an engine binary at the given URL.
    ///
    /// - Throws: ``ArchiveError/executableNotFound`` if no file exists there.
    public init(validatingURL url: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ArchiveError.executableNotFound
        }
        self.url = url
    }

    /// Creates a reference without validating the file. Prefer
    /// ``init(validatingURL:)`` outside of tests.
    public init(unchecked url: URL) {
        self.url = url
    }
}
