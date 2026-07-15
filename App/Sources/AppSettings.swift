import Foundation
import Observation
import SevenZipKit

/// User preferences, persisted in `UserDefaults` and observable by the UI.
///
/// Stored properties are the source of truth for observation; each writes
/// through to `UserDefaults` so the choice survives relaunches.
@MainActor
@Observable
public final class AppSettings {
    private let defaults: UserDefaults

    /// Default container format for new archives.
    public var defaultFormat: ArchiveFormat {
        didSet { defaults.set(defaultFormat.rawValue, forKey: Keys.format) }
    }

    /// Default compression effort for new archives.
    public var defaultLevel: CompressionLevel {
        didSet { defaults.set(defaultLevel.rawValue, forKey: Keys.level) }
    }

    /// Whether to encrypt entry names by default (7-Zip, when a password is set).
    public var defaultEncryptFileNames: Bool {
        didSet { defaults.set(defaultEncryptFileNames, forKey: Keys.encryptNames) }
    }

    /// Whether extraction creates a subfolder named after the archive.
    public var extractIntoSubfolder: Bool {
        didSet { defaults.set(extractIntoSubfolder, forKey: Keys.subfolder) }
    }

    /// How extraction handles files that already exist at the destination.
    public var defaultOverwritePolicy: ExtractionRequest.OverwritePolicy {
        didSet { defaults.set(defaultOverwritePolicy.rawValue, forKey: Keys.overwritePolicy) }
    }

    /// Whether to reveal the result in Finder after extracting or creating.
    public var revealInFinderWhenDone: Bool {
        didSet { defaults.set(revealInFinderWhenDone, forKey: Keys.reveal) }
    }

    /// Whether extraction shows a completion dialog (with a "Show in Finder"
    /// button) when it finishes. Off by default — extraction just completes
    /// quietly; turn this on to get the confirmation and the reveal shortcut.
    /// Extraction *failures* always show, regardless.
    public var confirmAfterExtraction: Bool {
        didSet { defaults.set(confirmAfterExtraction, forKey: Keys.confirmExtraction) }
    }

    /// Whether to show macOS/Unix "hidden" entries (names starting with "."
    /// or "__", e.g. `.DS_Store`, `__MACOSX`) when browsing an archive.
    /// Off by default — these are noise left by macOS/zip tooling, not
    /// content the user put there.
    public var showHiddenEntries: Bool {
        didSet { defaults.set(showHiddenEntries, forKey: Keys.showHidden) }
    }

    /// Keys of `AssociableFormat`s shown as "on" in Settings ▸ File Types.
    /// Defaults to every associable format except ISO/DMG/PKG (which override
    /// macOS's built-in mount/install behavior, so they're opt-in), matching
    /// 7-Zip for Windows' "associate everything" default — but note this only
    /// reflects what the toggles *show*; macOS requires a per-format
    /// confirmation dialog before any of them actually take effect (see
    /// `FileAssociationService`), so this is never auto-applied on launch,
    /// only when the user acts in Settings.
    public var associatedFormatKeys: Set<String> {
        didSet { defaults.set(Array(associatedFormatKeys), forKey: Keys.associations) }
    }

    /// The default-handler app path recorded for each UTI *before* 7ZIP4MAC
    /// took it over, keyed by `AssociableFormat.utTypeIdentifier`. Captured
    /// once at association time (never overwritten by a later re-association)
    /// so the uninstaller can hand each type back to whatever opened it
    /// before, instead of leaving the assignment dangling on a deleted app.
    public var originalHandlerPaths: [String: String] {
        didSet { defaults.set(originalHandlerPaths, forKey: Keys.originalHandlers) }
    }

    /// Whether the app has already sent the user to Settings ▸ File Types
    /// once, on first launch. Guards a one-time nudge — it should never fire
    /// again after that first appearance, even if the user never acts on it.
    public var hasShownFileTypesOnboarding: Bool {
        didSet { defaults.set(hasShownFileTypesOnboarding, forKey: Keys.fileTypesOnboardingShown) }
    }

    /// Whether the `compress`/`extract` AppleScript commands (`7ZIP4MAC.sdef`)
    /// actually run when invoked. Off by default: AppleScript exposes a
    /// scripting surface any script/app on the Mac can call unannounced, so
    /// it's opt-in rather than always-on.
    public var appleScriptAutomationEnabled: Bool {
        didSet { defaults.set(appleScriptAutomationEnabled, forKey: Keys.appleScriptEnabled) }
    }

    /// Whether the Shortcuts/Siri actions (``CompressFilesIntent``,
    /// ``ExtractArchiveIntent``) actually run when invoked. Off by default,
    /// for the same reason as AppleScript automation.
    public var shortcutsAutomationEnabled: Bool {
        didSet { defaults.set(shortcutsAutomationEnabled, forKey: Keys.shortcutsEnabled) }
    }

