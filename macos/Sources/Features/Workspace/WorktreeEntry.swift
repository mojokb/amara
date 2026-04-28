import Foundation

/// A single git worktree entry parsed from `git worktree list --porcelain`.
struct WorktreeEntry: Identifiable {
    let path: String
    let branch: String
    let isBare: Bool
    let isLocked: Bool
    /// PR info fetched from Gitea. nil = no PR or Gitea not configured.
    var prInfo: PRInfo? = nil

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

extension WorktreeEntry: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.path == rhs.path }
}
