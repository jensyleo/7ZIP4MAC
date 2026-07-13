import AppKit
#if canImport(Darwin)
import Darwin
#endif

/// Guarantees a single running instance **per user**. If another 7ZIP4MAC
/// owned by the same uid is already running, this instance activates it and
/// exits immediately.
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
