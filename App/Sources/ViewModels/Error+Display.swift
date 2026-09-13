import Foundation
import SevenZipKit

extension Error {
    /// The message to show the user for this error — `ArchiveError`'s own
    /// `localizedDescription` when it is one (nothing extra to add), or the
    /// generic `localizedDescription` otherwise. Shared by every ViewModel
    /// that surfaces a caught error as a user-facing string, instead of each
    /// repeating the same `(error as? ArchiveError)?.localizedDescription ??
    /// error.localizedDescription` fallback inline.
    var displayMessage: String {
        (self as? ArchiveError)?.localizedDescription ?? localizedDescription
    }
}
