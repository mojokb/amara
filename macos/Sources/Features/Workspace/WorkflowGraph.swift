import Foundation
import CoreGraphics

struct WorkflowNode: Identifiable, Codable, Equatable {
    var id = UUID()
    var agent: AgentKind
    var position: CGPoint
    var instruction: String = ""

    static let size = CGSize(width: 140, height: 52)
    static let portHitRadius: CGFloat = 14

    var outputPort: CGPoint { CGPoint(x: position.x + Self.size.width / 2, y: position.y) }
    var inputPort:  CGPoint { CGPoint(x: position.x - Self.size.width / 2, y: position.y) }

    func contains(_ p: CGPoint) -> Bool {
        abs(p.x - position.x) <= Self.size.width  / 2 &&
        abs(p.y - position.y) <= Self.size.height / 2
    }

    func isNearOutputPort(_ p: CGPoint) -> Bool {
        hypot(p.x - outputPort.x, p.y - outputPort.y) <= Self.portHitRadius
    }
}

struct WorkflowEdge: Identifiable, Codable, Equatable {
    var id = UUID()
    var fromId: UUID
    var toId: UUID
}

struct WorkflowGraph: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var nodes: [WorkflowNode] = []
    var edges: [WorkflowEdge] = []

    mutating func addNode(agent: AgentKind, at position: CGPoint) {
        nodes.append(WorkflowNode(agent: agent, position: position))
    }

    mutating func addEdge(from fromId: UUID, to toId: UUID) {
        guard fromId != toId,
              !edges.contains(where: { $0.fromId == fromId && $0.toId == toId })
        else { return }
        edges.append(WorkflowEdge(fromId: fromId, toId: toId))
    }

    mutating func remove(nodeId: UUID) {
        nodes.removeAll { $0.id == nodeId }
        edges.removeAll { $0.fromId == nodeId || $0.toId == nodeId }
    }

    mutating func remove(edgeId: UUID) {
        edges.removeAll { $0.id == edgeId }
    }

    // MARK: - Built-in templates

    static var templates: [WorkflowGraph] {
        var g1 = WorkflowGraph(name: "Design → Implement")
        var c1 = WorkflowNode(agent: .claude, position: CGPoint(x: 160, y: 180))
        c1.instruction = "You are a software architect. Analyze the user's request and produce a clear design specification: component breakdown, data models, API contracts, and key decisions. Be concise and implementation-ready."
        var x1 = WorkflowNode(agent: .codex, position: CGPoint(x: 400, y: 180))
        x1.instruction = "You are a software engineer. Implement the design specification below. Write clean, working code. Do not ask for clarification — implement directly."
        g1.nodes = [c1, x1]
        g1.edges = [WorkflowEdge(fromId: c1.id, toId: x1.id)]

        var g2 = WorkflowGraph(name: "Implement → Review")
        var x2 = WorkflowNode(agent: .codex, position: CGPoint(x: 160, y: 180))
        x2.instruction = "You are a software engineer. Implement the following feature request. Write clean, working code."
        var c2 = WorkflowNode(agent: .claude, position: CGPoint(x: 400, y: 180))
        c2.instruction = "You are a code reviewer. Review the implementation below and provide detailed, actionable feedback on correctness, edge cases, security, performance, and code quality."
        g2.nodes = [x2, c2]
        g2.edges = [WorkflowEdge(fromId: x2.id, toId: c2.id)]

        var g3 = WorkflowGraph(name: "Design → Implement → Review")
        var c3a = WorkflowNode(agent: .claude, position: CGPoint(x: 100, y: 180))
        c3a.instruction = "You are a software architect. Analyze the user's request and produce a clear design specification: component breakdown, data models, API contracts, and key decisions. Be concise and implementation-ready."
        var x3 = WorkflowNode(agent: .codex, position: CGPoint(x: 340, y: 180))
        x3.instruction = "You are a software engineer. Implement the design specification below. Write clean, working code. Do not ask for clarification — implement directly."
        var c3b = WorkflowNode(agent: .claude, position: CGPoint(x: 580, y: 180))
        c3b.instruction = "You are a code reviewer. Review the implementation below and provide detailed, actionable feedback on correctness, edge cases, security, performance, and code quality."
        g3.nodes = [c3a, x3, c3b]
        g3.edges = [WorkflowEdge(fromId: c3a.id, toId: x3.id),
                    WorkflowEdge(fromId: x3.id,  toId: c3b.id)]

        return [g1, g2, g3]
    }
}

// MARK: - Library (persistence)

final class WorkflowLibrary: ObservableObject {
    static let shared = WorkflowLibrary()

    @Published var custom: [WorkflowGraph] = []

    var all: [WorkflowGraph] { WorkflowGraph.templates + custom }

    private let key = "amara.workflows"

    private init() { load() }

    func save(_ graph: WorkflowGraph) {
        if let i = custom.firstIndex(where: { $0.id == graph.id }) {
            custom[i] = graph
        } else {
            custom.append(graph)
        }
        persist()
    }

    func delete(_ graph: WorkflowGraph) {
        custom.removeAll { $0.id == graph.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let graphs = try? JSONDecoder().decode([WorkflowGraph].self, from: data)
        else { return }
        custom = graphs
    }
}
