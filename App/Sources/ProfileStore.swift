import Foundation
import Observation
import SevenZipKit

/// Owns the compression profiles: the built-in presets plus any the user saves.
/// Custom profiles are persisted as JSON in `UserDefaults`.
@MainActor
@Observable
public final class ProfileStore {
    private let defaults: UserDefaults
    private let key = "customProfiles"

    public private(set) var custom: [CompressionProfile] = []

    /// Built-in profiles first, then the user's own.
    public var all: [CompressionProfile] {
        CompressionProfile.builtIns + custom
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    public func profile(id: CompressionProfile.ID) -> CompressionProfile? {
        all.first { $0.id == id }
    }

    /// Adds a new custom profile, or replaces an existing one — matched by
    /// `id` first (so editing a profile and renaming it updates it in place
    /// rather than leaving the old name behind), falling back to matching by
    /// `name` (for the "save current settings as a profile" flow, which
    /// always mints a fresh `id`).
    public func add(_ profile: CompressionProfile) {
        var toStore = profile
        toStore.isBuiltIn = false
        custom.removeAll { $0.id == profile.id || $0.name == profile.name }
        custom.append(toStore)
        save()
    }

    /// Deletes a custom profile. Built-ins are ignored.
    public func delete(_ profile: CompressionProfile) {
        guard !profile.isBuiltIn else { return }
        custom.removeAll { $0.id == profile.id }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CompressionProfile].self, from: data)
        else { return }
        custom = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(custom) else { return }
        defaults.set(data, forKey: key)
    }
}
