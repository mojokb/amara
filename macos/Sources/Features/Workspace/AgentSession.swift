import Foundation
import Combine
import AmaraKit

/// Manages a single AI agent process within a worktree.
final class AgentSession: ObservableObject {

    /// The ghostty surface that renders this agent's terminal.
    let surface: Amara.SurfaceView

    /// Placeholder — output monitoring is not yet implemented.
    @Published private(set) var needsAttention: Bool = false
    @Published private(set) var lastMessage: String?
    @Published private(set) var outputBuffer: String = ""

    var outputPublisher: AnyPublisher<String, Never> {
        PassthroughSubject<String, Never>().eraseToAnyPublisher()
    }

    var idlePublisher: AnyPublisher<String, Never> {
        PassthroughSubject<String, Never>().eraseToAnyPublisher()
    }

    init(ghosttyApp: ghostty_app_t, command: String, workingDirectory: String) {
        var config = Amara.SurfaceConfiguration()
        config.workingDirectory = workingDirectory
        config.command = command
        self.surface = Amara.SurfaceView(ghosttyApp, baseConfig: config)
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
}
