import Foundation

enum AgentKind: String, Hashable, CaseIterable {
    case claude, codex

    var label: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .claude: "sparkles"
        case .codex:  "chevron.left.forwardslash.chevron.right"
        }
    }
}
