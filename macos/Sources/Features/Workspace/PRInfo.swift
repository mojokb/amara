import SwiftUI

enum PRState: String, Hashable {
    case open, draft, merged, closed

    var color: Color {
        switch self {
        case .open:   return .green
        case .draft:  return .secondary
        case .merged: return .purple
        case .closed: return .red
        }
    }

    var icon: String {
        switch self {
        case .open:   return "arrow.triangle.pull"
        case .draft:  return "doc.text"
        case .merged: return "arrow.triangle.merge"
        case .closed: return "xmark.circle"
        }
    }
}

struct PRInfo: Hashable {
    let number: Int
    let title: String
    let state: PRState
    let webURL: String
    /// Head branch — used internally to match worktree branches.
    let headBranch: String
}
