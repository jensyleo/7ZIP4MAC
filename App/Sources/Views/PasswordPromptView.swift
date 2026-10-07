import SwiftUI

/// Sheet shown when an encrypted archive needs a password to open.
struct PasswordPromptView: View {
    let archiveName: String
    let showError: Bool
    let attemptCount: Int
    let maxAttempts: Int
    /// True while the archive is being re-read with the submitted password.
    var isChecking = false
    let onUnlock: (_ password: String) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Password Required")
                        .font(.headline)
                    Text("“\(archiveName)” is encrypted.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Text("You have \(maxAttempts) attempts. After that, this returns to the empty window.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Group {
                    if isRevealed {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit(unlock)
                .disabled(isChecking)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isRevealed ? "Hide password" : "Show password")
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            }

            if isChecking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking the password… this can take a while on a network volume.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showError {
                let remaining = max(0, maxAttempts - attemptCount)
                Label(
                    "Incorrect password. \(remaining) attempt\(remaining == 1 ? "" : "s") left.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Unlock", action: unlock)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty || isChecking)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func unlock() {
        guard !password.isEmpty, !isChecking else { return }
        onUnlock(password)
    }
}
