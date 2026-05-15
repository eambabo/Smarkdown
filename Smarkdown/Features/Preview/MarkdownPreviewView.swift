import SwiftUI
import WebKit

/// WKWebView-backed Markdown preview pane.
///
/// Rendering strategy — two-phase to preserve scroll position:
///
///   Phase 1 (first load or document switch): loadHTMLString with the full
///   HTML page (doctype + head + CSS + body). This establishes the stylesheet.
///
///   Phase 2 (incremental updates while typing): evaluateJavaScript to swap
///   document.body.innerHTML in place. No page reload = no scroll reset.
///   The body HTML is JSON-encoded before embedding in the script so that
///   quotes, backslashes, and newlines inside the content are always safe.
///
/// The coordinator tracks the last-rendered page HTML so updateNSView can
/// distinguish a document switch (needs full reload) from a typing update
/// (needs incremental update).
struct MarkdownPreviewView: NSViewRepresentable {

    /// Body HTML fragment from PreviewDebouncer / MarkdownRenderer.
    /// On document switch this is a full page; on typing it's body-only.
    let pageHTML: String
    let bodyHTML: String

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        /// The full page HTML that is currently loaded in the web view.
        /// Used to detect document switches that require a full reload.
        var loadedPageHTML: String = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // No-op for now. Hook point for Phase 8 scroll-restoration work.
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        // Disable content JavaScript so raw <script> blocks in user Markdown
        // cannot execute in the preview. This does NOT affect evaluateJavaScript
        // calls made by the host app — those are privileged and bypass this setting.
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Match the system background so the area below short documents
        // doesn't flash white in dark mode.
        webView.underPageBackgroundColor = .textBackgroundColor
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator

        if pageHTML != coordinator.loadedPageHTML {
            // Document switched or first load — full reload to establish CSS.
            coordinator.loadedPageHTML = pageHTML
            webView.loadHTMLString(pageHTML, baseURL: nil)
        } else if !bodyHTML.isEmpty {
            // Incremental typing update — swap body content without reloading.
            // JSON-encode the HTML so any quotes/slashes inside are escaped safely.
            guard let data = try? JSONSerialization.data(withJSONObject: bodyHTML, options: .fragmentsAllowed),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("document.body.innerHTML = \(json)")
        }
    }
}
