import AppKit
#if canImport(Darwin)
import Darwin
#endif

/// Guarantees a single running process **per user**. Every archive still gets
/// its own window (see ``ArchiveWindowRoot``) — this only stops a second
/// Dock/Finder launch from starting a duplicate process, the same as any
/// standard single-process, multi-window Mac app (Preview, TextEdit).
enum SingleInstance {

    static func enforceOrExit() {
        let selfPID = getpid()
        let others = sameUserInstances().filter { $0 != selfPID }
        guard let otherPID = others.first else { return }
        NSRunningApplication(processIdentifier: otherPID)?.activate()
        exit(0)
    }

    private static func sameUserInstances() -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        // -U <uid>: only processes owned by the current user; -x: exact name.
        process.arguments = ["-x", "-U", "\(getuid())", "7ZIP4MAC"]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }
}
