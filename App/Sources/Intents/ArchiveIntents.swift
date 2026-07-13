import AppIntents
import Foundation
import SevenZipKit

/// Shortcuts/Siri action: compress one or more files into a 7z archive.
///
/// Files handed in by Shortcuts arrive as `IntentFile` (data + filename, not
/// a live on-disk URL), so each is written to a scratch directory before
/// handing it to the same headless ``AutomationService`` AppleScript uses,
/// and the resulting archive is read back as the intent's output file.
struct CompressFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Compress Files"
    static let description = IntentDescription("Creates a 7z archive from one or more files, optionally password-protected.")

    @Parameter(title: "Files") var files: [IntentFile]
    @Parameter(title: "Archive Name", default: "Archive") var archiveName: String
    @Parameter(title: "Password", default: nil) var password: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Compress \(\.$files) into \(\.$archiveName)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard AutomationGate.shortcutsEnabled else { throw AutomationDisabledError(surface: "Shortcuts") }

        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        var sources: [URL] = []
        for file in files {
            let url = scratch.appendingPathComponent(file.filename ?? UUID().uuidString)
            try file.data.write(to: url)
            sources.append(url)
        }

        let sanitizedName = archiveName.isEmpty ? "Archive" : archiveName
        let destination = scratch.appendingPathComponent("\(sanitizedName).7z")
        _ = try await AutomationService.compress(sources: sources, destination: destination, password: password)

        let data = try Data(contentsOf: destination)
        let result = IntentFile(data: data, filename: destination.lastPathComponent, type: .init(filenameExtension: "7z"))
        return .result(value: result)
    }
}

/// Shortcuts/Siri action: extract an archive's contents.
///
/// Extracted contents are returned zipped back into a single `IntentFile`
/// (Shortcuts has no first-class "folder" output type), so the user can save
/// or unzip the result with the Files app / Archive Utility.
struct ExtractArchiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Extract Archive"
    static let description = IntentDescription("Extracts an archive's contents, returning them as a folder archive.")

    @Parameter(title: "Archive") var archive: IntentFile
    @Parameter(title: "Password", default: nil) var password: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Extract \(\.$archive)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard AutomationGate.shortcutsEnabled else { throw AutomationDisabledError(surface: "Shortcuts") }

        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let archiveURL = scratch.appendingPathComponent(archive.filename ?? "archive")
        try archive.data.write(to: archiveURL)

        let destination = scratch.appendingPathComponent("Extracted", isDirectory: true)
        _ = try await AutomationService.extract(archive: archiveURL, destination: destination, password: password)

        let zipped = scratch.appendingPathComponent("Extracted.zip")
        _ = try await AutomationService.compress(sources: [destination], destination: zipped)

        let data = try Data(contentsOf: zipped)
        let result = IntentFile(data: data, filename: zipped.lastPathComponent, type: .zip)
        return .result(value: result)
    }
}

private func makeScratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("7ZIP4MAC-Intent-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Exposes the app's intents to Shortcuts/Spotlight with ready-made phrases.
struct SevenZip4MacShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompressFilesIntent(),
            phrases: ["Compress files with \(.applicationName)"],
            shortTitle: "Compress Files",
            systemImageName: "archivebox"
        )
        AppShortcut(
            intent: ExtractArchiveIntent(),
            phrases: ["Extract archive with \(.applicationName)"],
            shortTitle: "Extract Archive",
            systemImageName: "archivebox.fill"
        )
    }
}
