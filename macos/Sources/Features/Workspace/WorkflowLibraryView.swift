import SwiftUI

/// Sheet for browsing, editing, and running workflow templates.
struct WorkflowLibraryView: View {
    @ObservedObject var library = WorkflowLibrary.shared
    @EnvironmentObject var manager: WorkspaceManager
    var worktreePath: String

    @State private var editingGraph: WorkflowGraph? = nil
    @State private var showingEditor = false
    @State private var runningGraph: WorkflowGraph? = nil
    @State private var showingPrompt = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let runner = manager.runner(for: worktreePath) {
                WorkflowStatusPanel(runner: runner, worktreePath: worktreePath)
                    .environmentObject(manager)
                Divider()
            }
            list
        }
        .sheet(isPresented: $showingPrompt) {
            if let graph = runningGraph {
                WorkflowPromptView(graph: graph) { prompt in
                    manager.runWorkflow(graph, prompt: prompt, inPath: worktreePath)
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let graph = editingGraph {
                WorkflowEditorSheet(
                    graph: graph,
                    worktreePath: worktreePath,
                    onSave: { saved in
                        if !WorkflowGraph.templates.contains(where: { $0.id == saved.id }) {
                            library.save(saved)
                        }
                        dismiss()
                    },
                    onRun: { g, prompt in
                        manager.runWorkflow(g, prompt: prompt, inPath: worktreePath)
                        dismiss()
                    }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Workflow Templates")
                .font(.headline)
            Spacer()
            Button {
                editingGraph = WorkflowGraph(name: "New Workflow")
                showingEditor = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("Create new workflow")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - List

    private var list: some View {
        List {
            Section("Built-in") {
                ForEach(WorkflowGraph.templates) { graph in
                    templateRow(graph, isCustom: false)
                }
            }
            if !library.custom.isEmpty {
                Section("Custom") {
                    ForEach(library.custom) { graph in
                        templateRow(graph, isCustom: true)
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { library.delete(library.custom[$0]) }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func templateRow(_ graph: WorkflowGraph, isCustom: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(graph.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Text("\(graph.nodes.count) nodes · \(graph.edges.count) edges")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            // Edit
            Button {
                editingGraph = graph
                showingEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Edit")

            // Run — opens prompt sheet
            Button {
                runningGraph = graph
                showingPrompt = true
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .help("Run now")
        }
        .padding(.vertical, 2)
    }

}

// MARK: - Execution status panel

struct WorkflowStatusPanel: View {
    @ObservedObject var runner: WorkflowRunner
    var worktreePath: String
    @EnvironmentObject var manager: WorkspaceManager
    @State private var pulse = false

    private var activeNode: WorkflowNode? {
        runner.graph.nodes.first { runner.activeNodeIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))
                Text(runner.graph.name)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.semibold)
                Spacer()
                if runner.isRunning {
                    Button("Stop") { manager.stopWorkflow(inPath: worktreePath) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                } else {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Node flow
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(runner.graph.nodes.enumerated()), id: \.element.id) { idx, node in
                        nodeChip(node)
                        if idx < runner.graph.nodes.count - 1 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 10)

            // Live output for the currently active node
            if let node = activeNode,
               let session = manager.workspaces[worktreePath]?.session(for: node.agent) {
                Divider()
                LiveOutputView(session: session, node: node) {
                    // Jump to agent tab
                    manager.workspaces[worktreePath]?.activeTab =
                        node.agent == .claude ? .claude : .codex
                }
            }
        }
        .background(Color.orange.opacity(0.05))
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
    }

    private func nodeChip(_ node: WorkflowNode) -> some View {
        let isActive   = runner.activeNodeIds.contains(node.id)
        let isDone     = runner.completedNodeIds.contains(node.id)
        let color: Color = node.agent == .claude ? .blue : .green

        return HStack(spacing: 4) {
            if isDone {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if isActive {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.yellow)
                    .opacity(pulse ? 1.0 : 0.35)
            } else {
                Image(systemName: "circle").foregroundStyle(.tertiary)
            }
            Text(node.agent.label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isActive ? .primary : isDone ? color : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(isActive ? 0.18 : isDone ? 0.1 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isActive ? Color.yellow.opacity(pulse ? 0.9 : 0.4) : color.opacity(isDone ? 0.4 : 0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Live output view

struct LiveOutputView: View {
    @ObservedObject var session: AgentSession
    let node: WorkflowNode
    var onJumpToTab: () -> Void

    private var recentLines: String {
        // Strip all common ANSI / VT escape sequences, then handle \r overwrites.
        let ansiPattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07]*\x07)"#
        let stripped = session.outputBuffer
            .replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
        // For each raw line, \r moves to column 0 — keep only the final segment.
        let lines = stripped.components(separatedBy: "\n").flatMap { rawLine -> [String] in
            let segments = rawLine.components(separatedBy: "\r")
            let resolved = segments.last ?? rawLine
            return [resolved.trimmingCharacters(in: .whitespaces)]
        }
        .filter { $0.count > 1 }
        return lines.suffix(6).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                let color: Color = node.agent == .claude ? .blue : .green
                Image(systemName: node.agent.systemImage)
                    .foregroundStyle(color)
                    .font(.system(size: 10))
                Text("\(node.agent.label) · live output")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onJumpToTab()
                } label: {
                    Label("View in tab", systemImage: "arrow.up.right.square")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Text(recentLines.isEmpty ? "Waiting for output…" : recentLines)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(recentLines.isEmpty ? .tertiary : .primary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Editor sheet

struct WorkflowEditorSheet: View {
    @State var graph: WorkflowGraph
    var worktreePath: String
    var onSave: (WorkflowGraph) -> Void
    var onRun:  (WorkflowGraph, String) -> Void

    @EnvironmentObject var manager: WorkspaceManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingPromptInEditor = false

    var body: some View {
        VStack(spacing: 0) {
            sheetToolbar
            Divider()
            editorContent
        }
        .frame(width: 720, height: 480)
        .sheet(isPresented: $showingPromptInEditor) {
            WorkflowPromptView(graph: graph) { prompt in
                onRun(graph, prompt)
            }
        }
    }

    private var sheetToolbar: some View {
        HStack {
            TextField("Workflow name", text: $graph.name)
                .textFieldStyle(.plain)
                .font(.system(.headline, design: .monospaced))
                .frame(maxWidth: 240)

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Save") { onSave(graph) }
                .buttonStyle(.bordered)

            Button("Save & Run") { onSave(graph); showingPromptInEditor = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var editorContent: some View {
        let workspace = manager.workspaces[worktreePath]
        let runner: WorkflowRunner? = workspace.map {
            manager.runner(for: worktreePath) ?? WorkflowRunner(graph: graph, workspace: $0)
        }
        return Group {
            if let runner {
                WorkflowEditorView(
                    graph: $graph,
                    runner: runner,
                    onRun:  { prompt in manager.runWorkflow(graph, prompt: prompt, inPath: worktreePath) },
                    onStop: { manager.stopWorkflow(inPath: worktreePath) }
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "square.dashed")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Select this worktree first, then open the editor.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
