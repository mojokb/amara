import Foundation
import Combine
import AmaraKit

/// Manages a single AI agent process within a worktree.
///
/// Wraps a ghostty SurfaceView and tees output to a named FIFO so Amara can
/// monitor the stream in real-time — enabling accurate idle detection,
/// last-message capture, and inter-agent output routing.
///
/// ghostty owns the PTY (no FD injection in ghostty_surface_config_s), so output
/// is intercepted via: command = "bash -c 'agent 2>&1 | tee /tmp/amara-<uuid>'"
final class AgentSession: ObservableObject {

    /// The ghostty surface that renders this agent's terminal.
    let surface: Amara.SurfaceView

    /// True when the agent produced output and then went idle while the user
    /// was looking at a different tab.
    @Published private(set) var needsAttention: Bool = false

    /// Last meaningful output line captured when the agent went idle.
    @Published private(set) var lastMessage: String?

    /// Full accumulated output since creation, capped at ~200 KB.
    @Published private(set) var outputBuffer: String = ""

    /// Fires on every incoming output chunk (raw bytes, may contain ANSI codes).
    var outputPublisher: AnyPublisher<String, Never> {
        outputSubject.eraseToAnyPublisher()
    }

    /// Fires when the agent goes idle, carrying the last meaningful output line.
    var idlePublisher: AnyPublisher<String, Never> {
        idleSubject.eraseToAnyPublisher()
    }

    private let outputSubject = PassthroughSubject<String, Never>()
    private let idleSubject   = PassthroughSubject<String, Never>()

    private let fifoPath: String
    private var readSource: DispatchSourceRead?
    private var idleTimer: Timer?
    private let idleThreshold: TimeInterval = 2.5

    init(ghosttyApp: ghostty_app_t, command: String, workingDirectory: String) {
        let fifoPath = "/tmp/amara-\(UUID().uuidString)"
        self.fifoPath = fifoPath
        Darwin.mkfifo(fifoPath, 0o600)

        var config = Amara.SurfaceConfiguration()
        config.workingDirectory = workingDirectory
        config.command = "/bin/bash -c '\(command) 2>&1 | tee \(fifoPath)'"
        self.surface = Amara.SurfaceView(ghosttyApp, baseConfig: config)

        openFIFO()
    }

    // MARK: - Input

    /// Sends text to the agent's stdin.
    func send(_ text: String) {
        guard let model = surface.surfaceModel else { return }
        DispatchQueue.main.async { model.sendText(text) }
    }

    // MARK: - Attention

    /// Call when the user switches to this agent's tab.
    func clearAttention() {
        idleTimer?.invalidate()
        idleTimer = nil
        needsAttention = false
        lastMessage = nil
    }

    deinit {
        readSource?.cancel()
        idleTimer?.invalidate()
        try? FileManager.default.removeItem(atPath: fifoPath)
    }

    // MARK: - FIFO

    private func openFIFO() {
        let fd = Darwin.open(fifoPath, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            self?.readAvailable(fd: fd)
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        readSource = source
    }

    private func readAvailable(fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 8192)
        let n = Darwin.read(fd, &buf, buf.count)
        guard n > 0 else { return }
        let chunk = String(bytes: buf.prefix(n), encoding: .utf8) ?? ""
        handleOutput(chunk)
    }

    private func handleOutput(_ chunk: String) {
        outputBuffer += chunk
        if outputBuffer.count > 200_000 {
            outputBuffer = String(outputBuffer.suffix(150_000))
        }

        outputSubject.send(chunk)

        needsAttention = false
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleThreshold, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.needsAttention = true
            if let msg = Self.extractLastMessage(from: self.outputBuffer) {
                self.lastMessage = msg
                self.idleSubject.send(msg)
            }
            self.idleTimer = nil
        }
    }

    // MARK: - Message extraction

    static func extractLastMessage(from content: String) -> String? {
        let stripped = content.replacingOccurrences(
            of: #"\x1B\[[0-9;]*[A-Za-z]"#,
            with: "", options: .regularExpression
        )
        for line in stripped.components(separatedBy: "\n").reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.count > 4 else { continue }
            if let f = t.unicodeScalars.first {
                let prompts: Set<Unicode.Scalar> = ["$", "%", "#", "❯"]
                if prompts.contains(f) && t.count < 6 { continue }
            }
            return t.count > 72 ? String(t.prefix(69)) + "…" : t
        }
        return nil
    }
}
