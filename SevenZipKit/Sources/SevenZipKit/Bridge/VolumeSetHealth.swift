import Foundation

/// Health of a multi-part RAR set named `<name>.partNN.rar`.
///
/// 7-Zip refuses to open the whole set when a volume is 0 bytes, and stops
/// listing at the first volume that is missing, so a set with either problem
/// is routed to the fallback engine instead. Only this naming scheme is
/// assessed; anything else (including healthy sets) returns `nil`.
struct VolumeSetHealth: Equatable, Sendable {
    var emptyVolumes: [String]
    var missingVolumeNumbers: [Int]

    var isDamaged: Bool { !emptyVolumes.isEmpty || !missingVolumeNumbers.isEmpty }

    static func assess(_ url: URL) -> VolumeSetHealth? {
        let name = url.lastPathComponent
        guard let match = name.range(of: #"\.part\d+\.rar$"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let prefix = String(name[..<match.lowerBound])
        let pattern = "^" + NSRegularExpression.escapedPattern(for: prefix) + #"\.part(\d+)\.rar$"#
        let directory = url.deletingLastPathComponent()
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let siblings = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey]
            )
        else { return nil }

        var present: Set<Int> = []
        var empty: [String] = []
        for sibling in siblings {
            let name = sibling.lastPathComponent
            let range = NSRange(name.startIndex..., in: name)
            guard
                let found = regex.firstMatch(in: name, range: range),
                let numberRange = Range(found.range(at: 1), in: name),
                let number = Int(name[numberRange])
            else { continue }
            present.insert(number)
            if (try? sibling.resourceValues(forKeys: [.fileSizeKey]).fileSize) == 0 { empty.append(name) }
        }
        guard let highest = present.max() else { return nil }
        let missing = (1...highest).filter { !present.contains($0) }
        return VolumeSetHealth(emptyVolumes: empty.sorted(), missingVolumeNumbers: missing)
    }
}
