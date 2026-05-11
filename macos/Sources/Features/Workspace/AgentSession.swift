import Foundation
import Combine
import AmaraKit

/// Manages a single AI agent process within a worktree.
final class AgentSession: ObservableObject {

    /// The ghostty surface that renders this agent's terminal.
    /// Replaced with a fresh surface on each manual restart.
    @Published private(set) var surface: Amara.SurfaceView

    @Published private(set) var needsAttention: Bool = false
    @Published private(set) var lastMessage: String?
    @Published private(set) var outputBuffer: String = ""

    var outputPublisher: AnyPublisher<String, Never> {
        PassthroughSubject<String, Never>().eraseToAnyPublisher()
    }

    var idlePublisher: AnyPublisher<String, Never> {
        PassthroughSubject<String, Never>().eraseToAnyPublisher()
    }

    var isExited: Bool { surface.childExitedMessage != nil }

    private let ghosttyApp: ghostty_app_t
    private let command: String
    private let workingDirectory: String
    private var surfaceObservation: AnyCancellable?

    init(ghosttyApp: ghostty_app_t, command: String, workingDirectory: String) {
        self.ghosttyApp = ghosttyApp
        self.command = command
        self.workingDirectory = workingDirectory
        self.surface = Self.makeSurface(ghosttyApp: ghosttyApp, command: command, workingDirectory: workingDirectory)
        observeSurface()
    }

    // MARK: - Input

    func send(_ text: String) {
        guard let model = surface.surfaceModel else { return }
        DispatchQueue.main.async { model.sendText(text) }
    }

    // MARK: - Attention

    func clearAttention() {
        needsAttention = false
        lastMessage = nil
    }

    // MARK: - Restart

    func restart() {
        surface = Self.makeSurface(ghosttyApp: ghosttyApp, command: command, workingDirectory: workingDirectory)
        observeSurface()
    }

    private func observeSurface() {
        surfaceObservation = surface.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private static func makeSurface(ghosttyApp: ghostty_app_t, command: String, workingDirectory: String) -> Amara.SurfaceView {
        var config = Amara.SurfaceConfiguration()
        config.workingDirectory = workingDirectory
        config.command = command
        // Prepend the binary's own directory to PATH so that shebang-based tools
        // (e.g. codex uses #!/usr/bin/env node) can find their runtime sibling binaries.
        let binDir = URL(fileURLWithPath: command).deletingLastPathComponent().path
        let basePath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin"
        config.environmentVariables["PATH"] = "\(binDir):\(basePath)"
        return Amara.SurfaceView(ghosttyApp, baseConfig: config)
    }
}
