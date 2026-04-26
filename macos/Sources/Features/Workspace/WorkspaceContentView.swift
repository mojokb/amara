import SwiftUI

/// Right-panel view for a single worktree.
///
/// Shows the custom tab bar and a ZStack of all surfaces for this worktree.
/// Non-active surfaces stay in the view hierarchy at opacity 0 so the PTY
/// keeps running while the user works in another tab.
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
                        Amara.InspectableSurface(surfaceView: surface)
                            .surfaceVisible(workspace.activeTab == .file(url))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Helpers

    private func closeFile(_ url: URL) {
        // Ask vim to quit gracefully; the surface closes itself via PTY exit.
        workspace.fileSurfaces[url]?.surfaceModel?.sendText(":q\n")
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
