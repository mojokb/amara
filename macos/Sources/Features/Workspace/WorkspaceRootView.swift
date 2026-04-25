import SwiftUI
import AppKit

/// Top-level view for the workspace window.
///
/// Layout:
/// ┌──────────────┬──────────────────────────────┐
/// │  Worktree    │  [claude] [codex]  ← tab bar │
/// │  List        │  ─────────────────────────── │
/// │              │  SurfaceView (active surface)│
/// └──────────────┴──────────────────────────────┘
struct WorkspaceRootView: View {
    let ghostty: Amara.App
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
                .frame(width: 210)
                .frame(maxHeight: .infinity)

            Divider()

            rightPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Makes ghostty available to SurfaceWrapper / InspectableSurface descendants.
        .environmentObject(ghostty)
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            if manager.repositoryPath != nil {
                WorktreeListView(
                    worktrees: manager.worktreeProvider.worktrees,
                    selectedPath: manager.selectedPath,
                    isLoading: manager.worktreeProvider.isLoading,
                    error: manager.worktreeProvider.error,
                    onSelect: { manager.select(path: $0.path) },
                    onRefresh: manager.refreshWorktrees
                )
            } else {
                noRepositoryPanel
            }
        }
    }

    private var noRepositoryPanel: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("No repository selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open Repository…") {
                pickRepository()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        ZStack {
            if manager.workspaces.isEmpty {
                emptyState
            }

            // Keep all previously-opened workspaces alive in the view graph so
            // their PTY processes continue running. Only the selected one is visible.
            ForEach(Array(manager.workspaces.values), id: \.path) { workspace in
                WorkspaceContentView(workspace: workspace)
                    .opacity(workspace.path == manager.selectedPath ? 1.0 : 0.0)
                    .allowsHitTesting(workspace.path == manager.selectedPath)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Select a worktree to start")
                .foregroundStyle(.secondary)
            if manager.repositoryPath == nil {
                Text("Open a repository first")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Repository picker

    private func pickRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the root of a git repository"
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        manager.setRepository(path: url.path)
    }
}
