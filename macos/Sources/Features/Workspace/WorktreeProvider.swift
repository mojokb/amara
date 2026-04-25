import Foundation

/// Runs `git worktree list --porcelain` and publishes the result.
final class WorktreeProvider: ObservableObject {
    @Published private(set) var worktrees: [WorktreeEntry] = []
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false

    private var refreshTask: Task<Void, Never>?

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
            case .failure(let err):
                error = err.localizedDescription
            }
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
