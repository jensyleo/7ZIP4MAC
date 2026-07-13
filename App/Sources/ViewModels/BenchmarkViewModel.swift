import Foundation
import Observation
import SevenZipKit

/// Drives the Benchmark window: runs the engine's benchmark and publishes the
/// result. All logic lives here; the view only renders `state`.
@MainActor
@Observable
public final class BenchmarkViewModel {

    public enum State: Equatable {
        case idle
        case running
        case done(BenchmarkResult)
        case failed(message: String)
    }

    public private(set) var state: State = .idle

    private let serviceProvider: @Sendable () throws -> ArchiveServing
    private var task: Task<Void, Never>?

    public init(serviceProvider: @escaping @Sendable () throws -> ArchiveServing) {
        self.serviceProvider = serviceProvider
    }

    public convenience init() {
        self.init(serviceProvider: {
            let executable = try BundledEngine.resolve()
            return ArchiveService(executable: executable)
        })
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public var result: BenchmarkResult? {
        if case .done(let result) = state { return result }
        return nil
    }

    /// Runs the benchmark. `passes` nil uses the engine default.
    public func run(passes: Int? = nil) {
        task?.cancel()
        state = .running
        task = Task { [serviceProvider] in
            do {
                let service = try serviceProvider()
                let result = try await service.benchmark(passes: passes)
                if Task.isCancelled { return }
                self.state = .done(result)
            } catch is CancellationError {
                self.state = .idle
            } catch let error as ArchiveError {
                self.state = .failed(message: error.localizedDescription)
            } catch {
                self.state = .failed(message: error.localizedDescription)
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }
}
