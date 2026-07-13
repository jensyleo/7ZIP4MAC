import Foundation
import SevenZipKit

// A tiny command-line harness for exercising SevenZipKit against a real
// archive without launching the app.
//
//   sevenzip-cli list    <7zz> <archive> [password]
//   sevenzip-cli extract <7zz> <archive> <destination> [password]
//
// (With no command the first form is assumed for backwards compatibility.)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let raw = Array(CommandLine.arguments.dropFirst())
let knownCommands: Set<String> = ["list", "extract", "compress", "benchmark", "test"]
let command = raw.first.map { knownCommands.contains($0) ? $0 : "list" } ?? "list"
let args = (raw.first.map(knownCommands.contains) ?? false) ? Array(raw.dropFirst()) : raw

func reportProgress(_ info: ProgressInfo) {
    let pct = Int(info.fractionCompleted * 100)
    let mbps = info.bytesPerSecond / 1_048_576
    let eta = info.estimatedTimeRemaining.map { String(format: "%.1fs", $0) } ?? "—"
    FileHandle.standardError.write(Data(
        String(format: "\r%3d%%  %6.1f MB/s  ETA %@  %@\u{1B}[K", pct, mbps, eta, info.currentFile ?? "").utf8
    ))
}

do {
    switch command {
    case "extract":
        guard args.count >= 3 else { fail("usage: sevenzip-cli extract <7zz> <archive> <destination> [password]") }
        let executable = try SevenZipExecutable(validatingURL: URL(fileURLWithPath: args[0]))
        let archiveURL = URL(fileURLWithPath: args[1])
        let destination = URL(fileURLWithPath: args[2])
        let password = args.count >= 4 ? args[3] : nil

        let service = ArchiveService(executable: executable)
        // Discover total size first, for ETA/throughput.
        let archive = try await service.open(archiveAt: archiveURL, password: password)
        let request = ExtractionRequest(
            archiveURL: archiveURL,
            destinationURL: destination,
            password: password,
            totalUncompressedSize: archive.totalSize
        )
        print("Extracting \(archive.fileCount) files (\(archive.totalSize) bytes) to \(destination.path)")
        try await service.extract(request) { info in
            let pct = Int(info.fractionCompleted * 100)
            let mbps = info.bytesPerSecond / 1_048_576
            let eta = info.estimatedTimeRemaining.map { String(format: "%.1fs", $0) } ?? "—"
            let file = info.currentFile ?? ""
            FileHandle.standardError.write(Data(
                String(format: "\r%3d%%  %6.1f MB/s  ETA %@  %@\u{1B}[K", pct, mbps, eta, file).utf8
            ))
        }
        FileHandle.standardError.write(Data("\n".utf8))
        print("Done.")

    case "compress":
        guard args.count >= 4 else { fail("usage: sevenzip-cli compress <7zz> <out-archive> <format> <source...>") }
        let executable = try SevenZipExecutable(validatingURL: URL(fileURLWithPath: args[0]))
        let destination = URL(fileURLWithPath: args[1])
        guard let format = ArchiveFormat(rawValue: args[2]) ?? ArchiveFormat.allCases.first(where: { $0.typeArgument == args[2] }) else {
            fail("unknown format: \(args[2]) (use sevenZip|zip|tar)")
        }
        let sources = args[3...].map { URL(fileURLWithPath: $0) }
        let total = sources.reduce(UInt64(0)) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + UInt64(size)
        }
        let service = ArchiveService(executable: executable)
        let request = CompressionRequest(
            destinationURL: destination, sourceURLs: sources,
            format: format, level: .normal, totalSourceSize: total
        )
        print("Compressing \(sources.count) source(s) → \(destination.lastPathComponent) [\(format.displayName)]")
        try await service.compress(request, progress: reportProgress)
        FileHandle.standardError.write(Data("\n".utf8))
        print("Done.")

    case "benchmark":
        guard args.count >= 1 else { fail("usage: sevenzip-cli benchmark <7zz> [passes]") }
        let executable = try SevenZipExecutable(validatingURL: URL(fileURLWithPath: args[0]))
        let passes = args.count >= 2 ? Int(args[1]) : nil
        let service = ArchiveService(executable: executable)
        print("Benchmarking…")
        let result = try await service.benchmark(passes: passes)
        print("CPU:   \(result.cpuModel ?? "unknown")")
        print("RAM:   \(result.ramSizeMB.map { "\($0) MB" } ?? "unknown")")
        print("Compress:   \(result.compressRatingMIPS ?? 0) MIPS")
        print("Decompress: \(result.decompressRatingMIPS ?? 0) MIPS")
        print("Total:      \(result.totalRatingMIPS ?? 0) MIPS")

    case "test":
        guard args.count >= 2 else { fail("usage: sevenzip-cli test <7zz> <archive> [password]") }
        let executable = try SevenZipExecutable(validatingURL: URL(fileURLWithPath: args[0]))
        let service = ArchiveService(executable: executable)
        let ok = try await service.test(archiveAt: URL(fileURLWithPath: args[1]),
                                        password: args.count >= 3 ? args[2] : nil)
        print(ok ? "OK: archive is healthy" : "PROBLEMS: archive failed the test")
        if !ok { exit(1) }

    default:
        guard args.count >= 2 else { fail("usage: sevenzip-cli list <7zz> <archive> [password]") }
        let executable = try SevenZipExecutable(validatingURL: URL(fileURLWithPath: args[0]))
        let archiveURL = URL(fileURLWithPath: args[1])
        let password = args.count >= 3 ? args[2] : nil

        let service = ArchiveService(executable: executable)
        let archive = try await service.open(archiveAt: archiveURL, password: password)

        print("Archive: \(archive.url.lastPathComponent)")
        print("Format:  \(archive.properties.format ?? "unknown")")
        print("Entries: \(archive.entries.count) (\(archive.fileCount) files, \(archive.folderCount) folders)")
        print("Size:    \(archive.totalSize) bytes")
        print("---")
        for entry in archive.entries {
            let kind = entry.isDirectory ? "DIR " : "FILE"
            print("\(kind)  \(entry.size)\t\(entry.path)")
        }
    }
} catch let error as ArchiveError {
    fail("error: \(error.localizedDescription)")
} catch {
    fail("error: \(error.localizedDescription)")
}
