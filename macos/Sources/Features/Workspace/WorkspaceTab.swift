import Foundation

/// Identifies a tab within the workspace right panel.
enum WorkspaceTab: Hashable, Identifiable {
    case claude
    case codex
    case file(URL)
    case web(UUID)

    var id: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .file(let url): return url.path
        case .web(let id): return "web-\(id)"
        }
    }

    var displayName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .file(let url): return url.lastPathComponent
        case .web: return "Web"
        }
    }
}
