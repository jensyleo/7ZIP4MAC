import Foundation
import Observation
import SevenZipKit

/// Drives the "create a new archive" flow: choosing sources, configuring
/// format/level/password, running the compression and reporting the result.
///
/// Independent of the currently opened archive; all logic lives here.
@MainActor
@Observable
public final class CompressionViewModel {

    public enum Phase: Equatable {
        case idle
        case configuring
        case running(ProgressInfo)
        case finished(archiveURL: URL)
        case failed(message: String)
    }

    public private(set) var phase: Phase = .idle

    // Configuration bound to the options sheet.
    public var sources: [URL] = []
    public var format: ArchiveFormat = .sevenZip
    public var level: CompressionLevel = .normal
    public var password: String = ""
    public var encryptFileNames: Bool = false
    /// Split size in bytes, or nil for a single file.
    public var volumeSize: UInt64?

    private let serviceProvider: @Sendable () throws -> ArchiveServing
    private var task: Task<Void, Never>?

    public init(serviceProvider: @escaping @Sendable () throws -> ArchiveServing) {
        self.serviceProvider = serviceProvider
    }

    public convenience init() {
        self.init(serviceProvider: {
            let executable = try BundledEngine.resolve()
            return ArchiveService(executable: executable)
        })
    }

    // MARK: - Derived state

    public var isConfiguring: Bool { phase == .configuring }

    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// A sensible default archive file name for the current sources and format.
    public var suggestedFileName: String {
        let base: String
        if sources.count == 1 {
            base = sources[0].deletingPathExtension().lastPathComponent
        } else {
            base = "Archive"
        }
        return "\(base).\(format.fileExtension)"
    }

    // MARK: - Intents

    /// Starts the flow with the chosen source files/folders, seeded with the
    /// user's default format/level/encryption preferences.
    public func begin(
        sources: [URL],
        format: ArchiveFormat = .sevenZip,
        level: CompressionLevel = .normal,
        encryptFileNames: Bool = false
    ) {
        guard !sources.isEmpty else { return }
        self.sources = sources
        self.format = format
        self.level = level
        self.encryptFileNames = encryptFileNames
        password = ""
        volumeSize = nil
        phase = .configuring
    }

    /// Applies a saved profile's settings to the current configuration.
    public func apply(_ profile: CompressionProfile) {
        format = profile.format
        level = profile.level
        encryptFileNames = profile.encryptFileNames
        volumeSize = profile.volumeSize
    }

    /// The current configuration captured as a profile with the given name.
    public func currentProfile(named name: String) -> CompressionProfile {
        CompressionProfile(
            name: name, format: format, level: level,
            encryptFileNames: encryptFileNames,
            requiresPassword: !password.isEmpty,
            volumeSize: volumeSize
        )
    }

    /// Cancels configuration or a running compression, returning to idle.
    public func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    /// Dismisses a finished/failed result, returning to idle.
    public func dismissResult() {
        phase = .idle
    }

    /// Runs the compression, writing to `destination`.
    public func create(destination: URL) {
        task?.cancel()
        phase = .running(.zero)

        let request = CompressionRequest(
            destinationURL: destination,
            sourceURLs: sources,
            format: format,
            level: level,
            password: password.isEmpty ? nil : password,
            encryptFileNames: encryptFileNames,
            totalSourceSize: Self.totalSize(of: sources),
            volumeSize: volumeSize
        )

        task = Task { [serviceProvider] in
            do {
                let service = try serviceProvider()
                try await service.compress(request) { info in
                    Task { @MainActor in
                        if case .running = self.phase { self.phase = .running(info) }
                    }
                }
                if Task.isCancelled { return }
                self.phase = .finished(archiveURL: destination)
            } catch is CancellationError {
                self.phase = .idle
            } catch ArchiveError.cancelled {
                self.phase = .idle
            } catch let error as ArchiveError {
                self.phase = .failed(message: error.localizedDescription)
            } catch {
                self.phase = .failed(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    /// Recursively sums the byte size of the given files/folders.
    private static func totalSize(of urls: [URL]) -> UInt64 {
        let fm = FileManager.default
        var total: UInt64 = 0
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
                )
                while let child = enumerator?.nextObject() as? URL {
                    let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    if values?.isRegularFile == true {
                        total += UInt64(values?.fileSize ?? 0)
                    }
                }
            } else {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                total += UInt64(size)
            }
        }
        return total
    }
}
