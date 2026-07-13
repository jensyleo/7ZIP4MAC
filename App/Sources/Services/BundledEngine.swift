import Foundation
import SevenZipKit

/// Locates the official `7zz` engine bundled inside the application.
///
/// The engine ships as a folder reference at `Contents/Resources/Engine/7zz`.
/// This is the single place that knows where the binary lives; services
/// receive a validated ``SevenZipExecutable`` and never touch the bundle.
enum BundledEngine {
    // The engine's location can't change during a run, so the validated
    // reference is resolved once and reused — this is called before every
    // single operation (open, extract, test, compress, benchmark, drag-out),
    // some of which run off the main actor (e.g. `DragOut`), hence the lock
    // rather than e.g. a `@MainActor`-confined cache.
    nonisolated(unsafe) private static var cached: SevenZipExecutable?
    private static let lock = NSLock()

    /// Resolves the bundled engine, validating that it exists and is executable.
    static func resolve() throws -> SevenZipExecutable {
        lock.lock()
        if let cached { lock.unlock(); return cached }
        lock.unlock()

        guard let url = Bundle.main.url(
            forResource: "7zz",
            withExtension: nil,
            subdirectory: "Engine"
        ) else {
            throw ArchiveError.executableNotFound
        }
        let executable = try SevenZipExecutable(validatingURL: url)

        lock.lock(); cached = executable; lock.unlock()
        return executable
    }
}
