import SwiftUI

/// Scrollable, searchable log of an agent session's accumulated output.
/// Shown as a popover from the workspace content view.
struct AgentLogView: View {
    @ObservedObject var session: AgentSession
    let title: String

    @State private var strippedLines: [String] = []
    @State private var searchText = ""
    @State private var autoScroll = true

    private var displayLines: [String] {
        guard !searchText.isEmpty else { return strippedLines }
        return strippedLines.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logBody
        }
        .onAppear { rebuild(session.outputBuffer) }
        .onChange(of: session.outputBuffer) { rebuild($0) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Filter", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 140)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 5))

            // Auto-scroll toggle
            Button {
                autoScroll.toggle()
            } label: {
                Image(systemName: autoScroll ? "arrow.down.to.line" : "arrow.down.to.line.circle")
                    .font(.caption)
                    .foregroundStyle(autoScroll ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(autoScroll ? "Auto-scroll: on" : "Auto-scroll: off")

            // Clear buffer label
            Text("\(strippedLines.count) lines")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: - Log body

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayLines.enumerated()), id: \.offset) { idx, line in
                        logLine(line, highlighted: !searchText.isEmpty)
                            .id(idx)
                    }
                    Color.clear.frame(height: 1).id("__bottom__")
                }
                .padding(.vertical, 4)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: strippedLines.count) { _ in
                if autoScroll && searchText.isEmpty {
                    withAnimation(.none) {
                        proxy.scrollTo("__bottom__")
                    }
                }
            }
            .onChange(of: searchText) { _ in
                if searchText.isEmpty, autoScroll {
                    proxy.scrollTo("__bottom__")
                }
            }
        }
    }

    @ViewBuilder
    private func logLine(_ line: String, highlighted: Bool) -> some View {
        if line.isEmpty {
            Color.clear.frame(height: 6)
        } else {
            Text(line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 1)
                .background(highlighted ? Color.accentColor.opacity(0.08) : .clear)
        }
    }

    // MARK: - Buffer processing

    private func rebuild(_ raw: String) {
        let stripped = raw.replacingOccurrences(
            of: #"\x1B\[[0-9;?]*[A-Za-z]"#,
            with: "", options: .regularExpression
        )
        strippedLines = stripped
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .init(charactersIn: "\r")) }
    }
}
