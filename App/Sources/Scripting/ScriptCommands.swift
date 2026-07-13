import AppKit
import Foundation
import SevenZipKit

/// Local stand-ins for the Carbon `errOSA*` constants (avoids importing Carbon
/// just for two OSStatus values).
private enum OSAScriptError {
    static let parameterMismatch = -1743
    static let executionFailed = -2700
}

/// Backs the `compress` AppleScript command declared in `7ZIP4MAC.sdef`.
///
/// AppleScript commands are inherently synchronous (`performDefaultImplementation`
/// must return the result directly), while `AutomationService` is `async`, so
/// each command blocks its own dispatch with a semaphore rather than the main
/// thread — AppleEvents are already delivered off the main run loop step.
@objc(CompressScriptCommand)
final class CompressScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard AutomationGate.appleScriptEnabled else {
            scriptErrorNumber = OSAScriptError.executionFailed
            scriptErrorString = AutomationDisabledError(surface: "AppleScript").localizedDescription
            return nil
        }
        guard let sources = directParameterURLs(), !sources.isEmpty else {
            scriptErrorNumber = OSAScriptError.parameterMismatch
            scriptErrorString = "compress requires at least one file or folder."
            return nil
        }
        guard let destination = fileURLArgument("destination") else {
            scriptErrorNumber = OSAScriptError.parameterMismatch
            scriptErrorString = "compress requires a destination archive (\"to\" parameter)."
            return nil
        }
        let password = evaluatedArguments?["password"] as? String

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<URL, Error>?
        Task {
            do {
                let url = try await AutomationService.compress(
                    sources: sources, destination: destination, password: password
                )
                result = .success(url)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()

        switch result {
        case .success(let url):
            return url as NSURL
        case .failure(let error):
            scriptErrorNumber = OSAScriptError.executionFailed
            scriptErrorString = "7ZIP4MAC couldn't create the archive: \(error.localizedDescription)"
            return nil
        case nil:
            return nil
        }
    }
}

/// Backs the `extract` AppleScript command declared in `7ZIP4MAC.sdef`.
@objc(ExtractScriptCommand)
final class ExtractScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard AutomationGate.appleScriptEnabled else {
            scriptErrorNumber = OSAScriptError.executionFailed
            scriptErrorString = AutomationDisabledError(surface: "AppleScript").localizedDescription
            return nil
        }
        guard let archive = directParameterURL() else {
            scriptErrorNumber = OSAScriptError.parameterMismatch
            scriptErrorString = "extract requires an archive to extract."
            return nil
        }
        let destination = fileURLArgument("destination")
            ?? archive.deletingLastPathComponent()
                .appendingPathComponent(archive.deletingPathExtension().lastPathComponent)
        let password = evaluatedArguments?["password"] as? String

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<URL, Error>?
        Task {
            do {
                let url = try await AutomationService.extract(
                    archive: archive, destination: destination, password: password
                )
                result = .success(url)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()

        switch result {
        case .success(let url):
            return url as NSURL
        case .failure(let error):
            scriptErrorNumber = OSAScriptError.executionFailed
            scriptErrorString = "7ZIP4MAC couldn't extract the archive: \(error.localizedDescription)"
            return nil
        case nil:
            return nil
        }
    }
}

// MARK: - Argument coercion

private extension NSScriptCommand {
    /// The command's direct parameter as a single file URL (for `extract`,
    /// which takes exactly one archive).
    func directParameterURL() -> URL? {
        if let url = directParameter as? URL { return url }
        if let descriptor = directParameter as? NSAppleEventDescriptor {
            return descriptor.fileURLValue
        }
        return nil
    }

    /// The command's direct parameter as a list of file URLs (for `compress`,
    /// which accepts one or more sources).
    func directParameterURLs() -> [URL]? {
        if let list = directParameter as? [URL] { return list }
        if let url = directParameterURL() { return [url] }
        if let descriptor = directParameter as? NSAppleEventDescriptor, descriptor.isRecordDescriptor == false {
            var urls: [URL] = []
            for index in 1...max(descriptor.numberOfItems, 1) where descriptor.numberOfItems > 0 {
                if let url = descriptor.atIndex(index)?.fileURLValue { urls.append(url) }
            }
            return urls.isEmpty ? nil : urls
        }
        return nil
    }

    /// A named parameter coerced to a file URL.
    func fileURLArgument(_ key: String) -> URL? {
        guard let value = evaluatedArguments?[key] else { return nil }
        if let url = value as? URL { return url }
        if let descriptor = value as? NSAppleEventDescriptor { return descriptor.fileURLValue }
        if let path = value as? String { return URL(fileURLWithPath: path) }
        return nil
    }
}

private extension NSAppleEventDescriptor {
    var fileURLValue: URL? {
        if let url = fileURLValue(forType: typeFileURL) { return url }
        if let string = stringValue { return URL(fileURLWithPath: string) }
        return nil
    }

    func fileURLValue(forType type: DescType) -> URL? {
        guard let data = self.data as Data?, self.descriptorType == type else { return nil }
        return URL(dataRepresentation: data, relativeTo: nil)
    }
}
