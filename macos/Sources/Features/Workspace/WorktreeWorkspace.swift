import Foundation
import Combine
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

    /// True when the claude surface has new activity while its tab is not active.
    @Published private(set) var claudeNeedsAttention: Bool = false

    /// True when the codex surface has new activity while its tab is not active.
    @Published private(set) var codexNeedsAttention: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    // Ignore surface events for a short window after creation to avoid
    // flagging startup chatter (initial title set, pwd resolved, etc.).
    private let createdAt = Date()
    private let gracePeriod: TimeInterval = 2.5

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

        setupAttentionTracking()
    }

    // MARK: - Attention tracking

    private func setupAttentionTracking() {
        // Clear attention flag whenever the user activates that tab.
        $activeTab
            .receive(on: RunLoop.main)
            .sink { [weak self] tab in
                switch tab {
                case .claude: self?.claudeNeedsAttention = false
                case .codex:  self?.codexNeedsAttention  = false
                case .file:   break
                }
            }
            .store(in: &cancellables)

        // Raise attention flag when a surface emits any published-property change
        // while its tab is not the active one. objectWillChange fires for title
        // updates, pwd (OSC 7 shell integration), bell, progress reports, etc.
        claudeSurface.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, Date().timeIntervalSince(self.createdAt) > self.gracePeriod else { return }
                if self.activeTab != .claude { self.claudeNeedsAttention = true }
            }
            .store(in: &cancellables)

        codexSurface.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, Date().timeIntervalSince(self.createdAt) > self.gracePeriod else { return }
                if self.activeTab != .codex { self.codexNeedsAttention = true }
            }
            .store(in: &cancellables)
    }
}
