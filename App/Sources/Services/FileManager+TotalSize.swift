import Foundation

extension FileManager {
    /// Recursively sums the byte size of the given files/folders — shared by
    /// every place that needs to size a set of user-chosen or extracted
    /// items before a compress/copy/move so it can report real progress
    /// (`CompressionViewModel`'s New Archive flow, `ArchiveViewModel`'s Add,
    /// and `DragOut`'s cross-volume move all needed the identical
    /// `enumerator`-based walk, duplicated three times before this).
    func totalSize(of urls: [URL]) -> UInt64 {
        var total: UInt64 = 0
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let enumerator = enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
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
