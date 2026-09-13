import Foundation
import SevenZipKit

/// Whether each automation surface is allowed to actually run, read straight
/// from `UserDefaults` (the same keys `AppSettings` writes) since both the
/// AppleScript commands and the App Intents are instantiated by the system,
/// outside the app's normal `AppSettings` object graph.
enum AutomationGate {
    static var appleScriptEnabled: Bool {
        UserDefaults.standard.bool(forKey: "appleScriptAutomationEnabled")
    }

    static var shortcutsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "shortcutsAutomationEnabled")
    }
}

/// Thrown when an automation surface is invoked while disabled in Settings.
struct AutomationDisabledError: LocalizedError {
    let surface: String
    var errorDescription: String? {
        "\(surface) automation is turned off. Enable it in 7ZIP4MAC ▸ Settings ▸ Automation."
    }
}

/// Thrown when `AutomationService.compress` is asked for a destination whose
/// extension doesn't match any writable ``ArchiveFormat``. Matching by file
/// extension and silently falling back to `.7z` for anything unrecognized
/// was a real bug here (mirroring the one already fixed in
/// `ArchiveViewModel.writableFormat`) — a Shortcut or AppleScript command
/// targeting, say, "archive.xyz" would silently produce actual 7z content
/// under that misleading name instead of failing.
struct UnsupportedDestinationFormatError: LocalizedError {
    let destination: URL
    var errorDescription: String? {
        "“\(destination.lastPathComponent)” doesn't match a supported archive format. Use a .7z, .zip, or .tar destination."
    }
}

/// Headless compress/extract operations shared by AppleScript commands and
/// App Intents (Shortcuts/Siri) — independent of any ViewModel or UI
/// progress state, since both callers run outside a visible window.
enum AutomationService {
    static func compress(
        sources: [URL],
        destination: URL,
        password: String? = nil
    ) async throws -> URL {
        guard let format = ArchiveFormat.allCases.first(where: { $0.fileExtension == destination.pathExtension.lowercased() }) else {
            throw UnsupportedDestinationFormatError(destination: destination)
        }
        let executable = try BundledEngine.resolve()
        let service = ArchiveService(executable: executable)
        let request = CompressionRequest(
            destinationURL: destination,
            sourceURLs: sources,
            format: format,
            password: password,
            encryptFileNames: password != nil,
            totalSourceSize: 0
        )
        try await service.compress(request, progress: { _ in })
        return destination
    }

    static func extract(
        archive: URL,
        destination: URL,
        password: String? = nil
    ) async throws -> URL {
        let executable = try BundledEngine.resolve()
        let service = ArchiveService(executable: executable)
        let request = ExtractionRequest(
            archiveURL: archive,
            destinationURL: destination,
            password: password
        )
        try await service.extract(request, progress: { _ in })
        return destination
    }
}
