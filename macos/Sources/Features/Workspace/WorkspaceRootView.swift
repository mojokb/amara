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
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftPanel
                    .frame(width: 210)
                    .frame(maxHeight: .infinity)

                Divider()

                rightPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            statusBar
        }
        // Makes ghostty available to SurfaceWrapper / InspectableSurface descendants.
        .environmentObject(ghostty)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        Divider()
            .overlay(alignment: .bottom) {
                HStack(spacing: 12) {
                    // Repo path
                    if let repo = manager.repositoryPath {
                        Label(shortenPath(repo), systemImage: "folder")
                            .lineLimit(1)
                    }

                    // Active worktree branch
                    if let selected = manager.selectedPath,
                       let entry = manager.worktreeProvider.worktrees.first(where: { $0.path == selected }) {
                        Divider().frame(height: 12)
                        Label(entry.branch, systemImage: "arrow.triangle.branch")
                            .lineLimit(1)
                        Divider().frame(height: 12)
                        Label(shortenPath(selected), systemImage: "internaldrive")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Attention state

    private var needsAttentionPaths: Set<String> {
        Set(manager.workspaces.values
            .filter { $0.claudeNeedsAttention || $0.codexNeedsAttention }
            .map { $0.path })
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
                    needsAttentionPaths: needsAttentionPaths,
                    onSelect: { manager.select(path: $0.path) },
                    onRefresh: manager.refreshWorktrees,
                    onCreateWorktree: { try await manager.createWorktree(branch: $0) }
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
        VStack(spacing: 0) {
            preflightBanner
            rightPanelContent
        }
    }

    @ViewBuilder
    private var preflightBanner: some View {
        if manager.resolver.isChecking {
            Label("Checking for claude and codex…", systemImage: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        } else if !manager.resolver.missingAgents.isEmpty {
            let names = manager.resolver.missingAgents.joined(separator: ", ")
            Label(
                "\(names) not found — install and relaunch Amara.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.25))
        }
    }

    private var rightPanelContent: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
