import Foundation

/// Typed errors surfaced by every layer of the 7-Zip bridge.
///
/// No layer of the application identifies errors by matching against
/// free-form strings. All failures are expressed through this enum so that
/// ViewModels and Views can react to specific, exhaustive cases.
public enum ArchiveError: Error, Equatable, Sendable {
    /// The bundled `7zz` executable could not be located.
    case executableNotFound

    /// The `7zz` process could not be launched at all.
    case launchFailed(reason: String)

    /// The archive file does not exist at the given path.
    case archiveNotFound(path: String)

    /// The archive is encrypted and the supplied password was missing or wrong.
    case wrongPassword

    /// 7-Zip does not recognise the archive format, or the file is corrupt.
    case unsupportedFormat

    /// `7zz` exited with a fatal status while performing an operation.
    case operationFailed(code: Int32, message: String)

    /// The `7zz` output could not be parsed into a structured listing.
    case parsingFailed(reason: String)

    /// The operation was cancelled by the caller.
    case cancelled
}

extension ArchiveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "The 7-Zip engine could not be found inside the application."
        case .launchFailed(let reason):
            return "The 7-Zip engine failed to launch: \(reason)"
        case .archiveNotFound(let path):
            return "The archive could not be found at \(path)."
        case .wrongPassword:
            return "The archive is encrypted and requires a valid password."
        case .unsupportedFormat:
            return "This file is not a supported archive, or it is damaged."
        case .operationFailed(let code, let message):
            return "The 7-Zip engine reported an error (code \(code)): \(message)"
        case .parsingFailed(let reason):
            return "The archive listing could not be read: \(reason)"
        case .cancelled:
            return "The operation was cancelled."
        }
    }
}
