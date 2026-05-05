import Foundation
import Combine
import AmaraKit

/// Per-worktree state: agent sessions, shell surface, and file editor tabs.
///
/// Surfaces are created eagerly at init time so PTY processes start
/// immediately when a worktree is first selected.
final class WorktreeWorkspace: ObservableObject {

    /// Absolute path to the worktree root.
    let path: String

    /// Agent session running `claude` in this worktree.
    let claudeSession: AgentSession

    /// Agent session running `codex` in this worktree.
    let codexSession: AgentSession

    /// Plain shell surface shown in the bottom terminal panel.
    let shellSurface: Amara.SurfaceView

    // Convenience accessors for views that reference surfaces directly.
    var claudeSurface: Amara.SurfaceView { claudeSession.surface }
    var codexSurface:  Amara.SurfaceView { codexSession.surface }

    // Attention state forwarded from sessions.
    var claudeNeedsAttention: Bool { claudeSession.needsAttention }
    var codexNeedsAttention:  Bool { codexSession.needsAttention }
    var claudeLastMessage: String? { claudeSession.lastMessage }
    var codexLastMessage:  String? { codexSession.lastMessage }

    /// Ordered list of open file URLs (editor tabs).
    @Published var fileTabs: [URL] = []

    /// Surface per open file URL.
    @Published var fileSurfaces: [URL: Amara.SurfaceView] = [:]

    /// For markdown files: true = viewer, false = vim editor. Defaults to viewer.
    @Published var markdownViewModes: [URL: Bool] = [:]

    /// Which tab is currently active in the right panel.
    @Published var activeTab: WorkspaceTab = .claude

    func session(for kind: AgentKind) -> AgentSession {
        kind == .claude ? claudeSession : codexSession
    }

    private let ghosttyApp: ghostty_app_t
    private var cancellables: Set<AnyCancellable> = []
    private var fileSurfaceCancellables: [URL: AnyCancellable] = [:]

    init(path: String, ghosttyApp: ghostty_app_t, claudeCommand: String, codexCommand: String) {
        self.path = path
        self.ghosttyApp = ghosttyApp

        claudeSession = AgentSession(ghosttyApp: ghosttyApp, command: claudeCommand, workingDirectory: path)
        codexSession  = AgentSession(ghosttyApp: ghosttyApp, command: codexCommand,  workingDirectory: path)

        var shellConfig = Amara.SurfaceConfiguration()
        shellConfig.workingDirectory = path
        shellSurface = Amara.SurfaceView(ghosttyApp, baseConfig: shellConfig)

        setupObservation()
    }

    // MARK: - File editor

    func isViewingMarkdown(_ url: URL) -> Bool {
        markdownViewModes[url] ?? true
    }

    func toggleMarkdownMode(for url: URL) {
        markdownViewModes[url] = !isViewingMarkdown(url)
    }

    func openFile(_ url: URL) {
        if fileSurfaces[url] != nil {
            activeTab = .file(url)
            return
        }
        if url.pathExtension.lowercased() == "md" {
            markdownViewModes[url] = true
        }
        var config = Amara.SurfaceConfiguration()
        config.workingDirectory = path
        config.command = "/usr/bin/vim " + shellEscape(url.path)
        let surface = Amara.SurfaceView(ghosttyApp, baseConfig: config)
        fileSurfaces[url] = surface
        fileTabs.append(url)
        activeTab = .file(url)

        fileSurfaceCancellables[url] = surface.$childExitedMessage
            .receive(on: RunLoop.main)
            .compactMap { $0 }
            .first()
            .sink { [weak self] _ in self?.removeFileTab(url) }
    }

    func closeFile(_ url: URL) {
        if let model = fileSurfaces[url]?.surfaceModel {
            Task { @MainActor in model.sendText(":q!\n") }
        }
        removeFileTab(url)
    }

    private func removeFileTab(_ url: URL) {
        fileSurfaceCancellables.removeValue(forKey: url)
        fileSurfaces.removeValue(forKey: url)
        markdownViewModes.removeValue(forKey: url)
        fileTabs.removeAll { $0 == url }
        if activeTab == .file(url) {
            activeTab = fileTabs.last.map { .file($0) } ?? .claude
        }
    }

    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Observation

    private func setupObservation() {
        // Forward session objectWillChange → workspace, so SwiftUI views that
        // observe WorktreeWorkspace re-render when session state changes.
        claudeSession.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        codexSession.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Clear attention when the user opens a tab.
        $activeTab
            .receive(on: RunLoop.main)
            .sink { [weak self] tab in
                guard let self else { return }
                switch tab {
                case .claude:    self.claudeSession.clearAttention()
                case .codex:     self.codexSession.clearAttention()
                case .workflow:  break
                case .file:      break
                }
            }
            .store(in: &cancellables)
    }
}
