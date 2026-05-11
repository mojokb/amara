import Foundation
import WebKit
import Combine

final class WebTabState: ObservableObject {
    let id: UUID
    @Published var url: URL
    @Published var title: String
    let webView: WKWebView

    private var observations: [NSKeyValueObservation] = []

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
        self.title = url.host ?? url.absoluteString
        self.webView = WKWebView()

        observations = [
            webView.observe(\.url, options: .new) { [weak self] wv, _ in
                if let u = wv.url { self?.url = u }
            },
            webView.observe(\.title, options: .new) { [weak self] wv, _ in
                self?.title = wv.title?.nilIfEmpty ?? wv.url?.host ?? "Web"
            },
        ]

        webView.load(URLRequest(url: url))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
