import SwiftUI
import SevenZipKit

/// The Preferences window (⌘,). Presentational — it edits ``AppSettings``.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var profileStore: ProfileStore
    @State private var editingProfile: ProfileTarget?

    /// What `profilesTab`'s sheet is showing: a brand-new profile, or an
    /// existing one to view/edit. Wrapped so `.sheet(item:)` (which needs
    /// `Identifiable`) can drive it directly.
    private enum ProfileTarget: Identifiable {
        case new
        case existing(CompressionProfile)

        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let profile): return profile.id.uuidString
            }
        }

        var profile: CompressionProfile? {
            if case .existing(let profile) = self { return profile }
            return nil
        }
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            compressionTab
                .tabItem { Label("Compression", systemImage: "archivebox") }
            profilesTab
                .tabItem { Label("Profiles", systemImage: "slider.horizontal.3") }
            associationsTab
                .tabItem { Label("File Types", systemImage: "doc.badge.gearshape") }
            automationTab
                .tabItem { Label("Automation", systemImage: "wand.and.stars") }
        }
        .frame(width: 460)
        .padding(.vertical, 8)
    }

    // MARK: - Automation

    private var automationTab: some View {
        Form {
            Section {
                Text("Let other apps and scripts drive 7ZIP4MAC. Both are off by default: they open a way to compress/extract without any visible window, so turn them on only if you actually use them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("AppleScript") {
                Toggle("Enable AppleScript commands", isOn: $settings.appleScriptAutomationEnabled)
                Text("Adds `compress` and `extract` commands, usable from Script Editor, osascript, or Automator.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("Shortcuts & Siri") {
                Toggle("Enable Shortcuts actions", isOn: $settings.shortcutsAutomationEnabled)
                Text("Adds “Compress Files” and “Extract Archive” actions to the Shortcuts app, and matching Siri phrases.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - File type associations

    private var associationsTab: some View {
        Form {
            Section {
                Text("Choose which file types open in 7ZIP4MAC by default when double-clicked in Finder. Associating ISO/DMG/PKG overrides macOS's built-in mount/install behavior for those, so they default off — turn them on only if that's what you want.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("macOS asks you to confirm each format individually — turning one on (or using “Associate All”) shows a system dialog per format (“Do you want .zip files to open with 7ZIP4MAC?”). There's no way to un-associate a format from here; turning a toggle off just stops it from being offered — change the default back via Finder ▸ Get Info ▸ Open With if needed.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                HStack {
                    Button("Associate All…") { setAll(true) }
                    Button("Clear Toggles") { setAll(false) }
                    Spacer()
                }
            }
            ForEach(AssociableFormat.Tier.allCases, id: \.self) { tier in
                Section(tier.rawValue) {
                    ForEach(AssociableFormat.all.filter { $0.tier == tier }) { format in
                        Toggle(isOn: bindingFor(format)) {
                            Label {
                                Text(format.displayName)
                            } icon: {
                                Circle().fill(color(for: tier)).frame(width: 10, height: 10)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func bindingFor(_ format: AssociableFormat) -> Binding<Bool> {
        Binding(
            get: { settings.associatedFormatKeys.contains(format.key) },
            set: { isOn in
                if isOn {
                    settings.associatedFormatKeys.insert(format.key)
                    Task { await FileAssociationService.associate(format) }
                } else {
                    settings.associatedFormatKeys.remove(format.key)
                }
            }
        )
    }

    private func setAll(_ on: Bool) {
        if on {
            settings.associatedFormatKeys = AssociableFormat.allKeys
            Task { await FileAssociationService.associate(all: AssociableFormat.all) }
        } else {
            settings.associatedFormatKeys = []
        }
    }

    private func color(for tier: AssociableFormat.Tier) -> Color {
        switch tier {
        case .common: return .blue
        case .lessCommon: return .orange
        case .diskImage: return .yellow
        }
    }

    private var profilesTab: some View {
        Form {
            Section {
                Button("New Profile…") { editingProfile = .new }
            }
            Section("Profiles") {
                ForEach(profileStore.all) { profile in
                    Button { editingProfile = .existing(profile) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                Text(profileSummary(profile))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.isBuiltIn {
                                Text("Built-in").font(.caption).foregroundStyle(.tertiary)
                            } else {
                                Button(role: .destructive) {
                                    profileStore.delete(profile)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingProfile) { target in
            ProfileEditorView(profile: target.profile, profileStore: profileStore)
        }
    }

    private func profileSummary(_ p: CompressionProfile) -> String {
        var parts = [p.format.displayName, p.level.displayName]
        if p.requiresPassword { parts.append("encrypted") }
        if let v = p.volumeSize { parts.append("split \(ByteFormatter.string(fromByteCount: Int64(v)))") }
        return parts.joined(separator: " · ")
    }

    private var generalTab: some View {
        Form {
            Section("Extraction") {
                Toggle("Extract into a subfolder named after the archive",
                       isOn: $settings.extractIntoSubfolder)
                Toggle("Show a dialog when extraction finishes",
                       isOn: $settings.confirmAfterExtraction)
                Text("The dialog offers a “Show in Finder” button. Errors are always shown regardless.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section {
                Toggle("Reveal in Finder when finished", isOn: $settings.revealInFinderWhenDone)
            }
            Section("Browsing") {
                Toggle("Show hidden items (.DS_Store, __MACOSX, dotfiles…)",
                       isOn: $settings.showHiddenEntries)
            }
            Section("Notifications") {
                Toggle("Confirm after Add", isOn: $settings.notifyOnAdd)
                Toggle("Confirm after Delete", isOn: $settings.notifyOnDelete)
                Toggle("Confirm after Move/Rename", isOn: $settings.notifyOnMove)
                Toggle("Confirm after Copy", isOn: $settings.notifyOnCopy)
                Text("Test always confirms — its result isn't visible anywhere else. Errors are always shown regardless of these toggles.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    private var compressionTab: some View {
        Form {
            Section("Defaults for new archives") {
                Picker("Format", selection: $settings.defaultFormat) {
                    ForEach(ArchiveFormat.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Compression", selection: $settings.defaultLevel) {
                    ForEach(CompressionLevel.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Encrypt file names when a password is set",
                       isOn: $settings.defaultEncryptFileNames)
            }
        }
        .formStyle(.grouped)
    }
}
