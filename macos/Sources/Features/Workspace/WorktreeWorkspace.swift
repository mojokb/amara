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

    private let ghosttyApp: ghostty_app_t

    /// Ordered list of open file URLs (editor tabs).
    @Published var fileTabs: [URL] = []

    /// Surface per open file URL.
    @Published var fileSurfaces: [URL: Amara.SurfaceView] = [:]

    /// Which tab is currently selected in the right panel.
    @Published var activeTab: WorkspaceTab = .claude

    /// True when the claude surface went idle after producing output (waiting for user input).
    @Published private(set) var claudeNeedsAttention: Bool = false

    /// True when the codex surface went idle after producing output (waiting for user input).
    @Published private(set) var codexNeedsAttention: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    // Screen content hashes — updated every poll cycle
    private var claudeLastHash: Int = 0
    private var codexLastHash:  Int = 0

    // Timers that fire when content stabilises (agent went idle)
    private var claudeIdleTimer: Timer?
    private var codexIdleTimer:  Timer?

    // Repeating timer that reads surface content hashes
    private var pollTimer: Timer?

    // How long content must be stable before we consider the agent idle.
    private let idleThreshold: TimeInterval = 2.5

    // Grace period: ignore the first few seconds after a workspace is created
    // to suppress PTY startup chatter.
    private let createdAt = Date()
    private let gracePeriod: TimeInterval = 3.0

    init(path: String, ghosttyApp: ghostty_app_t, claudeCommand: String, codexCommand: String) {
        self.path = path
        self.ghosttyApp = ghosttyApp

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

    // MARK: - File editor

    func openFile(_ url: URL) {
        if fileSurfaces[url] != nil {
            activeTab = .file(url)
            return
        }
        var config = Amara.SurfaceConfiguration()
        config.workingDirectory = path
        config.command = "/usr/bin/vim " + shellEscape(url.path)
        let surface = Amara.SurfaceView(ghosttyApp, baseConfig: config)
        fileSurfaces[url] = surface
        fileTabs.append(url)
        activeTab = .file(url)
    }

    func closeFile(_ url: URL) {
        if let model = fileSurfaces[url]?.surfaceModel {
            Task { @MainActor in model.sendText(":q!\n") }
        }
        fileSurfaces.removeValue(forKey: url)
        fileTabs.removeAll { $0 == url }
        if activeTab == .file(url) {
            activeTab = fileTabs.last.map { .file($0) } ?? .claude
        }
    }

    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    deinit {
        pollTimer?.invalidate()
        claudeIdleTimer?.invalidate()
        codexIdleTimer?.invalidate()
    }

    // MARK: - Attention tracking

    private func setupAttentionTracking() {
        // When the user activates a tab: clear its attention flag, cancel its
        // idle timer, and snapshot the current content so the next poll has a
        // fresh baseline to diff against.
        $activeTab
            .receive(on: RunLoop.main)
            .sink { [weak self] tab in
                guard let self else { return }
                switch tab {
                case .claude:
                    self.claudeIdleTimer?.invalidate()
                    self.claudeIdleTimer = nil
                    self.claudeNeedsAttention = false
                    self.claudeLastHash = self.claudeSurface.cachedVisibleContents.get().hashValue
                case .codex:
                    self.codexIdleTimer?.invalidate()
                    self.codexIdleTimer = nil
                    self.codexNeedsAttention = false
                    self.codexLastHash = self.codexSurface.cachedVisibleContents.get().hashValue
                case .file:
                    break
                }
            }
            .store(in: &cancellables)

        // Poll visible screen content for both surfaces every second.
        // On each tick we compare the new hash to the previous one:
        //   • hash changed  → agent is still producing output; reset the idle
        //                     timer and clear any pending attention flag.
        //   • hash unchanged → content has stabilised; the idle timer (started
        //                     on the last change) will fire after idleThreshold
        //                     seconds and set needsAttention.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollSurfaces()
        }
    }

    private func pollSurfaces() {
        guard Date().timeIntervalSince(createdAt) > gracePeriod else { return }
        pollSurface(.claude)
        pollSurface(.codex)
    }

    private func pollSurface(_ tab: WorkspaceTab) {
        // No need to track content while the user is looking at it.
        guard activeTab != tab else { return }

        let surface: Amara.SurfaceView
        switch tab {
        case .claude: surface = claudeSurface
        case .codex:  surface = codexSurface
        default:      return
        }

        let newHash = surface.cachedVisibleContents.get().hashValue
        let prevHash: Int
        switch tab {
        case .claude: prevHash = claudeLastHash
        case .codex:  prevHash = codexLastHash
        default:      return
        }

        // Store updated hash
        switch tab {
        case .claude: claudeLastHash = newHash
        case .codex:  codexLastHash  = newHash
        default: break
        }

        guard newHash != prevHash else {
            // Content unchanged — idle timer (if any) is already counting down.
            return
        }

        // Content changed → agent is still producing output.
        // Restart the idle timer and clear any dot that may have been set.
        switch tab {
        case .claude:
            claudeIdleTimer?.invalidate()
            claudeNeedsAttention = false
            claudeIdleTimer = Timer.scheduledTimer(
                withTimeInterval: idleThreshold, repeats: false
            ) { [weak self] _ in
                guard let self, self.activeTab != .claude else { return }
                self.claudeNeedsAttention = true
                self.claudeIdleTimer = nil
            }
        case .codex:
            codexIdleTimer?.invalidate()
            codexNeedsAttention = false
            codexIdleTimer = Timer.scheduledTimer(
                withTimeInterval: idleThreshold, repeats: false
            ) { [weak self] _ in
                guard let self, self.activeTab != .codex else { return }
                self.codexNeedsAttention = true
                self.codexIdleTimer = nil
            }
        default: break
        }
    }
}