    /// Whether to show a confirmation alert after a successful Add. Off by
    /// default — the file list already reflects the change; errors always
    /// show regardless. Each in-place edit action has its own independent
    /// toggle rather than one combined switch.
    public var notifyOnAdd: Bool {
        didSet { defaults.set(notifyOnAdd, forKey: Keys.notifyOnAdd) }
    }

    /// Whether to show a confirmation alert after a successful Delete.
    public var notifyOnDelete: Bool {
        didSet { defaults.set(notifyOnDelete, forKey: Keys.notifyOnDelete) }
    }

    /// Whether to show a confirmation alert after a successful Move/Rename.
    public var notifyOnMove: Bool {
        didSet { defaults.set(notifyOnMove, forKey: Keys.notifyOnMove) }
    }

    /// Whether to show a confirmation alert after a successful Copy.
    public var notifyOnCopy: Bool {
        didSet { defaults.set(notifyOnCopy, forKey: Keys.notifyOnCopy) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaultFormat = (defaults.string(forKey: Keys.format)
            .flatMap(ArchiveFormat.init(rawValue:))) ?? .sevenZip
        self.defaultLevel = (defaults.object(forKey: Keys.level) as? Int)
            .flatMap(CompressionLevel.init(rawValue:)) ?? .normal
        self.defaultEncryptFileNames = defaults.bool(forKey: Keys.encryptNames)
        // Default these two "on" when unset (first launch).
        self.extractIntoSubfolder = defaults.object(forKey: Keys.subfolder) as? Bool ?? true
        self.defaultOverwritePolicy = (defaults.string(forKey: Keys.overwritePolicy)
            .flatMap(ExtractionRequest.OverwritePolicy.init(rawValue:))) ?? .overwrite
        self.revealInFinderWhenDone = defaults.object(forKey: Keys.reveal) as? Bool ?? true
        // Off by default: extraction finishes quietly, no completion dialog.
        self.confirmAfterExtraction = defaults.bool(forKey: Keys.confirmExtraction)
        // Off by default (hidden entries hidden) when unset.
        self.showHiddenEntries = defaults.object(forKey: Keys.showHidden) as? Bool ?? false
        // All associable formats "on" by default when unset (first launch),
        // except ISO/DMG/PKG — those override macOS's built-in mount/install
        // behavior, so they default off and require an explicit opt-in.
        self.associatedFormatKeys = (defaults.array(forKey: Keys.associations) as? [String])
            .map(Set.init) ?? AssociableFormat.allKeys.subtracting(["iso", "dmg", "pkg"])
        self.originalHandlerPaths = (defaults.dictionary(forKey: Keys.originalHandlers) as? [String: String]) ?? [:]
        self.hasShownFileTypesOnboarding = defaults.bool(forKey: Keys.fileTypesOnboardingShown)
        // Automation is opt-in: off by default when unset.
        self.appleScriptAutomationEnabled = defaults.bool(forKey: Keys.appleScriptEnabled)
        self.shortcutsAutomationEnabled = defaults.bool(forKey: Keys.shortcutsEnabled)
        // Off by default: no popup for every successful edit. (Test always
        // notifies — that one isn't user-configurable, see ContentView.)
        self.notifyOnAdd = defaults.bool(forKey: Keys.notifyOnAdd)
        self.notifyOnDelete = defaults.bool(forKey: Keys.notifyOnDelete)
        self.notifyOnMove = defaults.bool(forKey: Keys.notifyOnMove)
        self.notifyOnCopy = defaults.bool(forKey: Keys.notifyOnCopy)
    }

    private enum Keys {
        static let format = "defaultFormat"
        static let level = "defaultLevel"
        static let encryptNames = "defaultEncryptFileNames"
        static let subfolder = "extractIntoSubfolder"
        static let overwritePolicy = "defaultOverwritePolicy"
        static let reveal = "revealInFinderWhenDone"
        static let confirmExtraction = "confirmAfterExtraction"
        static let showHidden = "showHiddenEntries"
        static let associations = "associatedFormatKeys"
        static let originalHandlers = "originalHandlerPaths"
        static let fileTypesOnboardingShown = "hasShownFileTypesOnboarding"
        static let appleScriptEnabled = "appleScriptAutomationEnabled"
        static let shortcutsEnabled = "shortcutsAutomationEnabled"
        static let notifyOnAdd = "notifyOnAdd"
        static let notifyOnDelete = "notifyOnDelete"
        static let notifyOnMove = "notifyOnMove"
        static let notifyOnCopy = "notifyOnCopy"
    }
}
