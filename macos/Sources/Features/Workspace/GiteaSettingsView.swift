import SwiftUI

/// Sheet for entering Gitea server URL and personal access token.
struct GiteaSettingsView: View {
    @State private var serverURL = GiteaCredentials.serverURL
    @State private var token     = GiteaCredentials.token
    @Environment(\.dismiss) private var dismiss

    var onSave: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gitea Integration")
                .font(.headline)

            VStack(alignment: .leading, spacing: 5) {
                Text("Server URL")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("https://gitea.example.com", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Personal Access Token")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("token…", text: $token)
                    .textFieldStyle(.roundedBorder)
                Text("Settings → Applications → Generate Token  (scope: issues, pull-requests)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(serverURL.trimmingCharacters(in: .whitespaces).isEmpty ||
                              token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func save() {
        GiteaCredentials.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        GiteaCredentials.token     = token.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave?()
        dismiss()
    }
}
