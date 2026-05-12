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

    /// True while AppKit is processing a user-initiated text change.
    /// updateNSView checks this flag to avoid overwriting the text view's
    /// content during the brief window between a keystroke and the
    /// @Observable update propagating through SwiftUI.
    var isUserEditing = false

    init(onTextChange: @escaping (String) -> Void) {
        self.onTextChange = onTextChange
    }

    // MARK: - NSTextViewDelegate

    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn range: NSRange,
        replacementString: String?
    ) -> Bool {
        // Raised before AppKit applies the change. Set the flag so
        // updateNSView knows not to touch the text view's string until
        // textDidChange has fired and the ViewModel has been updated.
        isUserEditing = true
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else {
            // Guard failed — clear the flag so updateNSView doesn't get stuck.
            isUserEditing = false
            return
        }
        // This is the hot path — keep it under 1ms.
        // No Markdown parsing, no view updates — just forward the string.
        onTextChange(textView.string)
        isUserEditing = false
    }
}
