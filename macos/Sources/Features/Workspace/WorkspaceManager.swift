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

    /// Resolves claude/codex paths via the user's login shell.
    let resolver = AgentPathResolver()

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
        resolver.resolve()
    }

    // MARK: - Selection

    func select(path: String) {
        if workspaces[path] == nil {
            guard let app = ghostty.app else { return }
            // Use resolved full paths when available; fall back to login-shell
            // invocation so PATH is sourced from the user's shell config.
            let claudeCmd = resolver.claudeCommand ?? "/bin/zsh -l -c 'source ~/.zshrc 2>/dev/null; exec claude'"
            let codexCmd  = resolver.codexCommand  ?? "/bin/zsh -l -c 'source ~/.zshrc 2>/dev/null; exec codex'"
            workspaces[path] = WorktreeWorkspace(
                path: path,
                ghosttyApp: app,
                claudeCommand: claudeCmd,
                codexCommand: codexCmd
            )
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

    // MARK: - Worktree creation

    /// Creates a new worktree at `<repo-parent>/<branch>` on a new branch and refreshes the list.
    func createWorktree(branch: String) async throws {
        guard let repoPath = repositoryPath else { return }
        let worktreePath = URL(fileURLWithPath: repoPath)
            .deletingLastPathComponent()
            .appendingPathComponent(branch)
            .path
        try await Task.detached(priority: .userInitiated) {
            try Self.gitWorktreeAdd(repoPath: repoPath, branch: branch, worktreePath: worktreePath)
        }.value
        worktreeProvider.refresh(for: repoPath)
    }

    private nonisolated static func gitWorktreeAdd(repoPath: String, branch: String, worktreePath: String) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", repoPath, "worktree", "add", "-b", branch, worktreePath]
        proc.standardOutput = Pipe()
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "git", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: msg.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }
}
