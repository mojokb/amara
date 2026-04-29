import Foundation

/// A configured output route between two agents in the same worktree.
struct AgentRoute: Identifiable {
    let id: UUID
    let worktreePath: String
    let from: AgentKind
    let to: AgentKind
    /// If true, fires automatically each time the source agent goes idle.
    /// If false, was a one-shot manual trigger (kept for history, not active).
    let isAuto: Bool
}
