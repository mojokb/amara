import SwiftUI
import WebKit

/// Renders a local markdown file in a WKWebView with light/dark mode support.
struct MarkdownViewerView: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let md = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        webView.loadHTMLString(Self.html(from: md),
                               baseURL: fileURL.deletingLastPathComponent())
    }

    // MARK: - HTML document

    static func html(from md: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
        :root{--fg:#1d1d1f;--bg:#fff;--border:#ddd;--pre-bg:#f6f8fa;--code-bg:#f0f0f0;--bq:#d0d0d0;--bq-fg:#666;--link:#0066cc;--tr-alt:#fafafa}
        @media(prefers-color-scheme:dark){:root{--fg:#f5f5f7;--bg:#1c1c1e;--border:#3a3a3c;--pre-bg:#2c2c2e;--code-bg:#2c2c2e;--bq:#48484a;--bq-fg:#aaa;--link:#4da3ff;--tr-alt:#252527}}
        *{box-sizing:border-box}
        body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;font-size:14px;line-height:1.7;max-width:800px;margin:0 auto;padding:24px 20px;color:var(--fg);background:var(--bg)}
        h1,h2,h3,h4,h5,h6{margin:1.1em 0 .4em;font-weight:600;line-height:1.3}
        h1{font-size:1.9em;border-bottom:1px solid var(--border);padding-bottom:.3em}
        h2{font-size:1.4em;border-bottom:1px solid var(--border);padding-bottom:.2em}
        h3{font-size:1.15em}h4{font-size:1em}
        pre{background:var(--pre-bg);border-radius:6px;padding:14px 16px;overflow-x:auto;margin:1em 0}
        code{font-family:'SF Mono',Menlo,Consolas,monospace;font-size:.88em;background:var(--code-bg);padding:.15em .4em;border-radius:3px}
        pre code{background:none;padding:0;font-size:.87em}
        blockquote{border-left:4px solid var(--bq);margin:1em 0;padding:4px 16px;color:var(--bq-fg)}
        ul,ol{padding-left:1.8em;margin:.6em 0}li{margin:.2em 0}
        hr{border:none;border-top:1px solid var(--border);margin:1.5em 0}
        a{color:var(--link);text-decoration:none}a:hover{text-decoration:underline}
        img{max-width:100%;border-radius:4px}
        table{border-collapse:collapse;width:100%;margin:1em 0}
        th,td{border:1px solid var(--border);padding:6px 12px;text-align:left}
        th{background:var(--pre-bg);font-weight:600}
        tr:nth-child(even) td{background:var(--tr-alt)}
        p{margin:.7em 0}del{opacity:.6}
        </style></head><body>
        \(bodyHTML(from: md))
        </body></html>
        """
    }

    // MARK: - Block parser

    private static func bodyHTML(from md: String) -> String {
        let lines = md.components(separatedBy: "\n")
        var out = ""
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let fence = String(line.prefix(3))
                i += 1
                var code: [String] = []
                while i < lines.count && !lines[i].hasPrefix(fence) {
                    code.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 }
                out += "<pre><code>\(code.joined(separator: "\n").htmlEscaped)</code></pre>\n"
                continue
            }

            // ATX heading
            if line.hasPrefix("#") {
                let level = min(line.prefix(while: { $0 == "#" }).count, 6)
                let rest = line.dropFirst(level)
                if rest.hasPrefix(" ") {
                    out += "<h\(level)>\(inline(String(rest.dropFirst())))</h\(level)>\n"
                    i += 1; continue
                }
            }

            // Horizontal rule (3+ identical dash/asterisk/underscore, optional spaces)
            let hrChars = trimmed.filter { $0 != " " }
            if hrChars.count >= 3 && (hrChars.allSatisfy({ $0 == "-" }) || hrChars.allSatisfy({ $0 == "*" }) || hrChars.allSatisfy({ $0 == "_" })) && !trimmed.isEmpty {
                out += "<hr>\n"; i += 1; continue
            }

            // Blockquote
            if line.hasPrefix(">") {
                var bq: [String] = []
                while i < lines.count && lines[i].hasPrefix(">") {
                    let l = lines[i]
                    bq.append(l.hasPrefix("> ") ? String(l.dropFirst(2)) : String(l.dropFirst(1)))
                    i += 1
                }
                out += "<blockquote>\(bodyHTML(from: bq.joined(separator: "\n")))</blockquote>\n"
                continue
            }

            // Unordered list
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                out += "<ul>\n"
                while i < lines.count && (lines[i].hasPrefix("- ") || lines[i].hasPrefix("* ") || lines[i].hasPrefix("+ ")) {
                    out += "<li>\(inline(String(lines[i].dropFirst(2))))</li>\n"; i += 1
                }
                out += "</ul>\n"; continue
            }

            // Ordered list
            if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                out += "<ol>\n"
                while i < lines.count,
                      lines[i].trimmingCharacters(in: .whitespaces)
                              .range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                    let item = lines[i].replacingOccurrences(of: #"^\s*\d+\.\s+"#, with: "", options: .regularExpression)
                    out += "<li>\(inline(item))</li>\n"; i += 1
                }
                out += "</ol>\n"; continue
            }

            // Empty line
            if trimmed.isEmpty { i += 1; continue }

            // Paragraph — collect until a block-level element or blank line
            var para: [String] = []
            while i < lines.count {
                let l = lines[i]; let t = l.trimmingCharacters(in: .whitespaces)
                let lhrs = t.filter { $0 != " " }
                if t.isEmpty || l.hasPrefix("#") || l.hasPrefix("```") || l.hasPrefix("~~~")
                    || l.hasPrefix(">") || l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("+ ")
                    || t.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
                    || (lhrs.count >= 3 && (lhrs.allSatisfy({ $0 == "-" }) || lhrs.allSatisfy({ $0 == "*" }))) {
                    break
                }
                para.append(l); i += 1
            }
            if !para.isEmpty {
                out += "<p>\(inline(para.joined(separator: "\n")))</p>\n"
            }
        }
        return out
    }

    // MARK: - Inline formatter

    private static func inline(_ text: String) -> String {
        var s = text
        // Images (before links so ![...](...) is not partially matched)
        s = s.replacingOccurrences(of: #"!\[([^\]]*)\]\(([^)]+)\)"#,
                                   with: "<img alt=\"$1\" src=\"$2\">",
                                   options: .regularExpression)
        // Links
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#,
                                   with: "<a href=\"$2\">$1</a>",
                                   options: .regularExpression)
        // Inline code — scan manually so content is HTML-escaped
        var out = ""
        var idx = s.startIndex
        while idx < s.endIndex {
            if s[idx] == "`", let end = s[s.index(after: idx)...].firstIndex(of: "`") {
                out += "<code>\(String(s[s.index(after: idx)..<end]).htmlEscaped)</code>"
                idx = s.index(after: end)
            } else {
                out.append(s[idx])
                idx = s.index(after: idx)
            }
        }
        s = out
        // Bold+italic, bold, italic, strikethrough
        s = s.replacingOccurrences(of: #"\*\*\*([^*\n]+)\*\*\*"#, with: "<strong><em>$1</em></strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*\*([^*\n]+)\*\*"#,     with: "<strong>$1</strong>",          options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*([^*\n]+)\*"#,          with: "<em>$1</em>",                  options: .regularExpression)
        s = s.replacingOccurrences(of: #"~~([^~\n]+)~~"#,          with: "<del>$1</del>",                options: .regularExpression)
        return s
    }
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
