import Foundation

/// Resolves the on-disk paths of `claude` and `codex`.
///
/// GUI apps don't inherit the interactive shell PATH, so we use a two-pass strategy:
///
/// 1. **Login shell** — invoke the user's actual shell (`$SHELL`) with `-l` so it
///    sources all startup files (`.zprofile`, `.zshrc`, `config.fish`, etc.).
///    This naturally handles nvm, volta, fnm, asdf, mise, and anything else the
///    user has wired into their shell.
///
/// 2. **Known static paths** — check well-known install locations directly
///    (Homebrew, Volta, asdf shims, mise shims, npm global, ~/bin, …) as a
///    fallback for setups where the login shell times out or isn't configured.
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
        let shell = Self.userShell()
        Task {
            async let c = Self.find("claude", shell: shell)
            async let x = Self.find("codex",  shell: shell)
            let (cp, xp) = await (c, x)
            claude = cp.map { .found($0) } ?? .notFound
            codex  = xp.map { .found($0) } ?? .notFound
        }
    }

    // MARK: - Shell detection

    private static func userShell() -> String {
        // $SHELL is set by the OS for the current user even in GUI contexts.
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
           FileManager.default.fileExists(atPath: shell) {
            return shell
        }
        return "/bin/zsh"
    }

    // MARK: - Two-pass lookup

    private static func find(_ name: String, shell: String) async -> String? {
        if let path = await viaLoginShell(name, shell: shell) { return path }
        return viaKnownPaths(name)
    }

    // MARK: - Pass 1: login shell

    /// Runs `which NAME` through the user's login shell.
    /// Supports: zsh, bash, fish, dash and any POSIX-compatible shell.
    /// Times out after 10 s to handle slow rc files gracefully.
    private static func viaLoginShell(_ name: String, shell: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: shell)
                // `-l` = login shell → sources .zprofile / .bash_profile /
                //                      config.fish / etc. automatically.
                // `which` is a builtin or external available in all major shells.
                proc.arguments = ["-l", "-c", "which \(name) 2>/dev/null"]
                let out = Pipe()
                proc.standardOutput = out
                proc.standardError  = Pipe()

                // Safety timeout: slow rc files (e.g. nvm with many versions) can block.
                let kill = DispatchWorkItem { proc.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: kill)

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    kill.cancel()
                    let raw = String(data: out.fileHandleForReading.readDataToEndOfFile(),
                                     encoding: .utf8) ?? ""
                    // `which` may return multiple lines; take the first non-empty one.
                    let path = raw
                        .components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .first { !$0.isEmpty } ?? ""

                    if proc.terminationStatus == 0, !path.isEmpty,
                       FileManager.default.fileExists(atPath: path) {
                        cont.resume(returning: path)
                    } else {
                        cont.resume(returning: nil)
                    }
                } catch {
                    kill.cancel()
                    cont.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Pass 2: known static paths

    /// Checks well-known install locations directly, without spawning a shell.
    private static func viaKnownPaths(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm   = FileManager.default

        // nvm: resolve the default alias to find the active node version's bin dir.
        var nvmPaths: [String] = []
        let nvmAlias = "\(home)/.nvm/alias/default"
        if let raw = try? String(contentsOfFile: nvmAlias, encoding: .utf8) {
            let alias = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !alias.isEmpty {
            // alias may be "20", "v20.11.0", or "lts/iron" — try both with/without 'v'
            nvmPaths = [
                "\(home)/.nvm/versions/node/\(alias)/bin/\(name)",
                "\(home)/.nvm/versions/node/v\(alias)/bin/\(name)",
                ]
            }
        }

        // fnm: enumerate installed versions and pick the latest as a fallback.
        var fnmPaths: [String] = []
        let fnmRoot = "\(home)/.local/share/fnm/node-versions"
        if let versions = try? fm.contentsOfDirectory(atPath: fnmRoot) {
            fnmPaths = versions
                .sorted(by: >)
                .map { "\(fnmRoot)/\($0)/installation/bin/\(name)" }
        }

        let candidates: [String] = [
            // Homebrew — Apple Silicon
            "/opt/homebrew/bin/\(name)",
            // Homebrew — Intel / manual
            "/usr/local/bin/\(name)",
            // System PATH
            "/usr/bin/\(name)",
            // Volta (manages node/npm tool binaries)
            "\(home)/.volta/bin/\(name)",
            // asdf shims
            "\(home)/.asdf/shims/\(name)",
            // mise (formerly rtx) shims
            "\(home)/.local/share/mise/shims/\(name)",
            // mise legacy path
            "\(home)/.rtx/shims/\(name)",
            // fnm default alias bin
            "\(home)/.local/share/fnm/aliases/default/bin/\(name)",
            // npm global (default prefix on macOS)
            "\(home)/.npm-global/bin/\(name)",
            // npm global via n / nvm / custom prefix
            "\(home)/.local/bin/\(name)",
            // ~/bin (common user-local bin dir)
            "\(home)/bin/\(name)",
            // pnpm global
            "\(home)/Library/pnpm/\(name)",
            // yarn global
            "\(home)/.yarn/bin/\(name)",
        ] + nvmPaths + fnmPaths

        return candidates.first { fm.fileExists(atPath: $0) }
    }
}
