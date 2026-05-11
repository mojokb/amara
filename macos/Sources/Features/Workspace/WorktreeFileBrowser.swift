import SwiftUI
import AppKit

// MARK: - Environment key for refresh trigger

private struct RefreshIDKey: EnvironmentKey {
    static let defaultValue: UUID = UUID()
}
private extension EnvironmentValues {
    var fileBrowserRefreshID: UUID {
        get { self[RefreshIDKey.self] }
        set { self[RefreshIDKey.self] = newValue }
    }
}

// MARK: - Root view

struct WorktreeFileBrowser: View {
    let rootPath: String
    var onOpenFile: ((URL) -> Void)? = nil

    @StateObject private var clipboard  = FileBrowserClipboard()
    @StateObject private var controller: FileBrowserController

    @State private var rootEntries: [FileBrowserEntry] = []
    @State private var gitStatus: [String: String] = [:]
    @State private var refreshID = UUID()
    @State private var renamingPath: String? = nil
    @State private var keyMonitor: Any? = nil

    init(rootPath: String, onOpenFile: ((URL) -> Void)? = nil) {
        self.rootPath = rootPath
        self.onOpenFile = onOpenFile
        let cb = FileBrowserClipboard()
        _clipboard   = StateObject(wrappedValue: cb)
        _controller  = StateObject(wrappedValue: FileBrowserController(clipboard: cb))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rootEntries) { entry in
                    FileBrowserNode(
                        entry: entry,
                        depth: 0,
                        rootPath: rootPath,
                        gitStatus: gitStatus,
                        renamingPath: $renamingPath,
                        onOpenFile: onOpenFile,
                        onRefresh: refresh
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            guard let src = urls.first else { return false }
            let dest = URL(fileURLWithPath: rootPath)
                .appendingPathComponent(src.lastPathComponent)
            guard (try? FileManager.default.moveItem(at: src, to: dest)) != nil else { return false }
            refresh(); return true
        }
        .environmentObject(clipboard)
        .environmentObject(controller)
        .environment(\.fileBrowserRefreshID, refreshID)
        .onAppear {
            refresh()
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
        // Delete confirmation driven by controller
        .alert(
            deleteAlertTitle,
            isPresented: Binding(
                get: { controller.pendingDeletePath != nil },
                set: { if !$0 { controller.cancelDelete() } }
            )
        ) {
            Button("Delete", role: .destructive) {
                controller.confirmDelete(onRefresh: refresh)
            }
            Button("Cancel", role: .cancel) { controller.cancelDelete() }
        } message: {
            if let path = controller.pendingDeletePath {
                let isDir = (try? URL(fileURLWithPath: path)
                    .resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                Text(isDir
                     ? "This folder and all its contents will be permanently deleted."
                     : "This file will be permanently deleted.")
            }
        }
        .onChange(of: refreshID) { _ in
            rootEntries = FileBrowserEntry.children(of: rootPath)
            controller.update(rootPath: rootPath, entries: rootEntries)
            loadGitStatus()
        }
    }

    private var deleteAlertTitle: String {
        if let path = controller.pendingDeletePath {
            return "Delete \"\(URL(fileURLWithPath: path).lastPathComponent)\"?"
        }
        return "Delete?"
    }

    // MARK: - Refresh

    private func refresh() {
        rootEntries = FileBrowserEntry.children(of: rootPath)
        controller.update(rootPath: rootPath, entries: rootEntries)
        loadGitStatus()
        refreshID = UUID()
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

    // MARK: - Keyboard monitor

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard controller.selectedPath != nil || renamingPath == nil else { return event }
            return handleKey(event: event)
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Returns nil if the event was consumed, original event otherwise.
    private func handleKey(event: NSEvent) -> NSEvent? {
        // Don't intercept while renaming — TextField handles its own keys
        if renamingPath != nil { return event }
        guard controller.selectedPath != nil else { return event }
        // Don't intercept when a terminal surface (ghostty) has keyboard focus
        if NSApp.keyWindow?.firstResponder is Amara.SurfaceView { return event }

        let cmd   = event.modifierFlags.contains(.command)
        let key   = event.keyCode

        switch (cmd, key) {
        // Navigation
        case (false, 125): controller.selectNext();         return nil  // ↓
        case (false, 126): controller.selectPrev();         return nil  // ↑
        case (false, 124): controller.expandSelected();     return nil  // →
        case (false, 123): controller.collapseOrGoUp();     return nil  // ←

        // Rename → ↩ (Return)
        case (false, 36):
            if let path = controller.selectedPath { renamingPath = path }
            return nil

        // Open → Space
        case (false, 49):
            if let path = controller.selectedPath {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                if isDir.boolValue {
                    controller.toggleExpand(path)
                } else {
                    onOpenFile?(URL(fileURLWithPath: path))
                }
            }
            return nil

        // Deselect → Esc
        case (false, 53): controller.selectedPath = nil; return nil

        // ⌘X Cut
        case (true, 7):   controller.cutSelected();  return nil

        // ⌘C Copy
        case (true, 8):   controller.copySelected(); return nil

        // ⌘V Paste
        case (true, 9):
            controller.pasteIntoSelected(onRefresh: refresh)
            return nil

        // ⌘⌫ Delete
        case (true, 51):
            controller.requestDeleteSelected()
            return nil

        default: return event
        }
    }

    // MARK: - Git status

    private nonisolated static func fetchGitStatus(repoPath: String) -> [String: String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
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
            var relativePath = String(line.dropFirst(3))
            if xy.hasPrefix("R"), let arrow = relativePath.range(of: " -> ") {
                relativePath = String(relativePath[arrow.upperBound...])
            }
            let absPath = repoPath + "/" + relativePath
            let statusChar: String
            switch xy {
            case "??":                                              statusChar = "U"
            case _ where xy.hasPrefix("A"):                        statusChar = "A"
            case _ where xy.hasPrefix("D") || xy.hasSuffix("D"):   statusChar = "D"
            case _ where xy.hasPrefix("R"):                        statusChar = "R"
            case _ where xy.hasPrefix("M") || xy.hasSuffix("M"):   statusChar = "M"
            default:                                                statusChar = ""
            }
            if !statusChar.isEmpty { result[absPath] = statusChar }
        }
        return result
    }
}

// MARK: - Node

private struct FileBrowserNode: View {
    let entry: FileBrowserEntry
    let depth: Int
    let rootPath: String
    let gitStatus: [String: String]
    @Binding var renamingPath: String?
    let onOpenFile: ((URL) -> Void)?
    let onRefresh: () -> Void

    @EnvironmentObject private var clipboard:   FileBrowserClipboard
    @EnvironmentObject private var controller:  FileBrowserController
    @Environment(\.fileBrowserRefreshID) private var refreshID

    @State private var children: [FileBrowserEntry] = []
    @State private var isHovered = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    private var url: URL { URL(fileURLWithPath: entry.path) }
    private var isSelected: Bool { controller.selectedPath == entry.path }
    private var isExpanded: Bool { controller.isExpanded(entry.path) }
    private var isCut: Bool { clipboard.operation == .cut && clipboard.urls.contains(url) }
    private var isRenaming: Bool { renamingPath == entry.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowView
            if isExpanded {
                ForEach(children) { child in
                    FileBrowserNode(
                        entry: child,
                        depth: depth + 1,
                        rootPath: rootPath,
                        gitStatus: gitStatus,
                        renamingPath: $renamingPath,
                        onOpenFile: onOpenFile,
                        onRefresh: onRefresh
                    )
                }
            }
        }
        .onChange(of: refreshID) { _ in
            if isExpanded { children = FileBrowserEntry.children(of: entry.path) }
        }
        .onChange(of: renamingPath) { path in
            if path == entry.path {
                renameText = entry.name
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    renameFocused = true
                }
            }
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

            if isRenaming {
                TextField("", text: $renameText)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
            } else {
                Text(entry.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(isCut ? 0.4 : 1.0)
            }

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
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            guard !isRenaming else { return }
            controller.selectedPath = entry.path
            if entry.isDirectory {
                withAnimation(.easeInOut(duration: 0.15)) {
                    controller.toggleExpand(entry.path)
                }
                if controller.isExpanded(entry.path) && children.isEmpty {
                    children = FileBrowserEntry.children(of: entry.path)
                }
            } else {
                onOpenFile?(url)
            }
        }
        .draggable(url)
        .dropDestination(for: URL.self) { droppedURLs, _ in
            guard entry.isDirectory, let src = droppedURLs.first else { return false }
            let dest = url.appendingPathComponent(src.lastPathComponent)
            guard (try? FileManager.default.moveItem(at: src, to: dest)) != nil else { return false }
            onRefresh(); return true
        } isTargeted: { targeted in
            if entry.isDirectory { isHovered = targeted }
        }
        .contextMenu { contextMenuItems }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color.accentColor.opacity(0.2)
        } else if isHovered {
            Color.primary.opacity(0.07)
        } else {
            Color.clear
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if !entry.isDirectory {
            Button("Open to the Side") { onOpenFile?(url) }
            Divider()
        }

        Button("Cut") {
            controller.selectedPath = entry.path
            clipboard.cut(url)
        }
        .keyboardShortcut("x", modifiers: .command)

        Button("Copy") {
            controller.selectedPath = entry.path
            clipboard.copy(url)
        }
        .keyboardShortcut("c", modifiers: .command)

        Button("Paste") {
            let dir = entry.isDirectory ? url : url.deletingLastPathComponent()
            try? clipboard.paste(into: dir)
            onRefresh()
        }
        .keyboardShortcut("v", modifiers: .command)
        .disabled(!clipboard.hasContent)

        Divider()

        Button("Rename") {
            controller.selectedPath = entry.path
            renamingPath = entry.path
        }
        .keyboardShortcut(.return, modifiers: [])

        Button("Delete", role: .destructive) {
            controller.selectedPath = entry.path
            controller.requestDeleteSelected()
        }
        .keyboardShortcut(.delete, modifiers: .command)

        Divider()

        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.path, forType: .string)
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])

        Button("Copy Relative Path") {
            let rel = relativePath(from: rootPath, to: entry.path)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rel, forType: .string)
        }
        .keyboardShortcut("c", modifiers: [.command, .shift, .option])
    }

    // MARK: - Rename

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != entry.name else { cancelRename(); return }
        let dest = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        try? FileManager.default.moveItem(at: url, to: dest)
        renamingPath = nil
        onRefresh()
    }

    private func cancelRename() {
        renamingPath = nil
        renameText = ""
    }

    // MARK: - Git status

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
        case "D": return 4; case "M": return 3; case "A": return 2; case "U": return 1
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

    // MARK: - Helpers

    private func relativePath(from root: String, to path: String) -> String {
        var r = root
        if !r.hasSuffix("/") { r += "/" }
        return path.hasPrefix(r) ? String(path.dropFirst(r.count)) : path
    }
}
