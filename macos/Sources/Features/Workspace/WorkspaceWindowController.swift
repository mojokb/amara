import Cocoa
import SwiftUI
import Combine
import AmaraKit

/// A workspace window that shows git worktrees on the left and
/// per-worktree AI agent sessions (claude/codex) on the right.
///
/// This is a sibling of TerminalController, not a subclass.
/// It manages its own surface lifecycle independent of the split-tree model.
class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
    let ghostty: Amara.App
    let manager: WorkspaceManager

    private var hostingView: NSHostingView<WorkspaceRootView>?
    private var titleCancellable: AnyCancellable?
    private var zoomEventMonitor: Any?

    static func newWindow(_ ghostty: Amara.App) -> WorkspaceWindowController {
        let c = WorkspaceWindowController(ghostty: ghostty)
        c.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        return c
    }

    init(ghostty: Amara.App) {
        self.ghostty = ghostty
        self.manager = WorkspaceManager(ghostty: ghostty)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Amara Workspace"
        window.minSize = NSSize(width: 700, height: 450)

        // Disable native macOS tabbing — we manage our own tab UI.
        window.tabbingMode = .disallowed

        super.init(window: window)

        window.delegate = self
        window.center()

        // Update window title when repo or selected worktree changes.
        titleCancellable = Publishers.CombineLatest(
            manager.$repositoryPath,
            manager.$selectedPath
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] repoPath, selectedPath in
            guard let window = self?.window else { return }
            let home = FileManager.default.homeDirectoryForCurrentUser.path

            func shortenPath(_ path: String) -> String {
                path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
            }

            if let selected = selectedPath {
                let repoName = repoPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Amara"
                window.title = "\(repoName)  —  \(shortenPath(selected))"
                window.representedURL = URL(fileURLWithPath: selected)
            } else if let repo = repoPath {
                window.title = shortenPath(repo)
                window.representedURL = URL(fileURLWithPath: repo)
            } else {
                window.title = "Amara Workspace"
                window.representedURL = nil
            }
            window.subtitle = ""
        }

        let root = WorkspaceRootView(ghostty: ghostty, manager: manager)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = window.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(hosting)
        self.hostingView = hosting

        zoomEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handleZoomKey(event) }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let m = zoomEventMonitor { NSEvent.removeMonitor(m); zoomEventMonitor = nil }
    }

    // MARK: - Zoom

    @MainActor
    private func handleZoomKey(_ event: NSEvent) -> NSEvent? {
        guard window?.isKeyWindow == true else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return event }

        let key = event.charactersIgnoringModifiers ?? ""
        let action: String
        if flags.contains(.shift) && key == "=" {
            action = "increase_font_size:1"
        } else if key == "-" {
            action = "decrease_font_size:1"
        } else {
            return event
        }

        guard let surface = manager.activeSurface else { return event }
        ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
        return nil
    }
}
