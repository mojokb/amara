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

    init(path: String, ghosttyApp: ghostty_app_t, claudeCommand: String, codexCommand: String) {
        self.path = path

        var claudeConfig = Amara.SurfaceConfiguration()
        claudeConfig.workingDirectory = path
        claudeConfig.command = claudeCommand
        self.claudeSurface = Amara.SurfaceView(ghosttyApp, baseConfig: claudeConfig)

        var codexConfig = Amara.SurfaceConfiguration()
        codexConfig.workingDirectory = path
        codexConfig.command = codexCommand
        self.codexSurface = Amara.SurfaceView(ghosttyApp, baseConfig: codexConfig)
    }
}
