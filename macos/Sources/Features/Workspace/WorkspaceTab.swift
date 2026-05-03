import Foundation

/// Identifies a tab within the workspace right panel.
enum WorkspaceTab: Hashable, Identifiable {
    case claude
    case codex
    case workflow
    case file(URL)

    var id: String {
        switch self {
        case .claude:        return "claude"
        case .codex:         return "codex"
        case .workflow:      return "workflow"
        case .file(let url): return url.path
        }
    }

    var displayName: String {
        switch self {
        case .claude:        return "claude"
        case .codex:         return "codex"
        case .workflow:      return "workflow"
        case .file(let url): return url.lastPathComponent
        }
    }
}
