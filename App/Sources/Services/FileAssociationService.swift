import AppKit
import UniformTypeIdentifiers
import SevenZipKit

/// Sets 7ZIP4MAC as the default app for a file type, mirroring 7-Zip for
/// Windows' "associate this extension" checkboxes.
///
/// macOS has no public API to *un*-associate a type back to whatever the
/// previous default was — turning a toggle off just stops us from claiming
/// it going forward; the user can still pick another app manually via
/// Finder's Get Info ▸ Open With ▸ Change All.
@MainActor
enum FileAssociationService {
    /// Makes 7ZIP4MAC the default application for `format`.
    /// - Returns: `true` on success, `false` if the format has no resolvable
    ///   UTType on this system (logged, not thrown — this shouldn't normally
    ///   happen since every format was verified when the icons were wired).
    @discardableResult
    static func associate(_ format: AssociableFormat) async -> Bool {
        guard let type = format.utType else {
            ArchiveLog.service.error("No UTType for \(format.key, privacy: .public); cannot associate")
            return false
        }
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
            ArchiveLog.service.info("Associated \(format.key, privacy: .public) with 7ZIP4MAC")
            return true
        } catch {
            ArchiveLog.service.error("Failed to associate \(format.key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Associates every format in `formats`, sequentially (LaunchServices
    /// doesn't benefit from concurrency here and this keeps failures isolated
    /// and logged per-format instead of one failure aborting the rest).
    static func associate(all formats: [AssociableFormat]) async {
        for format in formats {
            await associate(format)
        }
    }
}
