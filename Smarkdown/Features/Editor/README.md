# Features/Editor

The editing surface of Smarkdown. The core challenge here is performance: SwiftUI's built-in `TextEditor` is not fast enough for a typing-intensive app, so the editor is built on `NSTextView` wrapped in `NSViewRepresentable`.

---

## Why NSTextView instead of SwiftUI TextEditor

SwiftUI's `TextEditor` internally wraps `NSTextView`, but exposes only a `Binding<String>`. Every character change fires that binding, which triggers SwiftUI's view diffing engine, which can cause redraws of the entire view hierarchy. At 120fps on ProMotion displays this is unacceptable.

`NSTextView` gives direct access to the text system's three layers:

| Layer | Class | Role |
|---|---|---|
| Model | `NSTextStorage` | The actual attributed string on disk |
| Layout | `NSLayoutManager` | Converts model → glyph positions |
| Geometry | `NSTextContainer` | Maps glyphs → screen rectangles |

By using `NSTextViewDelegate.textDidChange(_:)`, we observe edits inside the text system's natural flow — no SwiftUI state machine involved on the hot path. A keystroke triggers one delegate call; we read the string and route it to the ViewModel. SwiftUI is not in the loop until we explicitly update state.

### iOS equivalent

Replace `NSTextView` + `NSViewRepresentable` with `UITextView` + `UIViewRepresentable`. The `Coordinator` pattern is identical — only the class names differ. Wrap the platform-specific code in `#if os(macOS) / #else / #endif`.

---

## Files

| File | Responsibility |
|---|---|
| `MarkdownEditorView.swift` | `NSViewRepresentable` wrapping `NSScrollView > NSTextView`. Configures the text view and handles the `updateNSView` guard. |
| `EditorCoordinator.swift` | `NSTextViewDelegate` implementation. Receives `textDidChange` and routes text to the ViewModel. Kept in its own file to separate AppKit delegate logic from the SwiftUI wrapper. |
| `EditorViewModel.swift` | `@MainActor @Observable` ViewModel. Owns the current document, handles text changes, coordinates with `AutoSaveManager`. |

---

## The updateNSView guard

This is the single most important performance detail in the entire editor:

```swift
func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }
    if textView.string != text {
        textView.string = text
        textView.typingAttributes = Self.defaultTypingAttributes
    }
}
```

`updateNSView` is called by SwiftUI on every render pass — window resize, focus change, toolbar update, anything. Without the guard, every render would call `textView.string = text`, which resets the cursor to position 0 and triggers a full re-layout. The guard short-circuits this: if the text view already has the right content (because the user just typed it), nothing happens.

The guard only allows updates when content changed *externally* — i.e., when a new document is opened and `text` (from the ViewModel) no longer matches what the text view is showing.

---

## NSTextView configuration

| Setting | Value | Why |
|---|---|---|
| `isRichText` | `false` | Store plain text only — prevents RTF attributes from being applied |
| `allowsUndo` | `true` | Required for ⌘Z to work — not enabled by default on all text view configurations |
| `isAutomaticQuoteSubstitutionEnabled` | `false` | Markdown requires straight quotes — curly quotes break code blocks and links |
| `isAutomaticDashSubstitutionEnabled` | `false` | Prevents `--` becoming `—` in Markdown source |
| `isAutomaticTextReplacementEnabled` | `false` | Prevents system text substitutions from corrupting Markdown syntax |
| `isAutomaticSpellingCorrectionEnabled` | `false` | Spell correction would silently alter source text |
| `textContainerInset` | `(16, 16)` | Comfortable reading margins |
| `backgroundColor` | `NSColor.textBackgroundColor` | Dynamic system color — updates automatically for dark mode |
| `typingAttributes` | SF Mono 14pt + `NSColor.labelColor` | Monospace font for source editing; `labelColor` is dynamic for dark mode |

`NSTextView.scrollableTextView()` is used to create the scroll view + text view pair. This class method sets up the sizing relationships (vertical resize, horizontal wrap, scroll view linkage) correctly — more reliable than configuring them manually.

---

## Data flow

```
User types
    │
    ▼ NSTextViewDelegate.textDidChange (on main thread, inside text system)
EditorCoordinator.textDidChange
    │ calls onTextChange(string) — a closure stored from makeCoordinator/updateNSView
    ▼
EditorViewModel.handleTextChange
    │ updates content, document.content, document.modifiedAt
    │ calls AutoSaveManager.schedule(document:)
    ▼
SwiftUI detects @Observable property change (content)
    │
    ▼ updateNSView called
Guard: textView.string == text → no-op ✓ (cursor preserved)
```

---

## EditorViewModel

`@MainActor @Observable` — why `@Observable` over `ObservableObject`:

`@Observable` (Observation framework, macOS 14+) tracks which specific properties a view accessed and only re-renders when those properties change. `ObservableObject` with `@Published` re-renders any subscriber when *any* `@Published` property changes. For a typing-intensive app where `content` changes on every keystroke, `@Observable`'s surgical precision matters.

The ViewModel also exposes `renderedHTML: String` (currently empty — populated in Phase 4) so the preview pane can observe it without knowing about the debounce implementation.
