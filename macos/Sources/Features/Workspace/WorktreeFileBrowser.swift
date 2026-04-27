import SwiftUI

/// Expandable file-tree panel shown below a worktree row on double-click.
struct WorktreeFileBrowser: View {
    let rootPath: String

    @State private var rootEntries: [FileBrowserEntry] = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rootEntries) { entry in
                    FileBrowserNode(entry: entry, depth: 0)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 220)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onAppear {
            rootEntries = FileBrowserEntry.children(of: rootPath)
        }
    }
}

// MARK: - Node (recursive)

private struct FileBrowserNode: View {
    let entry: FileBrowserEntry
    let depth: Int

    @State private var isExpanded = false
    @State private var children: [FileBrowserEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowView
            if isExpanded {
                ForEach(children) { child in
                    FileBrowserNode(entry: child, depth: depth + 1)
                }
            }
        }
    }

    private var rowView: some View {
        HStack(spacing: 3) {
            // depth indent
            Color.clear.frame(width: CGFloat(depth) * 12)

            if entry.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
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
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard entry.isDirectory else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
            if isExpanded && children.isEmpty {
                children = FileBrowserEntry.children(of: entry.path)
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
