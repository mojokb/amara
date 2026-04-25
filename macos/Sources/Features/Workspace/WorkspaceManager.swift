import Foundation
import Combine
import AmaraKit

/// Owns all per-worktree state for the workspace window.
/// Always accessed from the main actor (SwiftUI/AppKit context).
@MainActor
final class WorkspaceManager: ObservableObject {
    let ghostty: Amara.App

    /// The git-subprocess helper for listing worktrees.
    let worktreeProvider = WorktreeProvider()

    /// Root directory used for `git worktree list`. nil = not yet configured.
    @Published private(set) var repositoryPath: String?

    /// Per-path workspace state. Key = canonical worktree path.
    @Published private(set) var workspaces: [String: WorktreeWorkspace] = [:]

    /// The path of the currently selected worktree.
    @Published var selectedPath: String?

    var selectedWorkspace: WorktreeWorkspace? {
        guard let path = selectedPath else { return nil }
        return workspaces[path]
    }

    private var providerCancellable: AnyCancellable?

    init(ghostty: Amara.App) {
        self.ghostty = ghostty
        // Forward worktreeProvider changes so SwiftUI views using this manager re-render.
        providerCancellable = worktreeProvider.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    // MARK: - Selection

    func select(path: String) {
        if workspaces[path] == nil {
            guard let app = ghostty.app else { return }
            workspaces[path] = WorktreeWorkspace(path: path, ghosttyApp: app)
        }
        selectedPath = path
    }

    func remove(path: String) {
        workspaces.removeValue(forKey: path)
        if selectedPath == path {
            selectedPath = workspaces.keys.first
        }
    }

    // MARK: - Repository

    func setRepository(path: String) {
        repositoryPath = path
        worktreeProvider.refresh(for: path)
    }

    func refreshWorktrees() {
        guard let path = repositoryPath else { return }
        worktreeProvider.refresh(for: path)
    }
}
