import Foundation

/// Thread-safe accumulator for pipe data drained on a background thread.
///
/// `Data` is mutated from a dedicated drain thread and read once that thread
/// has signalled completion; the lock makes the hand-off explicit for the
/// Swift 6 concurrency checker.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Holds a reference to a running `Process` so a cancellation handler on
/// another task can terminate it. `Process` is not `Sendable`; access is
/// serialised through a lock.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var terminated = false

    /// Stores the process, terminating it immediately if cancellation already
    /// arrived before the process was assigned.
    func adopt(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        if terminated {
            process.terminate()
        } else {
            self.process = process
        }
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        terminated = true
        process?.terminate()
    }
}

/// The single low-level gateway that launches the official `7zz` engine.
///
/// This is the only place in the codebase that spawns a process. Higher
/// layers (`SevenZipBridge`, the services) speak only in terms of arguments
/// and ``ProcessResult``; the UI never reaches this type directly.
public struct SevenZipRunner: Sendable {
    public let executable: SevenZipExecutable

    public init(executable: SevenZipExecutable) {
        self.executable = executable
    }

    /// Runs `7zz` with the given arguments and returns once it exits.
    ///
    /// Standard output and standard error are drained concurrently so that a
    /// large listing can never deadlock by filling a pipe buffer.
    ///
    /// - Parameter arguments: Arguments passed verbatim to `7zz`.
    /// - Returns: The captured ``ProcessResult``.
    /// - Throws: ``ArchiveError/launchFailed(reason:)`` if the process cannot start.
    public func run(_ arguments: [String]) async throws -> ProcessResult {
        let executableURL = executable.url
        return try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                // Never let the engine wait on interactive stdin (e.g. a
                // password prompt); we pass everything via arguments.
                process.standardInput = FileHandle.nullDevice

                // Drain stderr on its own thread while we drain stdout here.
                let errorBox = DataBox()
                let errorDone = DispatchSemaphore(value: 0)
                let errorHandle = errorPipe.fileHandleForReading
                let errorThread = Thread {
                    errorBox.append(errorHandle.readDataToEndOfFile())
                    errorDone.signal()
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(
                        throwing: ArchiveError.launchFailed(reason: error.localizedDescription)
                    )
                    return
                }

                errorThread.start()
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                errorDone.wait()

                continuation.resume(
                    returning: ProcessResult(
                        exitCode: process.terminationStatus,
                        standardOutput: outputData,
                        standardError: errorBox.value
                    )
                )
            }
        }
    }

    /// Runs `7zz`, streaming standard output to `onOutput` as it arrives.
    ///
    /// Used for long operations (extraction, compression) that report live
    /// progress. Standard error is captured and returned for error handling.
    /// If the surrounding task is cancelled the engine process is terminated.
    ///
    /// - Parameters:
    ///   - arguments: Arguments passed verbatim to `7zz`.
    ///   - onOutput: Called on a background thread with each chunk of stdout text.
    /// - Returns: The exit code and the captured standard error.
    /// - Throws: ``ArchiveError/launchFailed(reason:)`` if the process cannot start,
    ///   or ``ArchiveError/cancelled`` if cancelled before completing.
    public func stream(
        _ arguments: [String],
        workingDirectory: URL? = nil,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> (exitCode: Int32, standardError: Data) {
        let executableURL = executable.url
        let box = ProcessBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Thread.detachNewThread {
                    let process = Process()
                    process.executableURL = executableURL
                    process.arguments = arguments
                    if let workingDirectory {
                        process.currentDirectoryURL = workingDirectory
                    }

                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe
                    process.standardInput = FileHandle.nullDevice

                    let errorBox = DataBox()
                    let errorDone = DispatchSemaphore(value: 0)
                    let errorHandle = errorPipe.fileHandleForReading
                    let errorThread = Thread {
                        errorBox.append(errorHandle.readDataToEndOfFile())
                        errorDone.signal()
                    }

                    do {
                        try process.run()
                    } catch {
                        continuation.resume(
                            throwing: ArchiveError.launchFailed(reason: error.localizedDescription)
                        )
                        return
                    }
                    box.adopt(process)
                    errorThread.start()

                    // Drain stdout incrementally; `availableData` blocks until
                    // data arrives and returns empty at end-of-file.
                    let outputHandle = outputPipe.fileHandleForReading
                    while true {
                        let chunk = outputHandle.availableData
                        if chunk.isEmpty { break }
                        onOutput(String(decoding: chunk, as: UTF8.self))
                    }

                    process.waitUntilExit()
                    errorDone.wait()
                    continuation.resume(
                        returning: (process.terminationStatus, errorBox.value)
                    )
                }
            }
        } onCancel: {
            box.terminate()
        }
    }
}
