import Foundation

/// Parses an incoming `file://` URL (double-click / "Open With") into a
/// structured command.
///
/// This used to also parse a private `sevenzip4mac://` scheme that the
/// Finder Sync extension talked to the app through, but that extension (and
/// the whole Finder-integration feature) was removed — Finder Sync
/// extensions require a paid Apple Developer ID code signature to be
/// accepted by macOS at all, which this ad-hoc-signed build doesn't have,
/// so it could never actually work.
enum AppURLRouter {
    enum Command: Equatable {
        /// Open an archive in the browser.
        case openArchive(URL)
    }

    static func command(for url: URL) -> Command? {
        guard url.isFileURL else { return nil }
        return .openArchive(url)
    }
}
