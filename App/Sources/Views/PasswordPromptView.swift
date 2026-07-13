import SwiftUI

/// Sheet shown when an encrypted archive needs a password to open.
struct PasswordPromptView: View {
    let archiveName: String
    let showError: Bool
    let attemptCount: Int
    let maxAttempts: Int
    let onUnlock: (_ password: String) -> Void
    let onCancel: () -> Void

    @State private var password = ""

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

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(unlock)

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
                    .disabled(password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        onUnlock(password)
    }
}
