import Foundation

/// Copies a file or folder to a place that may refuse everything but the data.
///
/// `FileManager.copyItem` also copies metadata (extended attributes, flags,
/// ACLs). Some network shares reject that — a Samba share (Batocera, many NAS
/// and PC shares) answers "Operation not permitted" — and the copy then fails
/// *after* creating the destination, leaving a file of size zero. This tries
/// the full copy first (it keeps metadata where the destination allows it),
/// and on failure removes the partial result and copies just the contents.
public enum ResilientCopy {
    public static func copyItem(at source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            try copyContentsOnly(at: source, to: destination)
        }
    }

    /// Data only: folders, regular files (streamed in 4 MB pieces) and
    /// symlinks. The modification date and the download marker are kept when
    /// the destination accepts them, and silently skipped when it does not.
    static func copyContentsOnly(at source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
        if values.isSymbolicLink == true {
            let target = try fileManager.destinationOfSymbolicLink(atPath: source.path)
            try fileManager.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
            return
        }
        if values.isDirectory == true {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            for child in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                try copyContentsOnly(at: child, to: destination.appendingPathComponent(child.lastPathComponent))
            }
        } else {
            try streamFile(from: source, to: destination)
        }
        if let date = values.contentModificationDate {
            try? fileManager.setAttributes([.modificationDate: date], ofItemAtPath: destination.path)
        }
        if let marker = Quarantine.value(of: source) {
            Quarantine.apply(marker, to: destination)
        }
    }

    private static func streamFile(from source: URL, to destination: URL) throws {
        guard let input = InputStream(url: source) else { throw CocoaError(.fileReadNoSuchFile) }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        input.open()
        defer { input.close() }
        var buffer = [UInt8](repeating: 0, count: 4 << 20)
        while true {
            let count = input.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw input.streamError ?? CocoaError(.fileReadUnknown) }
            if count == 0 { break }
            try output.write(contentsOf: buffer[0..<count])
        }
        try output.synchronize()
    }
}
