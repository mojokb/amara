import Foundation
import AppKit

// MARK: - Entry model (shared with WorktreeFileBrowser)

struct FileBrowserEntry: Identifiable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool

    static let skipNames: Set<String> = [
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
            .filter { !skipNames.contains($0.lastPathComponent) }
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

// MARK: - Controller

/// Manages selection, expansion state, and keyboard navigation for the file browser.
@MainActor
final class FileBrowserController: ObservableObject {

    // MARK: State

    @Published var selectedPath: String? = nil
    @Published var expandedPaths: Set<String> = []
    @Published var pendingDeletePath: String? = nil   // triggers delete confirm

    let clipboard: FileBrowserClipboard

    private var rootEntries: [FileBrowserEntry] = []
    private var rootPath: String = ""

    init(clipboard: FileBrowserClipboard) {
        self.clipboard = clipboard
    }

    // MARK: - Tree state

    func update(rootPath: String, entries: [FileBrowserEntry]) {
        self.rootPath = rootPath
        self.rootEntries = entries
    }

    func toggleExpand(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }

    func isExpanded(_ path: String) -> Bool {
        expandedPaths.contains(path)
    }

    // MARK: - Visible flat list (for arrow key navigation)

    var visiblePaths: [String] {
        flatVisible(entries: rootEntries)
    }

    private func flatVisible(entries: [FileBrowserEntry]) -> [String] {
        var result: [String] = []
        for entry in entries {
            result.append(entry.path)
            if entry.isDirectory && expandedPaths.contains(entry.path) {
                result += flatVisible(entries: FileBrowserEntry.children(of: entry.path))
            }
        }
        return result
    }

    // MARK: - Navigation

    func selectNext() {
        let paths = visiblePaths
        guard !paths.isEmpty else { return }
        if let cur = selectedPath, let idx = paths.firstIndex(of: cur) {
            selectedPath = paths[min(idx + 1, paths.count - 1)]
        } else {
            selectedPath = paths.first
        }
    }

    func selectPrev() {
        let paths = visiblePaths
        guard !paths.isEmpty else { return }
        if let cur = selectedPath, let idx = paths.firstIndex(of: cur) {
            selectedPath = paths[max(idx - 1, 0)]
        } else {
            selectedPath = paths.first
        }
    }

    /// → key: expand folder, or do nothing for files.
    func expandSelected() {
        guard let path = selectedPath else { return }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        if isDir.boolValue { expandedPaths.insert(path) }
    }

    /// ← key: collapse folder, or jump to parent directory.
    func collapseOrGoUp() {
        guard let path = selectedPath else { return }
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            if parent != rootPath && parent != path {
                selectedPath = parent
            }
        }
    }

    // MARK: - Actions on selected item

    func cutSelected() {
        guard let path = selectedPath else { return }
        clipboard.cut(URL(fileURLWithPath: path))
    }

    func copySelected() {
        guard let path = selectedPath else { return }
        clipboard.copy(URL(fileURLWithPath: path))
    }

    func pasteIntoSelected(onRefresh: @escaping () -> Void) {
        guard clipboard.hasContent else { return }
        let dir: URL
        if let path = selectedPath {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            dir = isDir.boolValue
                ? URL(fileURLWithPath: path)
                : URL(fileURLWithPath: path).deletingLastPathComponent()
        } else {
            dir = URL(fileURLWithPath: rootPath)
        }
        try? clipboard.paste(into: dir)
        onRefresh()
    }

    func requestDeleteSelected() {
        guard selectedPath != nil else { return }
        pendingDeletePath = selectedPath
    }

    func confirmDelete(onRefresh: @escaping () -> Void) {
        guard let path = pendingDeletePath else { return }
        try? FileManager.default.removeItem(atPath: path)
        if selectedPath == path { selectedPath = nil }
        pendingDeletePath = nil
        onRefresh()
    }

    func cancelDelete() {
        pendingDeletePath = nil
    }
}
