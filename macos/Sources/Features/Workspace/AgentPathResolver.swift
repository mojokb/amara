import Foundation

/// Resolves the on-disk paths of `claude` and `codex` by querying the user's
/// login shell. GUI apps don't inherit the interactive PATH, so we can't rely
/// on plain `which` — we need to source the user's shell config first.
@MainActor
final class AgentPathResolver: ObservableObject {
    enum Status: Equatable {
        case checking
        case found(String)
        case notFound
    }

    @Published private(set) var claude: Status = .checking
    @Published private(set) var codex: Status = .checking

    var claudeCommand: String? {
        if case .found(let p) = claude { return p }
        return nil
    }

    var codexCommand: String? {
        if case .found(let p) = codex { return p }
        return nil
    }

    var isChecking: Bool {
        claude == .checking || codex == .checking
    }

    /// Missing agent names after resolution completes.
    var missingAgents: [String] {
        var missing: [String] = []
        if case .notFound = claude { missing.append("claude") }
        if case .notFound = codex  { missing.append("codex") }
        return missing
    }

    func resolve() {
        claude = .checking
        codex = .checking
        Task {
            async let c = which("claude")
            async let x = which("codex")
            let (cp, xp) = await (c, x)
            claude = cp.map { .found($0) } ?? .notFound
            codex  = xp.map { .found($0) } ?? .notFound
        }
    }

    private func which(_ name: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-l", "-c", "source ~/.zshrc 2>/dev/null; source ~/.bash_profile 2>/dev/null; which \(name)"]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let path = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if proc.terminationStatus == 0, let p = path, !p.isEmpty {
                        continuation.resume(returning: p)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
