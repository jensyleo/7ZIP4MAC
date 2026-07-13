import SwiftUI
import SevenZipKit

/// Split-size presets offered in the New Archive sheet.
enum VolumePreset: CaseIterable, Identifiable {
    case none, mb100, cd700, fat4000, dvd4700

    var id: Self { self }

    private static let miB: UInt64 = 1024 * 1024

    var bytes: UInt64? {
        switch self {
        case .none: return nil
        case .mb100: return 100 * Self.miB
        case .cd700: return 700 * Self.miB
        case .fat4000: return 4000 * Self.miB
        case .dvd4700: return 4700 * Self.miB
        }
    }

    var label: String {
        switch self {
        case .none: return "Don't split"
        case .mb100: return "100 MB"
        case .cd700: return "CD — 700 MB"
        case .fat4000: return "FAT32 — 4 GB"
        case .dvd4700: return "DVD — 4.7 GB"
        }
    }

    static func matching(_ bytes: UInt64?) -> VolumePreset {
        allCases.first { $0.bytes == bytes } ?? .none
    }
}

/// The sheet where the user configures a new archive: profile, format,
/// compression level, encryption and splitting.
struct CompressionOptionsView: View {
    @Bindable var viewModel: CompressionViewModel
    @Bindable var profileStore: ProfileStore
    let onCreate: () -> Void
    let onCancel: () -> Void

    @State private var selectedProfileID: CompressionProfile.ID?
    @State private var isSavingProfile = false
    @State private var newProfileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Archive")
                .font(.title2.weight(.semibold))
                .padding(20)

            Form {
                Section {
                    LabeledContent("Items") {
                        Text(sourcesSummary).foregroundStyle(.secondary)
                    }
                    Picker("Profile", selection: $selectedProfileID) {
                        Text("Custom").tag(CompressionProfile.ID?.none)
                        Divider()
                        ForEach(profileStore.all) { profile in
                            Text(profile.name).tag(CompressionProfile.ID?.some(profile.id))
                        }
                    }
                    .onChange(of: selectedProfileID) { _, id in
                        if let id, let profile = profileStore.profile(id: id) {
                            viewModel.apply(profile)
                        }
                    }
                }

                Section {
                    Picker("Format", selection: $viewModel.format) {
                        ForEach(ArchiveFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Compression", selection: $viewModel.level) {
                        ForEach(CompressionLevel.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Split", selection: volumeBinding) {
                        ForEach(VolumePreset.allCases) { Text($0.label).tag($0) }
                    }
                }

                if viewModel.format.supportsPassword {
                    Section("Encryption") {
                        SecureField("Password (optional)", text: $viewModel.password)
                        if viewModel.format.supportsEncryptedHeaders {
                            Toggle("Encrypt file names", isOn: $viewModel.encryptFileNames)
                                .disabled(viewModel.password.isEmpty)
                        }
                    }
                }

                Section {
                    Button("Save these settings as a profile…") { isSavingProfile = true }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create…", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 480)
        .alert("Save Profile", isPresented: $isSavingProfile) {
            TextField("Profile name", text: $newProfileName)
            Button("Save") {
                let name = newProfileName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { profileStore.add(viewModel.currentProfile(named: name)) }
                newProfileName = ""
            }
            Button("Cancel", role: .cancel) { newProfileName = "" }
        } message: {
            Text("Save the current format, level, encryption and split settings as a reusable profile.")
        }
    }

    private var volumeBinding: Binding<VolumePreset> {
        Binding(
            get: { VolumePreset.matching(viewModel.volumeSize) },
            set: { viewModel.volumeSize = $0.bytes }
        )
    }

    private var sourcesSummary: String {
        viewModel.sources.count == 1
            ? viewModel.sources[0].lastPathComponent
            : "\(viewModel.sources.count) items"
    }
}
