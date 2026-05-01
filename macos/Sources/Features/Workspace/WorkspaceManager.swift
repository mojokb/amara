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
    private var resolverCancellable: AnyCancellable?
    // One cancellable per live workspace — forwards attention-state changes up to
    // WorkspaceManager so WorkspaceRootView re-renders the sidebar dots.
    private var workspaceCancellables: [String: AnyCancellable] = [:]

    // MARK: - Agent routing

    /// Currently active auto-routes.
    @Published private(set) var routes: [AgentRoute] = []
    private var routeCancellables: [UUID: AnyCancellable] = [:]

    init(ghostty: Amara.App) {
        self.ghostty = ghostty
        // Forward worktreeProvider changes so SwiftUI views using this manager re-render.
        providerCancellable = worktreeProvider.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
        resolverCancellable = resolver.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
        resolver.resolve()

        worktreeProvider.onPRMerged = { [weak self] entry in
            self?.handlePRMerged(entry)
        }
    }

    // MARK: - Selection

    func select(path: String) {
        if workspaces[path] == nil {
            guard let app = ghostty.app else { return }
            // Block workspace creation until both agents are confirmed present.
            guard !resolver.isChecking, resolver.missingAgents.isEmpty,
                  let claudeCmd = resolver.claudeCommand,
                  let codexCmd  = resolver.codexCommand else { return }
            let workspace = WorktreeWorkspace(
                path: path,
                ghosttyApp: app,
                claudeCommand: claudeCmd,
                codexCommand: codexCmd
            )
            workspaces[path] = workspace
            // Forward workspace-level changes (e.g. attention flags) so SwiftUI
            // views that observe WorkspaceManager re-render the sidebar.
            workspaceCancellables[path] = workspace.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
        }
        selectedPath = path
    }

    func remove(path: String) {
        workspaces.removeValue(forKey: path)
        workspaceCancellables.removeValue(forKey: path)
        if selectedPath == path {
            selectedPath = workspaces.keys.first
        }
    }

    // MARK: - File editor

    func openFile(_ url: URL, inWorktreePath worktreePath: String) {
        // Ensure the workspace for this worktree exists (creates it if needed).
        if workspaces[worktreePath] == nil {
            select(path: worktreePath)
        }
        workspaces[worktreePath]?.openFile(url)
        selectedPath = worktreePath
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

    // MARK: - PR merge handling

    /// Non-nil when a PR has just merged and is awaiting user confirmation to remove the worktree.
    @Published private(set) var pendingMergeEntry: WorktreeEntry?

    private func handlePRMerged(_ entry: WorktreeEntry) {
        pendingMergeEntry = entry
    }

    func confirmRemoveMergedWorktree() {
        guard let entry = pendingMergeEntry,
              let repoPath = repositoryPath else {
            pendingMergeEntry = nil
            return
        }
        pendingMergeEntry = nil
        remove(path: entry.path)
        worktreeProvider.refresh(for: repoPath)
        Task.detached(priority: .utility) {
            Self.gitWorktreeRemove(repoPath: repoPath, worktreePath: entry.path)
        }
    }

    func cancelRemoveMergedWorktree() {
        pendingMergeEntry = nil
    }

    // MARK: - Routing API

    /// Immediately sends the source agent's accumulated output to the destination agent.
    func routeNow(from: AgentKind, to: AgentKind, inPath: String) {
        guard let workspace = workspaces[inPath] else { return }
        let output = session(from, in: workspace).outputBuffer
        guard !output.isEmpty else { return }
        session(to, in: workspace).send(output)
    }

    /// Registers an auto-route that fires each time the source agent goes idle.
    /// Replaces any existing auto-route with the same from/to pair in the same worktree.
    @discardableResult
    func addAutoRoute(from: AgentKind, to: AgentKind, inPath: String) -> UUID {
        // Remove duplicate if already registered.
        if let existing = routes.first(where: {
            $0.worktreePath == inPath && $0.from == from && $0.to == to && $0.isAuto
        }) {
            removeRoute(existing.id)
        }

        let route = AgentRoute(id: UUID(), worktreePath: inPath, from: from, to: to, isAuto: true)
        routes.append(route)

        guard let workspace = workspaces[inPath] else { return route.id }
        let dest = session(to, in: workspace)

        routeCancellables[route.id] = session(from, in: workspace).idlePublisher
            .receive(on: RunLoop.main)
            .sink { [weak dest] lastMessage in
                dest?.send(lastMessage + "\n")
            }
        return route.id
    }

    func removeRoute(_ id: UUID) {
        routeCancellables.removeValue(forKey: id)
        routes.removeAll { $0.id == id }
    }

    /// Returns active routes for a given worktree path.
    func activeRoutes(for path: String) -> [AgentRoute] {
        routes.filter { $0.worktreePath == path }
    }

    private func session(_ kind: AgentKind, in workspace: WorktreeWorkspace) -> AgentSession {
        kind == .claude ? workspace.claudeSession : workspace.codexSession
    }

    private nonisolated static func gitWorktreeRemove(repoPath: String, worktreePath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", repoPath, "worktree", "remove", "--force", worktreePath]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
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
