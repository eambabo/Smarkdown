import AppKit

/// NSTextView subclass that adds Markdown formatting keyboard shortcuts.
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
