import SwiftUI
import WebKit

/// Full-featured WebKit browser panel for a workspace tab.
struct WebBrowserView: View {
    @ObservedObject var state: WebTabState
    @State private var addressText: String = ""
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            WebViewRepresentable(webView: state.webView)
        }
        .onReceive(state.$url) { url in
            if !isEditing {
                addressText = url.absoluteString
            }
        }
        .onAppear {
            addressText = state.url.absoluteString
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button { state.webView.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!state.webView.canGoBack)

            Button { state.webView.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!state.webView.canGoForward)

            Button { state.webView.reload() } label: {
                Image(systemName: "arrow.clockwise")
            }

            TextField("URL", text: $addressText, onEditingChanged: { editing in
                isEditing = editing
            }, onCommit: {
                navigate(to: addressText)
            })
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func navigate(to input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let urlString = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        guard let url = URL(string: urlString) else { return }
        state.webView.load(URLRequest(url: url))
    }
}

// MARK: - NSViewRepresentable wrapper

private struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
