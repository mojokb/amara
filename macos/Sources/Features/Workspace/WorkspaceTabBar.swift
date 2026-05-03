import SwiftUI

/// Custom tab bar for the workspace right panel.
/// Shows claude / codex fixed tabs and any open file editor tabs.
struct WorkspaceTabBar: View {
    @Binding var activeTab: WorkspaceTab
    let fileTabs: [URL]
    let claudeNeedsAttention: Bool
    let codexNeedsAttention: Bool
    let workflowIsRunning: Bool
    let onClose: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                fixedTab(.claude)
                fixedTab(.codex)
                fixedTab(.workflow)

                if !fileTabs.isEmpty {
                    Divider()
                        .frame(height: 18)
                        .padding(.horizontal, 4)
                }

                ForEach(fileTabs, id: \.self) { url in
                    fileTab(url: url)
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
        case .claude:    claudeNeedsAttention
        case .codex:     codexNeedsAttention
        default:         false
        }
        let dotColor: Color = tab == .workflow ? .orange : .accentColor
        let showDot: Bool   = tab == .workflow ? workflowIsRunning : needsAttention
        return Button { activeTab = tab } label: {
            HStack(spacing: 4) {
                Text(tab.displayName)
                    .font(.callout)
                if showDot {
                    Circle()
                        .fill(dotColor)
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
