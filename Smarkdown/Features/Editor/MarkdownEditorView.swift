import SwiftUI
import AppKit

/// SwiftUI wrapper around NSScrollView > NSTextView.
///
/// SwiftUI's built-in TextEditor exposes only a Binding<String>, which fires
/// on every keystroke and triggers SwiftUI view diffing — too slow for a
/// typing-intensive editor. NSTextView lets us observe edits through the text
/// system's own delegate, bypassing SwiftUI's state machine on the hot path.
///
/// See Features/Editor/README.md for full rationale and data flow.
struct MarkdownEditorView: NSViewRepresentable {
    typealias Coordinator = EditorCoordinator

    /// Current document content. Updated externally only when a new document
    /// is opened — NOT on every keystroke (the coordinator handles that path).
    let text: String

    /// Called by the coordinator on every text change. Kept as a closure so
    /// it is refreshed in updateNSView without recreating the coordinator.
    let onTextChange: (String) -> Void

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // scrollableTextView() creates a correctly configured NSScrollView +
        // NSTextView pair: vertical resize, horizontal word-wrap, and scroll
        // view linkage are all set up by Apple's own factory method.
        let scrollView = NSTextView.scrollableTextView()

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.typingAttributes = Self.defaultTypingAttributes
        textView.delegate = context.coordinator

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Refresh the coordinator's closure so it never calls into stale state.
        // SwiftUI reuses coordinators across renders, but the closure is new each time.
        context.coordinator.onTextChange = onTextChange

        // THE CRITICAL GUARD: only write to textView.string when the content
        // changed externally (e.g. a new document was opened). Without this,
        // every SwiftUI render pass resets the cursor to position 0.
        if textView.string != text {
            textView.string = text
            // Restore typing attributes — setting .string clears them.
            textView.typingAttributes = Self.defaultTypingAttributes
        }
    }

    // MARK: - Appearance

    /// SF Mono at 14pt for source editing. Falls back to the system monospace
    /// font if SF Mono is somehow unavailable (e.g. unusual system configuration).
    static let defaultFont: NSFont =
        NSFont(name: "SFMono-Regular", size: 14) ??
        NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    /// Dynamic colors (labelColor, textBackgroundColor) update automatically
    /// when the user switches between light and dark mode.
    static let defaultTypingAttributes: [NSAttributedString.Key: Any] = [
        .font: defaultFont,
        .foregroundColor: NSColor.labelColor,
    ]
}
