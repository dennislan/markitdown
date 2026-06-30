import SwiftUI
import WebKit

struct PreviewSheet: NSViewRepresentable {
    let markdownText: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
                font-size: 14px;
                line-height: 1.6;
                padding: 24px;
                max-width: 720px;
                margin: 0 auto;
                color: #1d1d1f;
            }
            @media (prefers-color-scheme: dark) {
                body { color: #f5f5f7; }
                a { color: #4da3ff; }
                code { background: #2d2d2d; color: #f5f5f7; }
                pre { background: #2d2d2d; }
                blockquote { border-left-color: #545456; color: #a1a1a6; }
            }
            h1 { font-size: 2em; border-bottom: 1px solid #d2d2d7; padding-bottom: 0.3em; }
            h2 { font-size: 1.5em; border-bottom: 1px solid #d2d2d7; padding-bottom: 0.3em; }
            h3 { font-size: 1.25em; }
            code { background: #f0f0f5; padding: 2px 6px; border-radius: 4px; font-family: "SF Mono", monospace; font-size: 0.9em; }
            pre { background: #f0f0f5; padding: 16px; border-radius: 8px; overflow-x: auto; }
            pre code { background: none; padding: 0; }
            blockquote { border-left: 4px solid #d2d2d7; padding-left: 16px; color: #6e6e73; margin: 0; }
            table { border-collapse: collapse; width: 100%; margin: 16px 0; }
            th, td { border: 1px solid #d2d2d7; padding: 8px 12px; text-align: left; }
            th { background: #f0f0f5; }
            img { max-width: 100%; height: auto; }
            a { color: #0066cc; text-decoration: none; }
            a:hover { text-decoration: underline; }
        </style>
        </head>
        <body>
        \(renderMarkdown(markdownText))
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func renderMarkdown(_ text: String) -> String {
        var html = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        html = html.replacingOccurrences(of: "^### (.+)$", with: "<h3>$1</h3>", options: .regularExpression)
        html = html.replacingOccurrences(of: "^## (.+)$", with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: "^# (.+)$", with: "<h1>$1</h1>", options: .regularExpression)
        html = html.replacingOccurrences(of: "^> (.+)$", with: "<blockquote>$1</blockquote>", options: .regularExpression)
        html = html.replacingOccurrences(of: "^- (.+)$", with: "<li>$1</li>", options: .regularExpression)
        html = html.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)
        html = html.replacingOccurrences(of: "`(.+?)`", with: "<code>$1</code>", options: .regularExpression)
        html = html.replacingOccurrences(of: "\\[(.+?)\\]\\((.+?)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        html = html.replacingOccurrences(of: "\n\n", with: "</p><p>")
        html = "<p>" + html + "</p>"
        html = html.replacingOccurrences(of: "<p></p>", with: "")

        return html
    }
}
