import AppKit

/// NSTextViewDelegate implementation for MarkdownEditorView.
///
/// Kept in its own file to separate AppKit delegate logic from the SwiftUI
/// NSViewRepresentable wrapper. The coordinator is created once by SwiftUI
/// and reused across renders — only its `onTextChange` closure is refreshed
/// in updateNSView to stay in sync with the latest ViewModel state.
final class EditorCoordinator: NSObject, NSTextViewDelegate {
    /// Updated on every updateNSView call so the closure always captures
    /// the current ViewModel state without retaining a stale copy.
    var onTextChange: (String) -> Void

    init(onTextChange: @escaping (String) -> Void) {
        self.onTextChange = onTextChange
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        // This is the hot path — keep it under 1ms.
        // No Markdown parsing, no view updates — just forward the string.
        onTextChange(textView.string)
    }
}
