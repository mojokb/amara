import SwiftUI

/// Sheet shown at launch once AgentPathResolver finishes.
/// Displays resolved paths for claude and codex, or install hints if missing.
struct AgentStatusView: View {
    @ObservedObject var resolver: AgentPathResolver
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 420)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: overallIcon)
                .font(.title2)
                .foregroundStyle(overallColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Setup")
                    .font(.headline)
                Text(overallSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var overallIcon: String {
        if resolver.isChecking            { return "magnifyingglass" }
        if resolver.missingAgents.isEmpty { return "checkmark.seal.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var overallColor: Color {
        if resolver.isChecking            { return .secondary }
        if resolver.missingAgents.isEmpty { return .green }
        return .yellow
    }

    private var overallSubtitle: String {
        if resolver.isChecking            { return "Searching your shell PATH…" }
        if resolver.missingAgents.isEmpty { return "Both agents are ready." }
        let names = resolver.missingAgents.joined(separator: " and ")
        return "\(names) could not be found."
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            agentRow("claude", status: resolver.claude)
            agentRow("codex",  status: resolver.codex)

            if !resolver.missingAgents.isEmpty && !resolver.isChecking {
                Divider()
                installHints
            }
        }
        .padding(20)
    }

    private func agentRow(_ name: String, status: AgentPathResolver.Status) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                switch status {
                case .checking:
                    ProgressView().controlSize(.small).frame(width: 20)
                case .found:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                case .notFound:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title3)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                switch status {
                case .checking:
                    Text("checking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .found(let path):
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                case .notFound:
                    Text("not found in PATH or known install locations")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Install hints

    private var installHints: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Installation")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(resolver.missingAgents, id: \.self) { agent in
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(installCommand(for: agent))
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 5))
                        .textSelection(.enabled)
                }
            }

            Text("After installing, click Retry or relaunch Amara.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    private func installCommand(for agent: String) -> String {
        switch agent {
        case "claude": return "npm install -g @anthropic-ai/claude-code"
        case "codex":  return "npm install -g @openai/codex"
        default:       return "# install \(agent) via npm or your package manager"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            if resolver.isChecking {
                ProgressView().controlSize(.small).padding(.trailing, 4)
                Text("Searching…").font(.caption).foregroundStyle(.secondary)
            } else if !resolver.missingAgents.isEmpty {
                Button("Retry") {
                    resolver.resolve()
                }
            }
            Button(resolver.missingAgents.isEmpty ? "Continue" : "Skip") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(resolver.isChecking)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
