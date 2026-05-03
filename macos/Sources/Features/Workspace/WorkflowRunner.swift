import Foundation
import Combine

@MainActor
final class WorkflowRunner: ObservableObject {
    @Published private(set) var activeNodeIds: Set<UUID> = []
    @Published private(set) var completedNodeIds: Set<UUID> = []
    @Published private(set) var isRunning = false

    let graph: WorkflowGraph
    private let workspace: WorktreeWorkspace
    private var cancellables: [UUID: AnyCancellable] = [:]
    private var bufferSnapshots: [UUID: Int] = [:]

    init(graph: WorkflowGraph, workspace: WorktreeWorkspace) {
        self.graph = graph
        self.workspace = workspace
    }

    func start(prompt: String) {
        guard !isRunning else { return }
        isRunning = true
        activeNodeIds = []
        completedNodeIds = []
        bufferSnapshots = [:]

        let roots = graph.nodes.filter { node in
            !graph.edges.contains { $0.toId == node.id }
        }
        roots.forEach { node in
            if !prompt.isEmpty {
                let input = node.instruction.isEmpty
                    ? prompt
                    : node.instruction + "\n\n" + prompt
                sendAndSubmit(input, to: node.agent)
            }
            activate(node)
        }
    }

    func stop() {
        cancellables.values.forEach { $0.cancel() }
        cancellables = [:]
        activeNodeIds = []
        bufferSnapshots = [:]
        isRunning = false
    }

    // Sends multiline text and follows up with an extra Enter after a short delay
    // so claude CLI's paste-detection logic confirms and submits the input.
    private func sendAndSubmit(_ text: String, to agent: AgentKind) {
        let session = workspace.session(for: agent)
        session.send(text + "\n")
        Task { @MainActor [weak session] in
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 s
            session?.send("\n")
        }
    }

    private func activate(_ node: WorkflowNode) {
        activeNodeIds.insert(node.id)
        bufferSnapshots[node.id] = workspace.session(for: node.agent).outputBuffer.count

        cancellables[node.id] = workspace.session(for: node.agent).idlePublisher
            .first()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.activeNodeIds.remove(node.id)
                self.completedNodeIds.insert(node.id)

                let session = self.workspace.session(for: node.agent)
                let snapshotIndex = self.bufferSnapshots[node.id] ?? 0
                let fullOutput = String(session.outputBuffer.dropFirst(snapshotIndex))

                let nexts = self.graph.edges
                    .filter { $0.fromId == node.id }
                    .compactMap { edge in self.graph.nodes.first { $0.id == edge.toId } }

                nexts.forEach { next in
                    let input = next.instruction.isEmpty
                        ? fullOutput
                        : next.instruction + "\n\n" + fullOutput
                    self.sendAndSubmit(input, to: next.agent)
                    self.activate(next)
                }

                if self.activeNodeIds.isEmpty { self.isRunning = false }
            }
    }
}
