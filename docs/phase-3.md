# Phase 3 — Editor Surface

**Goal:** A working NSTextView-based editor in the left pane of the split view, wired to EditorViewModel, with auto-save and correct scrolling behavior.

**Status:** Complete.

---

## What was built

| File | New in Phase 3 |
|---|---|
| `Features/Editor/MarkdownEditorView.swift` | NSViewRepresentable wrapping NSScrollView + NSTextView |
| `Features/Editor/EditorCoordinator.swift` | NSTextViewDelegate — routes keystrokes to ViewModel |
| `Features/Editor/EditorViewModel.swift` | @Observable ViewModel — owns document, drives editor and preview |
| `App/ContentView.swift` | HSplitView layout with editor + preview placeholder |

Phase 3 connects the Phase 2 FileStore/AutoSaveManager to the user-visible editing surface. The Phase 2 data layer was unchanged.

---

## Key design decisions

### NSTextView over SwiftUI TextEditor

SwiftUI's `TextEditor` wraps `NSTextView` internally but exposes only `Binding<String>`. Every keystroke fires the binding, which notifies the `@Observable` ViewModel, which triggers SwiftUI's diff engine, which re-evaluates the view hierarchy. At 120fps on ProMotion displays this is a problem.

`NSTextView` via `NSViewRepresentable` lets us intercept edits through `NSTextViewDelegate.textDidChange`, which runs inside AppKit's own text system. SwiftUI is completely bypassed on the hot path. A keystroke triggers one delegate call; the string is forwarded to the ViewModel; SwiftUI renders only when the ViewModel's `content` property actually changes — and even then, `updateNSView` detects the string hasn't changed externally and does nothing.

See `Features/Editor/README.md` for the complete data flow diagram.

### NSView container pattern for sizing

The most significant implementation challenge in this phase was making the editor fill the available pane height. Three approaches were tried before the correct solution was found:

| Attempt | What it did | Why it failed |
|---|---|---|
| `EditorScrollView` subclass returning `noIntrinsicMetric` | Override `intrinsicContentSize` | SwiftUI's `NSViewRepresentable` does not consult `intrinsicContentSize` in the same way for returned `NSScrollView` types — the collapse still happened |
| `sizeThatFits(_:nsView:context:)` | Explicitly return the proposed size to SwiftUI | Correct in theory, but the HSplitView was not propagating a definite height proposal to begin with |
| `NSView` container + AutoLayout | Pin scroll view inside a wrapper view with constraints | Correct approach, but sizing still collapsed because the root cause was upstream |

**The actual root cause was twofold:**

1. **Saved window state.** macOS persists window frames via `NSWindowRestoration`. An early development session had opened the window at a very small height, and every subsequent launch restored that size. The editor was correctly filling a ~17px window, not a collapsed scroll view. Fix: delete `~/Library/Saved Application State/com.eambabo.Smarkdown.savedState/` during development; add minimum window size constraints for production.

2. **Missing frame on HSplitView.** `HSplitView` (backed by `NSSplitView`) has no intrinsic height. Without `.frame(maxHeight: .infinity)` on the split view itself, SwiftUI did not consistently propagate the full window height to its children. Adding this to ContentView was the production fix.

The NSView container + AutoLayout approach was retained because it is the correct architecture: SwiftUI owns the outer frame; AppKit constraints ensure the scroll view fills it; the two layout systems don't negotiate with each other.

### @Observable over ObservableObject

`EditorViewModel` uses `@Observable` (macOS 14+ / Observation framework). The key difference:

- `@Observable`: SwiftUI tracks which specific properties each view body accessed, and only re-renders that view when those specific properties change.
- `ObservableObject` + `@Published`: any `@Published` change notifies all subscribers of the object, even if the view that changed wasn't the one rendering.

For a typing-intensive app where `content` changes on every keystroke, `@Observable`'s surgical invalidation is essential. A view observing only `document.displayName` (the toolbar title) must not re-render on every keystroke.

### isUserEditing flag

`updateNSView` is called by SwiftUI on every render pass — window resize, toolbar focus, system appearance change, anything. Without protection, every call would do `textView.string = text`, which:
- Resets the insertion point to position 0
- Triggers a full NSLayoutManager re-layout
- Fires another `textDidChange` → ViewModel update → SwiftUI render → loop

The `isUserEditing` flag in `EditorCoordinator` breaks this loop. It is set in `shouldChangeTextIn` (before AppKit applies the change) and cleared in `textDidChange` (after the ViewModel has been updated). `updateNSView` skips all string writes while the flag is true.

