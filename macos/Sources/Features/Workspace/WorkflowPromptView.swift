import SwiftUI

/// Sheet shown when the user clicks "Run" on a workflow.
/// Collects the initial prompt that will be sent to root node(s).
struct WorkflowPromptView: View {
    let graph: WorkflowGraph
    var onRun: (String) -> Void

    @State private var prompt = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var rootAgents: [AgentKind] {
        let rootNodes = graph.nodes.filter { node in
            !graph.edges.contains { $0.toId == node.id }
        }
        return rootNodes.map { $0.agent }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            promptArea
            Divider()
            footer
        }
        .frame(width: 480)
        .onAppear { focused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(graph.name)
                    .font(.headline)
                Text("초기 프롬프트를 입력하면 \(rootAgentLabel)에 자동으로 전송됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var rootAgentLabel: String {
        rootAgents.map { $0.label }.joined(separator: ", ")
    }

    // MARK: - Prompt area

    private var promptArea: some View {
        TextEditor(text: $prompt)
            .font(.system(.body, design: .monospaced))
            .focused($focused)
            .frame(height: 140)
            .padding(12)
            .overlay(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("예: 로그인 기능을 설계하고 구현해줘")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Flow preview
            HStack(spacing: 4) {
                ForEach(Array(graph.nodes.enumerated()), id: \.offset) { idx, node in
                    let color: Color = node.agent == .claude ? .blue : .green
                    Text(node.agent.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                    if idx < graph.nodes.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Run") {
                onRun(prompt)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
