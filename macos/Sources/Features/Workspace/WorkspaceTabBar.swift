import SwiftUI

/// Custom tab bar for the workspace right panel.
/// Shows claude / codex fixed tabs and any open file editor tabs.
struct WorkspaceTabBar: View {
    @Binding var activeTab: WorkspaceTab
    let fileTabs: [URL]
    let webTabs: [UUID]
    let webTabStates: [UUID: WebTabState]
    let claudeNeedsAttention: Bool
    let codexNeedsAttention: Bool
    let onClose: (URL) -> Void
    let onCloseWeb: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                fixedTab(.claude)
                fixedTab(.codex)

                if !fileTabs.isEmpty {
                    Divider()
                        .frame(height: 18)
                        .padding(.horizontal, 4)
                }

                ForEach(fileTabs, id: \.self) { url in
                    fileTab(url: url)
                }

                if !webTabs.isEmpty {
                    Divider()
                        .frame(height: 18)
                        .padding(.horizontal, 4)
                }

                ForEach(webTabs, id: \.self) { id in
                    if let state = webTabStates[id] {
                        webTab(state: state)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 36)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Tab buttons

    private func fixedTab(_ tab: WorkspaceTab) -> some View {
        let isActive = activeTab == tab
        let needsAttention: Bool = switch tab {
        case .claude: claudeNeedsAttention
        case .codex:  codexNeedsAttention
        default:      false
        }
        return Button { activeTab = tab } label: {
            HStack(spacing: 4) {
                Text(tab.displayName)
                    .font(.callout)
                if needsAttention {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
            .foregroundStyle(isActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func webTab(state: WebTabState) -> some View {
        let isActive = activeTab == .web(state.id)
        return HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            ObservingText(state: state)
                .font(.callout)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: 120)

            Button {
                onCloseWeb(state.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { activeTab = .web(state.id) }
    }

    private func fileTab(url: URL) -> some View {
        let isActive = activeTab == .file(url)
        return HStack(spacing: 6) {
            Text(url.lastPathComponent)
                .font(.callout)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            Button {
                onClose(url)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { activeTab = .file(url) }
    }
}

// Tiny view so @ObservedObject can track WebTabState.title changes.
private struct ObservingText: View {
    @ObservedObject var state: WebTabState
    var body: some View { Text(state.title) }
}
