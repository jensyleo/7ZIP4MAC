import AppKit
import UniformTypeIdentifiers
import SevenZipKit

/// Sets 7ZIP4MAC as the default app for a file type, mirroring 7-Zip for
/// Windows' "associate this extension" checkboxes.
///
/// Before overriding a type for the first time, the previous default handler
/// is recorded in `AppSettings.originalHandlerPaths` — the uninstaller uses
/// this to hand each type back to whatever opened it before, instead of
/// leaving the default-handler assignment dangling on a deleted app (macOS
/// doesn't do this automatically; the assignment is keyed by bundle
/// identifier, not by whether the file still exists on disk).
@MainActor
enum FileAssociationService {
    /// Makes 7ZIP4MAC the default application for `format`, recording the
    /// previous default (if any, and if not already recorded) first.
    /// - Returns: `true` on success, `false` if the format has no resolvable
    ///   UTType on this system (logged, not thrown — this shouldn't normally
    ///   happen since every format was verified when the icons were wired).
    @discardableResult
    static func associate(_ format: AssociableFormat, settings: AppSettings) async -> Bool {
        guard let type = format.utType else {
            ArchiveLog.service.error("No UTType for \(format.key, privacy: .public); cannot associate")
            return false
        }
        if settings.originalHandlerPaths[format.utTypeIdentifier] == nil,
           let previous = NSWorkspace.shared.urlForApplication(toOpen: type),
           previous.path != Bundle.main.bundleURL.path {
            settings.originalHandlerPaths[format.utTypeIdentifier] = previous.path
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
    static func associate(all formats: [AssociableFormat], settings: AppSettings) async {
        for format in formats {
            await associate(format, settings: settings)
        }
    }

    /// Hands every recorded association back to its original app (called
    /// from the uninstaller, before the bundle is trashed). Formats with no
    /// recorded original (never associated through this app's own toggles,
    /// e.g. the custom archive/image UTIs this app is the *only* declared
    /// handler for) are left untouched — there is no other app to fall back
    /// to, so macOS correctly reports "no application can open this" once
    /// 7ZIP4MAC is gone.
    static func restoreOriginals(settings: AppSettings) async {
        for format in AssociableFormat.all {
            guard let path = settings.originalHandlerPaths[format.utTypeIdentifier],
                  let type = format.utType else { continue }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: url, toOpen: type)
                ArchiveLog.service.info("Restored \(format.key, privacy: .public) to its original handler")
            } catch {
                ArchiveLog.service.error("Failed to restore \(format.key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        settings.originalHandlerPaths = [:]
    }
}
