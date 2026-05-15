import SwiftUI
import AppKit

/// Container view returned from makeNSView.
///
/// Holds typed references to the scroll view and classification ruler so
/// updateNSView can reach them without fragile positional subview lookups.
/// AppKit's NSView.tag is read-only (unlike UIKit), so a subclass is the
/// idiomatic alternative.
final class EditorContainerView: NSView {
    let scrollView: NSScrollView
    let rulerView: ClassificationRulerView

    init(scrollView: NSScrollView, rulerView: ClassificationRulerView) {
        self.scrollView = scrollView
        self.rulerView  = rulerView
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
/// on every keystroke and triggers SwiftUI diffs and potential full-hierarchy
/// redraws — too slow for a typing-intensive editor. NSTextView lets us observe
/// edits through the text system's own delegate, bypassing SwiftUI's state
/// machine on the hot path.
///
/// See Features/Editor/README.md for full rationale and data flow.
struct MarkdownEditorView: NSViewRepresentable {
    typealias Coordinator = EditorCoordinator

    /// Current document content. Updated externally only when a new document
    /// is opened — NOT on every keystroke (the coordinator handles that path).
    let text: String

    /// Called by the coordinator on every text change.
    let onTextChange: (String) -> Void

    /// Pre-computed (range, type) pairs for all classifications in the current
    /// document. Drives the gutter ruler dots.
    let classificationMarkers: [ClassificationMarker]

    /// Called after a classification prefix is stripped and the line committed.
    let onClassification: (ClassificationType, String) -> Void

    /// When non-nil, the editor scrolls to the first occurrence of this text
    /// and shows a find indicator. The id field changes on each new request
    /// so the same text string can be re-targeted without being ignored.
    let scrollRequest: EditorViewModel.ScrollRequest?

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> EditorContainerView {
        // Build scroll view + text view manually so we can use MarkdownTextView
        // (our NSTextView subclass). NSTextView.scrollableTextView() does not
        // accept a custom class, so we replicate its key sizing setup here.
        let scrollView = NSScrollView()
        scrollView.borderType            = .noBorder
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true

        let textView = MarkdownTextView()
        textView.minSize    = NSSize(width: 0, height: 0)
        textView.maxSize    = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable   = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask        = [.width]
        textView.textContainer?.widthTracksTextView = true

        textView.isRichText                              = false
        textView.allowsUndo                              = true
        textView.isAutomaticQuoteSubstitutionEnabled     = false
        textView.isAutomaticDashSubstitutionEnabled      = false
        textView.isAutomaticTextReplacementEnabled       = false
        textView.isAutomaticSpellingCorrectionEnabled    = false
        textView.textContainerInset                      = NSSize(width: 16, height: 16)
        textView.backgroundColor                         = NSColor.textBackgroundColor
        textView.typingAttributes                        = Self.defaultTypingAttributes
        textView.delegate                                = context.coordinator

        // Wire classification callback through the coordinator.
        let coordinator = context.coordinator
        textView.onClassification = { type, content in
            coordinator.onClassification?(type, content)
        }

        // Install the classification gutter ruler.
        let rulerView = ClassificationRulerView(scrollView: scrollView, orientation: .verticalRuler)
        rulerView.ruleThickness       = 20
        scrollView.verticalRulerView  = rulerView
        scrollView.hasVerticalRuler   = true
        scrollView.rulersVisible      = true
        rulerView.clientView          = textView

        scrollView.documentView = textView
        return EditorContainerView(scrollView: scrollView, rulerView: rulerView)
    }

    func updateNSView(_ container: EditorContainerView, context: Context) {
        guard let textView = container.scrollView.documentView as? MarkdownTextView else { return }

        // Refresh callbacks so they never call into stale ViewModel state.
        context.coordinator.onTextChange     = onTextChange
        context.coordinator.onClassification = onClassification

        // Update gutter dots — independent of editing state so the ruler
        // always reflects the latest classification data.
        container.rulerView.dots = classificationMarkers.map {
            ClassificationRulerView.Marker(characterRange: $0.range, type: $0.type)
        }

        // Update text content when a new document is opened (not during typing).
        if !context.coordinator.isUserEditing && textView.string != text {
            textView.string           = text
            textView.typingAttributes = Self.defaultTypingAttributes
        }

        // Handle scroll-to-line requests from task navigation.
        // Runs after any text update above so the range search hits the right content.
        if let req = scrollRequest, req.id != context.coordinator.lastScrollRequestID {
            context.coordinator.lastScrollRequestID = req.id
            let nsString = textView.string as NSString
            let range = nsString.range(of: req.text)
            if range.location != NSNotFound {
                textView.scrollRangeToVisible(range)
                textView.showFindIndicator(for: range)
            }
        }
    }

    // MARK: - Appearance

    static let defaultFont: NSFont =
        NSFont(name: "SFMono-Regular", size: 14) ??
        NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    static let defaultTypingAttributes: [NSAttributedString.Key: Any] = [
        .font:            defaultFont,
        .foregroundColor: NSColor.labelColor,
    ]
}
