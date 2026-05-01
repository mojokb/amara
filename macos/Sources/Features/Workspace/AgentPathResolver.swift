import Foundation

/// Resolves the on-disk paths of `claude` and `codex`.
///
/// Checks representative install locations directly (no shell spawn).
/// Covered: Homebrew, Volta, nvm, npm global prefix, ~/.local/bin.
/// If not found → `.notFound` immediately; user can Retry after installing.
@MainActor
final class AgentPathResolver: ObservableObject {
    enum Status: Equatable {
        case checking
        case found(String)
        case notFound
    }

    @Published private(set) var claude: Status = .checking
    @Published private(set) var codex:  Status = .checking

    var claudeCommand: String? {
        if case .found(let p) = claude { return p }
        return nil
    }

    var codexCommand: String? {
        if case .found(let p) = codex { return p }
        return nil
    }

    var isChecking: Bool { claude == .checking || codex == .checking }

    var missingAgents: [String] {
        var out: [String] = []
        if case .notFound = claude { out.append("claude") }
        if case .notFound = codex  { out.append("codex") }
        return out
    }

    func resolve() {
        claude = .checking
        codex  = .checking
        Task.detached(priority: .userInitiated) {
            let cp = Self.find("claude")
            let xp = Self.find("codex")
            await MainActor.run {
                self.claude = cp.map { .found($0) } ?? .notFound
                self.codex  = xp.map { .found($0) } ?? .notFound
            }
        }
    }

    // MARK: - Path lookup

    nonisolated private static func find(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm   = FileManager.default

        // npm prefix from ~/.npmrc
        var npmPrefixPath: String?
        if let raw = try? String(contentsOfFile: "\(home)/.npmrc", encoding: .utf8) {
            for line in raw.components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("prefix=") {
                    let prefix = String(t.dropFirst("prefix=".count)).trimmingCharacters(in: .whitespaces)
                    if !prefix.isEmpty { npmPrefixPath = "\(prefix)/bin/\(name)" }
                }
            }
        }

        // nvm: enumerate all installed versions newest-first
        var nvmPaths: [String] = []
        let nvmDir = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmDir) {
            nvmPaths = versions
                .sorted {
                    let a = $0.hasPrefix("v") ? String($0.dropFirst()) : $0
                    let b = $1.hasPrefix("v") ? String($1.dropFirst()) : $1
                    return a.compare(b, options: .numeric) == .orderedDescending
                }
                .map { "\(nvmDir)/\($0)/bin/\(name)" }
        }

        let candidates: [String] = [
            "/opt/homebrew/bin/\(name)",        // Homebrew (Apple Silicon)
            "/usr/local/bin/\(name)",            // Homebrew (Intel) / system npm
            "\(home)/.volta/bin/\(name)",        // Volta
            "\(home)/.asdf/shims/\(name)",       // asdf
            "\(home)/.npm-global/bin/\(name)",   // npm global custom prefix
            "\(home)/.local/bin/\(name)",        // misc user-local
            "\(home)/bin/\(name)",
        ] + (npmPrefixPath.map { [$0] } ?? []) + nvmPaths

        return candidates.first { fm.fileExists(atPath: $0) }
    }
}
