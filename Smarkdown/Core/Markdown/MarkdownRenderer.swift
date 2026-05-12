import Foundation
import Down

/// Converts Markdown text to HTML using the Down library (cmark under the hood).
///
/// Two render methods:
///   - renderPage(from:)  — full HTML document with embedded CSS; used for the initial
///     WKWebView load so the stylesheet is established.
///   - renderBody(from:)  — just the <body> content; used for incremental updates via
///     JavaScript so the scroll position is preserved between keystrokes.
///
/// CSS is loaded once from the app bundle at first use and cached. Falls back to an
/// empty string if the resource is missing (preview still renders, just unstyled).
enum MarkdownRenderer {

    private static let css: String = {
        guard
            let url = Bundle.main.url(forResource: "preview-styles", withExtension: "css"),
            let content = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return content
    }()

    /// Full HTML document suitable for WKWebView.loadHTMLString(_:baseURL:).
    static func renderPage(from markdown: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        </head>
        <body>
        \(renderBody(from: markdown))
        </body>
        </html>
        """
    }

    /// HTML fragment for the document body — no <html>, <head>, or <style>.
    /// Used for incremental in-place updates via evaluateJavaScript to avoid
    /// reloading the full page (and resetting scroll position) on every keystroke.
    static func renderBody(from markdown: String) -> String {
        let down = Down(markdownString: markdown)
        return (try? down.toHTML()) ?? "<p><em>Render error</em></p>"
    }
}
