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

/// Headless compress/extract operations shared by AppleScript commands and
/// App Intents (Shortcuts/Siri) — independent of any ViewModel or UI
/// progress state, since both callers run outside a visible window.
enum AutomationService {
    static func compress(
        sources: [URL],
        destination: URL,
        password: String? = nil
    ) async throws -> URL {
        let executable = try BundledEngine.resolve()
        let service = ArchiveService(executable: executable)
        let format = ArchiveFormat.allCases.first { $0.fileExtension == destination.pathExtension.lowercased() } ?? .sevenZip
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
