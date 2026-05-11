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
///
/// Sizing strategy: makeNSView returns a plain NSView container. The scroll
/// view is added as a subview with AutoLayout constraints pinning all four
/// edges. SwiftUI controls the container's frame; AppKit constraints ensure
/// the scroll view always fills it. This completely bypasses the
/// intrinsicContentSize negotiation that causes NSScrollView to collapse to
/// one line height when returned directly from makeNSView.
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

    func makeNSView(context: Context) -> NSView {
        // Container: SwiftUI sizes this to fill the layout slot.
        let container = NSView()
        container.autoresizingMask = [.width, .height]

        // scrollableTextView() is Apple's factory for a correctly-linked
        // NSScrollView > NSClipView > NSTextView hierarchy.
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return container
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

        // Pin scroll view to all four edges of the container using AutoLayout.
        // This ensures the scroll view always fills whatever frame SwiftUI
        // assigns to the container, regardless of intrinsicContentSize.
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let scrollView = container.subviews.first as? NSScrollView,
              let textView = scrollView.documentView as? NSTextView else { return }

        // Refresh the coordinator's closure so it never calls into stale state.
        context.coordinator.onTextChange = onTextChange

        // Skip all string manipulation while the user is actively typing.
        guard !context.coordinator.isUserEditing else { return }

        // Only write to textView.string when content changed externally
        // (e.g. a new document was opened). Without this guard, every SwiftUI
        // render pass resets the cursor to position 0.
        if textView.string != text {
            textView.string = text
            textView.typingAttributes = Self.defaultTypingAttributes
        }
    }

    // MARK: - Appearance

    static let defaultFont: NSFont =
        NSFont(name: "SFMono-Regular", size: 14) ??
        NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    static let defaultTypingAttributes: [NSAttributedString.Key: Any] = [
        .font: defaultFont,
        .foregroundColor: NSColor.labelColor,
    ]
}
