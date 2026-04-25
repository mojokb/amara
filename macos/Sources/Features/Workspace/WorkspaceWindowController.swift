import Cocoa
import SwiftUI
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

        let root = WorkspaceRootView(ghostty: ghostty, manager: manager)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = window.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(hosting)
        self.hostingView = hosting
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Surface cleanup is handled by WorktreeWorkspace deinit via ARC.
    }
}
