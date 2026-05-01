import SwiftUI

struct AgentStatusView: View {
    @ObservedObject var resolver: AgentPathResolver
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // 8-bit dark background
            Color(red: 0.04, green: 0.04, blue: 0.14)

            // Scanlines overlay
            Canvas { ctx, size in
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(.black.opacity(0.18)))
                    y += 3
                }
            }
            .allowsHitTesting(false)

            HStack(alignment: .top, spacing: 0) {
                characterPortrait
                dialogBox
            }
            .padding(16)
        }
        .frame(width: 580, height: 300)
    }

    // MARK: - Character

    private var characterPortrait: some View {
        Image("AppIconImage")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 160, height: 268)
            .clipped()
            .pixelBorder(color: .cyan.opacity(0.7), width: 2)
    }

    // MARK: - Dialog box

    private var dialogBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Name tab
            HStack(spacing: 0) {
                Text("▶ AMARA")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.14))
                    .tracking(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.cyan)
                Spacer()
            }

            // Content
            VStack(alignment: .leading, spacing: 12) {
                // Dialog message
                Text(dialogMessage)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                // Agent status rows
                VStack(alignment: .leading, spacing: 6) {
                    agentRow("claude", status: resolver.claude)
                    agentRow("codex",  status: resolver.codex)
                }

                Spacer()

                // Footer buttons
                HStack {
                    if !resolver.isChecking && !resolver.missingAgents.isEmpty {
                        pixelButton("[ RETRY ]", color: .yellow) { resolver.resolve() }
                    }
                    Spacer()
                    if resolver.isChecking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).colorScheme(.dark)
                            Text("SCANNING…")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan.opacity(0.8))
                        }
                    } else if resolver.missingAgents.isEmpty {
                        pixelButton("[ 응, 가자！]", color: .cyan) { dismiss() }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 268)
        .pixelBorder(color: .cyan.opacity(0.7), width: 2)
        .padding(.leading, 8)
    }

    // MARK: - Dialog message (3x3 Eyes 느낌)

    private var dialogMessage: String {
        if resolver.isChecking {
            return "…지금 찾는 중이야.\n기다려줘."
        }
        if resolver.missingAgents.isEmpty {
            return "찾았어…\n클로드도, 코덱스도.\n이제… 같이 가자."
        }
        let names = resolver.missingAgents.map { "'\($0)'" }.joined(separator: "과 ")
        return "…\(names)가 없어.\n설치하고 나서\n다시 불러줘."
    }

    // MARK: - Agent row

    private func agentRow(_ name: String, status: AgentPathResolver.Status) -> some View {
        HStack(spacing: 8) {
            switch status {
            case .checking:
                Text("??")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.yellow)
            case .found:
                Text("OK")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.green)
            case .notFound:
                Text("NG")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.red)
            }

            Text(name)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            if case .found(let path) = status {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else if case .notFound = status {
                Text("NOT FOUND")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
    }

    // MARK: - Pixel button

    private func pixelButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.14))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color)
                .overlay(
                    Rectangle().stroke(color.opacity(0.4), lineWidth: 1).padding(2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pixel border modifier

private extension View {
    func pixelBorder(color: Color, width: CGFloat) -> some View {
        self.overlay(
            ZStack {
                Rectangle().stroke(Color.black, lineWidth: width + 2)
                Rectangle().stroke(color, lineWidth: width)
                Rectangle().stroke(color.opacity(0.3), lineWidth: 1).padding(width + 2)
            }
        )
    }
}
