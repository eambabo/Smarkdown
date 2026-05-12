import SwiftUI
import AppKit

/// Container view returned from makeNSView.
///
/// Holds a typed reference to the scroll view so updateNSView can retrieve
/// it without a fragile positional subview lookup. AppKit's NSView.tag is
/// read-only (unlike UIKit), so a subclass is the idiomatic alternative.
final class EditorContainerView: NSView {
    let scrollView: NSScrollView

    init(scrollView: NSScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// SwiftUI wrapper around NSScrollView > NSTextView.
///
/// SwiftUI's built-in TextEditor exposes only a Binding<String>, which fires
/// on every keystroke and triggers SwiftUI view diffing — too slow for a
/// typing-intensive editor. NSTextView lets us observe edits through the text
/// system's own delegate, bypassing SwiftUI's state machine on the hot path.
///
/// See Features/Editor/README.md for full rationale and data flow.
///
/// Sizing strategy: makeNSView returns an EditorContainerView. The scroll
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

    func makeNSView(context: Context) -> EditorContainerView {
        // Build the scroll view + text view manually so we can use MarkdownTextView
        // (our NSTextView subclass). NSTextView.scrollableTextView() does not accept
        // a custom class, so we replicate its key sizing setup here.
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = MarkdownTextView()
        // Sizing: text view starts small and grows vertically as content is added.
        // maxSize is effectively unlimited — the layout manager extends the frame.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        // Width tracks the scroll view's content area so text wraps at the pane edge.
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

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

        scrollView.documentView = textView
        return EditorContainerView(scrollView: scrollView)
    }

    func updateNSView(_ container: EditorContainerView, context: Context) {
        guard let textView = container.scrollView.documentView as? MarkdownTextView else { return }

        // Refresh the coordinator's closure so it never calls into stale state.
        // SwiftUI reuses coordinators across renders, but the closure is new each time.
        context.coordinator.onTextChange = onTextChange

        // Skip all string manipulation while the user is actively typing.
        // isUserEditing is set by shouldChangeTextIn and cleared in textDidChange.
        // This prevents a race where SwiftUI renders with a stale `text` value
        // during the brief window between a keystroke and @Observable propagating.
        guard !context.coordinator.isUserEditing else { return }

        // Only write to textView.string when content changed externally
        // (e.g. a new document was opened). Without this guard, every SwiftUI
        // render pass resets the cursor to position 0.
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
