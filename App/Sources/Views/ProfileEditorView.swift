import SwiftUI
import SevenZipKit

/// Create/edit/view sheet for a compression profile, opened from
/// Preferences ▸ Profiles. Built-in profiles are shown read-only (their
/// fields disabled, no Save/Delete) since they ship with the app; custom
/// profiles are fully editable.
struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let profileStore: ProfileStore

    private let editingID: UUID?
    private let isReadOnly: Bool

    @State private var name: String
    @State private var format: ArchiveFormat
    @State private var level: CompressionLevel
    @State private var encryptFileNames: Bool
    @State private var requiresPassword: Bool
    @State private var splitPreset: VolumePreset

    /// - Parameter profile: The profile to view/edit, or nil to create a new one.
    init(profile: CompressionProfile?, profileStore: ProfileStore) {
        self.profileStore = profileStore
        self.editingID = profile?.id
        self.isReadOnly = profile?.isBuiltIn ?? false
        _name = State(initialValue: profile?.name ?? "New Profile")
        _format = State(initialValue: profile?.format ?? .sevenZip)
        _level = State(initialValue: profile?.level ?? .normal)
        _encryptFileNames = State(initialValue: profile?.encryptFileNames ?? false)
        _requiresPassword = State(initialValue: profile?.requiresPassword ?? false)
        _splitPreset = State(initialValue: VolumePreset.matching(profile?.volumeSize))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isReadOnly ? name : (editingID == nil ? "New Profile" : "Edit Profile"))
                .font(.title2.weight(.semibold))
                .padding(20)

            Form {
                Section {
                    if isReadOnly {
                        LabeledContent("Name", value: name)
                    } else {
                        TextField("Name", text: $name)
                    }
                }
                Section {
                    Picker("Format", selection: $format) {
                        ForEach(ArchiveFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Compression", selection: $level) {
                        ForEach(CompressionLevel.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Split", selection: $splitPreset) {
                        ForEach(VolumePreset.allCases) { Text($0.label).tag($0) }
                    }
                }
                .disabled(isReadOnly)

                Section("Encryption") {
                    Toggle("Requires a password when used", isOn: $requiresPassword)
                    Toggle("Encrypt file names", isOn: $encryptFileNames)
                        .disabled(!format.supportsEncryptedHeaders)
                }
                .disabled(isReadOnly)

                if isReadOnly {
                    Section {
                        Text("Built-in profiles can't be edited or deleted. Create a custom one to change these settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button(isReadOnly ? "Done" : "Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !isReadOnly {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
        }
        .frame(width: 420)
    }

    private func save() {
        let profile = CompressionProfile(
            id: editingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            format: format,
            level: level,
            encryptFileNames: encryptFileNames,
            requiresPassword: requiresPassword,
            volumeSize: splitPreset.bytes,
            isBuiltIn: false
        )
        profileStore.add(profile)
        dismiss()
    }
}
