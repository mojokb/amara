import SwiftUI

/// Right-panel view for a single worktree.
///
/// Top half  — tab bar + agent/file surfaces (claude, codex, vim, markdown viewer).
/// Bottom half — plain shell terminal.
/// The split is user-resizable via NSSplitView (VSplitView).
struct WorkspaceContentView: View {
    @ObservedObject var workspace: WorktreeWorkspace
    @EnvironmentObject private var manager: WorkspaceManager

    @State private var showingLog = false

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTabBar(
                activeTab: $workspace.activeTab,
                fileTabs: workspace.fileTabs,
                claudeNeedsAttention: workspace.claudeNeedsAttention,
                codexNeedsAttention: workspace.codexNeedsAttention,
                onClose: closeFile
            )

            VSplitView {
                agentPanel
                terminalPanel
            }
        }
    }

    // MARK: - Top panel (agents + files)

    private var agentPanel: some View {
        ZStack {
            // Claude session — always in hierarchy, invisible when not active
            Amara.InspectableSurface(surfaceView: workspace.claudeSurface)
                .surfaceVisible(workspace.activeTab == .claude)

            // Codex session
            Amara.InspectableSurface(surfaceView: workspace.codexSurface)
                .surfaceVisible(workspace.activeTab == .codex)

            // File editor tabs
            ForEach(workspace.fileTabs, id: \.self) { url in
                if let surface = workspace.fileSurfaces[url] {
                    let isActive = workspace.activeTab == .file(url)
                    let isMarkdown = url.pathExtension.lowercased() == "md"
                    let viewing = workspace.isViewingMarkdown(url)

                    Amara.InspectableSurface(surfaceView: surface)
                        .surfaceVisible(isActive && !(isMarkdown && viewing))

                    if isMarkdown {
                        MarkdownViewerView(fileURL: url)
                            .opacity(isActive && viewing ? 1 : 0)
                            .allowsHitTesting(isActive && viewing)
                            .accessibilityHidden(!(isActive && viewing))
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) { topTrailingButtons }
        .frame(minHeight: 150)
    }

    // MARK: - Bottom panel (terminal)

    private var terminalPanel: some View {
        Amara.InspectableSurface(surfaceView: workspace.shellSurface)
            .frame(minHeight: 80)
    }

    // MARK: - Top-right overlay buttons

    private var activeAgentSession: AgentSession? {
        switch workspace.activeTab {
        case .claude: return workspace.claudeSession
        case .codex:  return workspace.codexSession
        default:      return nil
        }
    }

    @ViewBuilder
    private var topTrailingButtons: some View {
        HStack(spacing: 6) {
            // Agent log popover — only on agent tabs
            if let session = activeAgentSession {
                let tabName = workspace.activeTab == .claude ? "Claude" : "Codex"
                Button {
                    showingLog.toggle()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .foregroundStyle(showingLog ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
                .help("Show \(tabName) output log")
                .popover(isPresented: $showingLog, arrowEdge: .top) {
                    AgentLogView(session: session, title: "\(tabName) Log")
                        .frame(width: 560, height: 420)
                }
            }

            // Route menu — only on agent tabs
            if workspace.activeTab == .claude || workspace.activeTab == .codex {
                routeMenuButton
            }

            // Markdown toggle — only for .md file tabs
            if case .file(let url) = workspace.activeTab,
               url.pathExtension.lowercased() == "md" {
                let viewing = workspace.isViewingMarkdown(url)
                Button { workspace.toggleMarkdownMode(for: url) } label: {
                    Label(viewing ? "Edit" : "Preview",
                          systemImage: viewing ? "pencil" : "doc.richtext")
                        .font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    // MARK: - Route menu

    private var routeMenuButton: some View {
        let myRoutes = manager.activeRoutes(for: workspace.path)
        let hasAuto  = myRoutes.contains { $0.isAuto }

        return Menu {
            Section("Send output now") {
                Button("claude  →  codex") {
                    manager.routeNow(from: .claude, to: .codex, inPath: workspace.path)
                }
                Button("codex  →  claude") {
                    manager.routeNow(from: .codex, to: .claude, inPath: workspace.path)
                }
            }
            Section("Auto-route on idle") {
                Toggle("claude  →  codex", isOn: autoRouteBinding(from: .claude, to: .codex))
                Toggle("codex  →  claude", isOn: autoRouteBinding(from: .codex, to: .claude))
            }
        } label: {
            Image(systemName: hasAuto
                  ? "arrow.triangle.2.circlepath.circle.fill"
                  : "arrow.triangle.2.circlepath")
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .foregroundStyle(hasAuto ? Color.accentColor : .primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func autoRouteBinding(from: AgentKind, to: AgentKind) -> Binding<Bool> {
        Binding(
            get: {
                manager.routes.contains {
                    $0.worktreePath == workspace.path &&
                    $0.from == from && $0.to == to && $0.isAuto
                }
            },
            set: { on in
                if on {
                    manager.addAutoRoute(from: from, to: to, inPath: workspace.path)
                } else if let r = manager.routes.first(where: {
                    $0.worktreePath == workspace.path &&
                    $0.from == from && $0.to == to && $0.isAuto
                }) {
                    manager.removeRoute(r.id)
                }
            }
        )
    }

    // MARK: - Helpers

    private func closeFile(_ url: URL) {
        workspace.closeFile(url)
    }
}

// MARK: - View modifier helpers

private extension View {
    func surfaceVisible(_ visible: Bool) -> some View {
        self
            .opacity(visible ? 1.0 : 0.0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}
