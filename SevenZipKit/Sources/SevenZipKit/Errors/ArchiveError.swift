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

    /// A multi-part archive has one or more volumes that exist but are 0
    /// bytes — 7-Zip then reports the whole set as unreadable, which is
    /// otherwise indistinguishable from a genuinely corrupt file.
    case emptyVolumes(names: [String])

    /// The fallback engine's integrity test found damaged files (`failed`
    /// holds their descriptions; `passed` how many were fine).
    case integrityFailures(passed: Int, failed: [String])

    /// An extraction finished but some files could not be extracted;
    /// everything else was. `destinationIssue` is true when at least one
    /// failure happened while *writing* (the archive itself may be fine).
    case partialExtraction(failed: [String], destinationIssue: Bool)

    /// The engine (7-Zip, or the fallback `lsar`/`unar`) exited with a fatal
    /// status while performing an operation.
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
        case .emptyVolumes(let names):
            let shown = names.prefix(5).joined(separator: ", ")
            let more = names.count > 5 ? " and \(names.count - 5) more" : ""
            return "This multi-part archive can't be opened because \(names.count == 1 ? "a part is" : "\(names.count) parts are") empty (0 bytes): \(shown)\(more). Re-download or restore \(names.count == 1 ? "it" : "them") and try again."
        case .integrityFailures(let passed, let failed):
            let shown = failed.prefix(5).map { "• \($0)" }.joined(separator: "\n")
            let more = failed.count > 5 ? "\n…and \(failed.count - 5) more" : ""
            let hint = passed == 0 ? "\nIf every file fails, check that the password is correct." : ""
            return "\(failed.count) file(s) failed the integrity test (\(passed) passed):\n\(shown)\(more)\(hint)"
        case .partialExtraction(let failed, let destinationIssue):
            let shown = failed.prefix(10).map { "• \($0)" }.joined(separator: "\n")
            let more = failed.count > 10 ? "\n…and \(failed.count - 10) more" : ""
            let hint = destinationIssue
                ? "\nAt least one failed while writing to the destination (disk full, permissions or a dropped network connection) — the archive may be fine. Extract just those files again."
                : ""
            return "Everything else was extracted, but \(failed.count) file(s) could not be extracted:\n\(shown)\(more)\(hint)"
        case .operationFailed(let code, let message):
            return "The 7-Zip engine reported an error (code \(code)): \(message)"
        case .parsingFailed(let reason):
            return "The archive listing could not be read: \(reason)"
        case .cancelled:
            return "The operation was cancelled."
        }
    }
}
