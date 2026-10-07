import Foundation

/// Text appended from the engine's output thread and read afterwards.
final class LockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ chunk: String) { lock.lock(); text += chunk; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return text }
}
