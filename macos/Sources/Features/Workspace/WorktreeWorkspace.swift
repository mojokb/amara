import Foundation
import AmaraKit

/// Per-worktree state: agent surfaces and file editor tabs.
///
/// Surfaces are created eagerly at init time so the PTY processes start
/// immediately when a worktree is first selected.
final class WorktreeWorkspace: ObservableObject {
    /// Absolute path to the worktree root.
    let path: String

    /// The surface running `claude` in this worktree.
    let claudeSurface: Amara.SurfaceView

    /// The surface running `codex` in this worktree.
    let codexSurface: Amara.SurfaceView

    /// Ordered list of open file URLs (editor tabs).
    @Published var fileTabs: [URL] = []

    /// Surface per open file URL.
    @Published var fileSurfaces: [URL: Amara.SurfaceView] = [:]

    /// Which tab is currently selected in the right panel.
    @Published var activeTab: WorkspaceTab = .claude

    init(path: String, ghosttyApp: ghostty_app_t) {
        self.path = path

        var claudeConfig = Amara.SurfaceConfiguration()
        claudeConfig.workingDirectory = path
        claudeConfig.command = "/usr/bin/env claude"
        let cs = Amara.SurfaceView(ghosttyApp, baseConfig: claudeConfig)
        // Keep the surface even on error so the terminal can display the failure message.
        self.claudeSurface = cs

        var codexConfig = Amara.SurfaceConfiguration()
        codexConfig.workingDirectory = path
        codexConfig.command = "/usr/bin/env codex"
        let xs = Amara.SurfaceView(ghosttyApp, baseConfig: codexConfig)
        self.codexSurface = xs
    }
}
