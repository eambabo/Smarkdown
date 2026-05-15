import AppKit

/// NSTextView subclass that adds Markdown formatting shortcuts and
/// manual classification prefix detection.
///
/// Uses performKeyEquivalent (⌘ key handler) rather than keyDown so the
/// shortcuts integrate cleanly with the responder chain and don't interfere
/// with system shortcuts on unrelated keys.
///
/// All edits go through insertText(_:replacementRange:), which:
///   - calls shouldChangeText(in:replacementString:) — triggers isUserEditing flag
///   - registers the change with the undo manager (⌘Z works)
///   - calls textDidChange — triggers EditorCoordinator → ViewModel → auto-save
final class MarkdownTextView: NSTextView {

    // MARK: - Classification

    /// Set by the coordinator. Called after a classification prefix is
    /// detected, stripped, and the newline inserted — with the trimmed
    /// content text and its type.
    var onClassification: ((ClassificationType, String) -> Void)?

    /// Intercepts Return to detect slash command prefixes at the start of the
    /// current line: `/t ` (task), `/i ` (idea), `/q ` (question). When found:
    ///   1. Replaces the entire line up to the cursor with the trimmed content
    ///      (strips the prefix and any trailing whitespace) — undo-safe.
    ///   2. Inserts the newline via super.
    ///   3. Notifies via onClassification so the coordinator can persist it.
    ///
    /// Prefix detection is only applied when the cursor is at the END of the
    /// line (pressing Enter mid-line is left as normal newline insertion).
    override func insertNewline(_ sender: Any?) {
        let nsString    = string as NSString
        let cursor      = selectedRange().location

        // Find the start of the current paragraph.
        let paragraphStart: Int
        if cursor == 0 {
            paragraphStart = 0
        } else {
            let searchRange = NSRange(location: 0, length: cursor)
            let lastNewline = nsString.range(of: "\n", options: .backwards, range: searchRange)
            paragraphStart  = lastNewline.location != NSNotFound ? lastNewline.location + 1 : 0
        }

        // Only process when cursor is at the end of the line.
        let atEndOfLine: Bool = cursor >= nsString.length ||
            nsString.character(at: cursor) == 10 // '\n'
        guard atEndOfLine else {
            super.insertNewline(sender)
            return
        }

        let lineRange = NSRange(location: paragraphStart, length: cursor - paragraphStart)
        let lineText  = nsString.substring(with: lineRange)
        let lower     = lineText.lowercased()

        let prefixLength: Int
        let classificationType: ClassificationType

        if lower.hasPrefix("/t ") {
            prefixLength       = 3
            classificationType = .task
        } else if lower.hasPrefix("/i ") {
            prefixLength       = 3
            classificationType = .idea
        } else if lower.hasPrefix("/q ") {
            prefixLength       = 3
            classificationType = .question
        } else {
            super.insertNewline(sender)
            return
        }

        let content = String(lineText.dropFirst(prefixLength))
            .trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else {
            super.insertNewline(sender)
            return
        }

        // Replace the full line range with the trimmed content (strips prefix +
        // trailing whitespace). Goes through insertText so undo is registered.
        insertText(content, replacementRange: lineRange)
        super.insertNewline(sender)
        onClassification?(classificationType, content)
    }

    // MARK: - Key handling

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only handle plain ⌘ and ⌘⇧ combinations — ignore ⌘⌥, ⌘⌃, etc.
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let hasShift = flags == [.command, .shift]
        let justCmd  = flags == [.command]

        switch event.charactersIgnoringModifiers {
        case "b" where justCmd:
            applyInlineMarker("**")
            return true
        case "i" where justCmd:
            applyInlineMarker("_")
            return true
        case "k" where justCmd:
            applyInlineMarker("`")
            return true
        case "k" where hasShift:
            applyFencedCodeBlock()
            return true
        case "y" where justCmd:
            // ⌘Y redo — mirrors ⌘⇧Z, the macOS standard.
            // undoManager is the window's shared undo manager; it tracks
            // all text changes because allowsUndo = true on the text view.
            undoManager?.redo()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: - Formatting helpers

    /// Wraps the selection with `marker` on both sides.
    /// Toggles: if the selection is already wrapped, the markers are removed.
    /// If nothing is selected, inserts the paired markers and places the cursor between them.
    private func applyInlineMarker(_ marker: String) {
        let range    = selectedRange()
        let selected = (string as NSString).substring(with: range)

        if range.length == 0 {
            // No selection — insert paired markers, cursor between them.
            insertText(marker + marker, replacementRange: range)
            setSelectedRange(NSRange(location: range.location + marker.count, length: 0))
            return
        }

        let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
        if selected.hasPrefix(marker) && selected.hasSuffix(marker) && !inner.isEmpty {
            // Already wrapped — remove markers.
            insertText(inner, replacementRange: range)
            setSelectedRange(NSRange(location: range.location, length: inner.utf16.count))
        } else {
            // Wrap selection.
            let wrapped = marker + selected + marker
            insertText(wrapped, replacementRange: range)
            setSelectedRange(NSRange(location: range.location, length: wrapped.utf16.count))
        }
    }

    /// Wraps the selection in a fenced code block (```).
    /// Toggles: if the selection is already a fenced block, the fences are removed.
    /// If nothing is selected, inserts an empty block with the cursor on the body line.
    private func applyFencedCodeBlock() {
        let fence = "```"
        let range    = selectedRange()
        let selected = (string as NSString).substring(with: range)

        if range.length == 0 {
            // No selection — insert block, cursor on the empty middle line.
            let block = fence + "\n\n" + fence
            insertText(block, replacementRange: range)
            setSelectedRange(NSRange(location: range.location + fence.count + 1, length: 0))
            return
        }

        let openFence  = fence + "\n"
        let closeFence = "\n" + fence
        let inner = String(selected.dropFirst(openFence.count).dropLast(closeFence.count))

        if selected.hasPrefix(openFence) && selected.hasSuffix(closeFence) && !inner.isEmpty {
            // Already wrapped — remove fences.
            insertText(inner, replacementRange: range)
            setSelectedRange(NSRange(location: range.location, length: inner.utf16.count))
        } else {
            // Wrap selection.
            let wrapped = openFence + selected + closeFence
            insertText(wrapped, replacementRange: range)
            setSelectedRange(NSRange(location: range.location, length: wrapped.utf16.count))
        }
    }
}
