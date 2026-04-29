import Foundation

/// Runs `git worktree list --porcelain` and publishes the result.
/// Also polls Gitea for PR status and fires `onPRMerged` when a branch is merged.
final class WorktreeProvider: ObservableObject {
    @Published private(set) var worktrees: [WorktreeEntry] = []
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false

    /// Called on MainActor when a worktree's PR transitions to merged state.
    var onPRMerged: ((WorktreeEntry) -> Void)?

    private var refreshTask: Task<Void, Never>?
    private var prPollTask: Task<Void, Never>?
    /// branch name → PR number, tracks which branches have open PRs.
    private var trackedPRNumbers: [String: Int] = [:]

    @MainActor
    func refresh(for directory: String) {
        refreshTask?.cancel()
        isLoading = true
        error = nil

        refreshTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.run(in: directory)
            }.value

            guard !Task.isCancelled else { return }

            isLoading = false
            switch result {
            case .success(let entries):
                worktrees = entries
                await fetchAndApplyPRs(repoPath: directory, detectMerges: false)
                startPRPolling(repoPath: directory)
            case .failure(let err):
                error = err.localizedDescription
            }
        }
    }

    // MARK: - PR polling

    @MainActor
    private func startPRPolling(repoPath: String) {
        prPollTask?.cancel()
        guard GiteaCredentials.isConfigured else { return }
        prPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await fetchAndApplyPRs(repoPath: repoPath, detectMerges: true)
            }
        }
    }

    @MainActor
    func refreshPRInfo(repoPath: String) async {
        await fetchAndApplyPRs(repoPath: repoPath, detectMerges: false)
    }

    @MainActor
    private func fetchAndApplyPRs(repoPath: String, detectMerges: Bool) async {
        guard GiteaCredentials.isConfigured,
              let client = GiteaClient.fromCredentials() else { return }

        let remoteStr = await Task.detached { GiteaClient.remoteURL(repoPath: repoPath) }.value
        guard let remoteStr,
              let (owner, repo) = GiteaClient.parseRemote(remoteStr) else { return }

        do {
            async let openTask   = client.openPRs(owner: owner, repo: repo)
            async let closedTask = client.closedPRs(owner: owner, repo: repo)
            let (openPRs, closedPRs) = try await (openTask, closedTask)

            let allPRs = openPRs + closedPRs

            // Detect merges: branch was tracked as open but is now merged
            if detectMerges {
                for entry in worktrees where !entry.isBare {
                    if let tracked = trackedPRNumbers[entry.branch],
                       let pr = allPRs.first(where: { $0.number == tracked }),
                       pr.state == .merged {
                        trackedPRNumbers.removeValue(forKey: entry.branch)
                        onPRMerged?(entry)
                    }
                }
            }

            // Build branch → best PRInfo map (open takes priority over closed)
            var byBranch: [String: PRInfo] = [:]
            for pr in allPRs {
                if byBranch[pr.headBranch] == nil
                    || pr.state == .open || pr.state == .draft {
                    byBranch[pr.headBranch] = pr
                }
            }

            // Apply to worktree entries
            for idx in worktrees.indices where !worktrees[idx].isBare {
                let branch = worktrees[idx].branch
                let pr = byBranch[branch]
                worktrees[idx].prInfo = pr
                if let pr, pr.state == .open || pr.state == .draft {
                    trackedPRNumbers[branch] = pr.number
                }
            }
        } catch {
            // Silently ignore — Gitea may be unreachable
        }
    }

    // MARK: - git subprocess

    private static func run(in directory: String) -> Result<[WorktreeEntry], Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "worktree", "list", "--porcelain"]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return .failure(error)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return .failure(NSError(
                domain: "git",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git worktree list failed (not a git repo?)"]
            ))
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return .success(parse(output))
    }

    // MARK: - porcelain parser

    private static func parse(_ output: String) -> [WorktreeEntry] {
        var entries: [WorktreeEntry] = []
        var currentPath: String?
        var branch = "HEAD"
        var isBare = false
        var isLocked = false

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                if let p = currentPath {
                    entries.append(WorktreeEntry(
                        path: p, branch: branch,
                        isBare: isBare, isLocked: isLocked))
                }
                currentPath = String(line.dropFirst("worktree ".count))
                branch = "HEAD"
                isBare = false
                isLocked = false
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/")
                    ? String(ref.dropFirst("refs/heads/".count))
                    : ref
            } else if line == "bare" {
                isBare = true
            } else if line.hasPrefix("locked") {
                isLocked = true
            }
        }

        if let p = currentPath {
            entries.append(WorktreeEntry(
                path: p, branch: branch,
                isBare: isBare, isLocked: isLocked))
        }

        return entries
    }
}