A second guard (`textView.string != text`) handles the case where the flag is false but the text hasn't actually changed — for example when a non-editing event triggers a render pass after the ViewModel has already been updated.

---

## Bugs found and fixed

### Bug: Enter key disappeared text (fixed in Phase 3, session 1)

**Symptom:** Pressing Enter caused the editor content to disappear.

**Cause 1:** The toolbar button used `.primaryAction` placement. On macOS, a button with `.primaryAction` can become the window's default key equivalent — triggered by bare Return. Every Enter keystroke was creating a new document, clearing the editor. Fixed by switching to `.automatic` placement with an explicit `.keyboardShortcut("n", modifiers: .command)`.

**Cause 2:** The `isUserEditing` flag was not yet implemented. There was a race window between the keystroke and `@Observable` propagating where `updateNSView` would fire and overwrite `textView.string` with a stale value. Fixed by adding the `isUserEditing` flag.

### Bug: Only one line visible at a time (fixed in Phase 3, session 2)

**Symptom:** Typing and pressing Enter produced a new line, but only the current line was ever visible — lines above scrolled out of view and were not recoverable.

**Root cause:** The window was restoring a saved height of ~17px from an early development session. The editor was correctly filling a 17px window. Additionally, `HSplitView` lacked `maxHeight: .infinity`.

**Diagnostic:** Added `.background(Color.green.opacity(0.3))` to the `MarkdownEditorView` in ContentView. Green color filling the full window height confirmed the SwiftUI layout slot was correct — the container was not the issue.

**Fix:** Delete saved window state + add `.frame(maxWidth: .infinity, maxHeight: .infinity)` to `HSplitView`.

### Bug: isUserEditing could get stuck (fixed in bug review)

**Symptom:** Theoretical — `isUserEditing` is set in `shouldChangeTextIn` but only cleared in `textDidChange`. If AppKit calls `shouldChangeTextIn` without a subsequent `textDidChange` (e.g., rejected by another delegate, or certain input method edge cases), the flag sticks permanently. All subsequent `updateNSView` calls silently skip content updates — document switching would appear broken with no error.

**Fix:** Added `isUserEditing = false` in the `textDidChange` guard's else branch, ensuring the flag is always cleared even if the cast fails.

### Bug: Fragile subview lookup (fixed in bug review)

**Symptom:** `updateNSView` used `container.subviews.first as? NSScrollView` to retrieve the scroll view. If AppKit ever inserts an internal subview at index 0, this silently returns nil and all text updates are dropped.

**Fix:** Replaced the positional lookup with a typed `EditorContainerView` subclass that holds a direct `let scrollView: NSScrollView` property. `updateNSView` receives `EditorContainerView` and accesses `container.scrollView` directly — no searching, no casting, no fragility.

---

## Known issues (deferred)

| Issue | Severity | Planned fix |
|---|---|---|
| Dark mode toggle does not recolor already-typed text | Cosmetic | Phase 8: observe `NSApp.effectiveAppearance` and re-apply `typingAttributes` to the full text storage when appearance changes |
| Two "New Document" clicks within the same second produce the same filename | Very low risk | Phase 8: append a UUID suffix or use `Int64` nanosecond timestamps |
| File I/O is synchronous on the main thread | Non-issue for small docs, V2 concern | Move FileStore to a background actor if Instruments shows blocking on large files |
| `renderedHTML` on EditorViewModel is unused | Placeholder | Phase 4: wired to MarkdownRenderer + PreviewDebouncer |

---

## Testing checklist

Manual tests to run after any change to this phase's files:

- [ ] Type multiple lines — all lines visible, scrollbar appears when content exceeds pane height
- [ ] Press Enter at end of last visible line — editor scrolls to follow cursor
- [ ] ⌘Z works (undo multiple keystrokes)
- [ ] ⌘N creates a new document — editor clears, previous document is saved
- [ ] Switch away from Smarkdown, switch back — content is unchanged, cursor position is preserved
- [ ] Resize the split pane divider — editor fills the new width, text re-wraps
- [ ] Toggle dark mode — editor background and text color update immediately
- [ ] Quit and relaunch — most recent document reopens with correct content

---

## Build notes

No new dependencies in Phase 3. Build with:

```bash
xcodebuild -scheme Smarkdown -configuration Debug build
```

If new Swift files are added, run `xcodegen generate` first — the Xcode project is generated from `project.yml` and does not track files automatically.
