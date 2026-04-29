import SwiftUI

/// Expandable file-tree panel shown when a worktree is selected in the left panel.
struct WorktreeFileBrowser: View {
    let rootPath: String
    var onOpenFile: ((URL) -> Void)? = nil

    @State private var rootEntries: [FileBrowserEntry] = []
    @State private var gitStatus: [String: String] = [:]   // absolute path → status char

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rootEntries) { entry in
                    FileBrowserNode(entry: entry, depth: 0, gitStatus: gitStatus, onOpenFile: onOpenFile)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            rootEntries = FileBrowserEntry.children(of: rootPath)
            loadGitStatus()
        }
    }

    private func loadGitStatus() {
        let path = rootPath
        Task {
            let status = await Task.detached(priority: .utility) {
                WorktreeFileBrowser.fetchGitStatus(repoPath: path)
            }.value
            gitStatus = status
        }
    }

    private nonisolated static func fetchGitStatus(repoPath: String) -> [String: String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // -u lists individual untracked files (not just directories)
        proc.arguments = ["-C", repoPath, "status", "--porcelain", "-u"]
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return [:] }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return [:] }

        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var result: [String: String] = [:]

        for line in output.components(separatedBy: "\n") {
            guard line.count >= 4 else { continue }
            let xy = String(line.prefix(2))
            // For renames: "R  old -> new" — take the part after " -> "
            var relativePath = String(line.dropFirst(3))
            if xy.hasPrefix("R"), let arrow = relativePath.range(of: " -> ") {
                relativePath = String(relativePath[arrow.upperBound...])
            }
            let absPath = repoPath + "/" + relativePath

            let statusChar: String
            switch xy {
            case "??":                                    statusChar = "U"
            case _ where xy.hasPrefix("A"):               statusChar = "A"
            case _ where xy.hasPrefix("D") || xy.hasSuffix("D"): statusChar = "D"
            case _ where xy.hasPrefix("R"):               statusChar = "R"
            case _ where xy.hasPrefix("M") || xy.hasSuffix("M"): statusChar = "M"
            default:                                      statusChar = ""
            }
            if !statusChar.isEmpty {
                result[absPath] = statusChar
            }
        }
        return result
    }
}

// MARK: - Node (recursive)

private struct FileBrowserNode: View {
    let entry: FileBrowserEntry
    let depth: Int
    let gitStatus: [String: String]
    let onOpenFile: ((URL) -> Void)?

    @State private var isExpanded = false
    @State private var children: [FileBrowserEntry] = []
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowView
            if isExpanded {
                ForEach(children) { child in
                    FileBrowserNode(entry: child, depth: depth + 1, gitStatus: gitStatus, onOpenFile: onOpenFile)
                }
            }
        }
    }

    // MARK: - Git status indicator

    private var statusIndicator: (char: String, color: Color)? {
        if entry.isDirectory {
            let prefix = entry.path + "/"
            var best: String? = nil
            for (path, s) in gitStatus where path.hasPrefix(prefix) {
                if best == nil || statusPriority(s) > statusPriority(best!) { best = s }
            }
            return best.map { ($0, statusColor($0)) }
        } else {
            return gitStatus[entry.path].map { ($0, statusColor($0)) }
        }
    }

    private func statusPriority(_ s: String) -> Int {
        switch s {
        case "D": return 4
        case "M": return 3
        case "A": return 2
        case "U": return 1
        default:  return 0
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "U", "A": return .green
        case "M":      return Color(red: 0.9, green: 0.6, blue: 0.1)
        case "D":      return .red
        case "R":      return Color.blue.opacity(0.8)
        default:       return .secondary
        }
    }

    // MARK: - Row

    private var rowView: some View {
        HStack(spacing: 3) {
            Color.clear.frame(width: CGFloat(depth) * 12)

            if entry.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 8)
            } else {
                Color.clear.frame(width: 8)
            }

            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 10))
                .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                .frame(width: 13)

            Text(entry.name)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let indicator = statusIndicator {
                Text(indicator.char)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(indicator.color)
                    .frame(width: 14, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(isHovered ? Color.primary.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if entry.isDirectory {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                if isExpanded && children.isEmpty {
                    children = FileBrowserEntry.children(of: entry.path)
                }
            } else {
                onOpenFile?(URL(fileURLWithPath: entry.path))
            }
        }
    }
}

// MARK: - Model

private struct FileBrowserEntry: Identifiable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool

    private static let skip: Set<String> = [
        ".git", "node_modules", ".build", "zig-cache", ".zig-cache",
        "zig-out", "build-cmake", "__pycache__", ".venv", ".tox",
    ]

    static func children(of dirPath: String) -> [FileBrowserEntry] {
        let url = URL(fileURLWithPath: dirPath)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return items
            .filter { !skip.contains($0.lastPathComponent) }
            .compactMap { u -> FileBrowserEntry? in
                let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return FileBrowserEntry(id: u.path, name: u.lastPathComponent, path: u.path, isDirectory: isDir)
            }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }
}
