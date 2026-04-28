import SwiftUI

/// Right-panel view for a single worktree.
///
/// Top half  — tab bar + agent/file surfaces (claude, codex, vim, markdown viewer).
/// Bottom half — plain shell terminal.
/// The split is user-resizable via NSSplitView (VSplitView).
struct WorkspaceContentView: View {
    @ObservedObject var workspace: WorktreeWorkspace

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTabBar(
                activeTab: $workspace.activeTab,
                fileTabs: workspace.fileTabs,
                claudeNeedsAttention: workspace.claudeNeedsAttention,
                codexNeedsAttention: workspace.codexNeedsAttention,
                onClose: closeFile
            )

            VSplitView {
                agentPanel
                terminalPanel
            }
        }
    }

    // MARK: - Top panel (agents + files)

    private var agentPanel: some View {
        ZStack {
            // Claude session — always in hierarchy, invisible when not active
            Amara.InspectableSurface(surfaceView: workspace.claudeSurface)
                .surfaceVisible(workspace.activeTab == .claude)

            // Codex session
            Amara.InspectableSurface(surfaceView: workspace.codexSurface)
                .surfaceVisible(workspace.activeTab == .codex)

            // File editor tabs
            ForEach(workspace.fileTabs, id: \.self) { url in
                if let surface = workspace.fileSurfaces[url] {
                    let isActive = workspace.activeTab == .file(url)
                    let isMarkdown = url.pathExtension.lowercased() == "md"
                    let viewing = workspace.isViewingMarkdown(url)

                    // vim surface — kept alive even when markdown viewer is showing
                    Amara.InspectableSurface(surfaceView: surface)
                        .surfaceVisible(isActive && !(isMarkdown && viewing))

                    // markdown viewer — overlaid when in viewer mode
                    if isMarkdown {
                        MarkdownViewerView(fileURL: url)
                            .opacity(isActive && viewing ? 1 : 0)
                            .allowsHitTesting(isActive && viewing)
                            .accessibilityHidden(!(isActive && viewing))
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) { markdownToggleButton }
        .frame(minHeight: 150)
    }

    // MARK: - Bottom panel (terminal)

    private var terminalPanel: some View {
        Amara.InspectableSurface(surfaceView: workspace.shellSurface)
            .frame(minHeight: 80)
    }

    // MARK: - Markdown toggle

    @ViewBuilder
    private var markdownToggleButton: some View {
        if case .file(let url) = workspace.activeTab,
           url.pathExtension.lowercased() == "md" {
            let viewing = workspace.isViewingMarkdown(url)
            Button { workspace.toggleMarkdownMode(for: url) } label: {
                Label(viewing ? "Edit" : "Preview",
                      systemImage: viewing ? "pencil" : "doc.richtext")
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }

    // MARK: - Helpers

    private func closeFile(_ url: URL) {
        workspace.closeFile(url)
    }
}

// MARK: - View modifier helpers

private extension View {
    /// Keeps the view in the SwiftUI layout tree but hides it when `visible` is false.
    /// Unlike `.hidden()`, this does not call `@ViewBuilder if/else` so the underlying
    /// NSViewRepresentable (and the PTY inside it) stays alive across visibility changes.
    func surfaceVisible(_ visible: Bool) -> some View {
        self
            .opacity(visible ? 1.0 : 0.0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}
