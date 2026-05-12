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
| `MarkdownEditorView.swift` | `NSViewRepresentable` returning an `EditorContainerView` (typed NSView subclass) with the scroll view pinned inside via AutoLayout. Configures the text view and handles the `updateNSView` guard. |
| `EditorCoordinator.swift` | `NSTextViewDelegate` implementation. Receives `textDidChange` and routes text to the ViewModel. Kept in its own file to separate AppKit delegate logic from the SwiftUI wrapper. |
| `EditorViewModel.swift` | `@MainActor @Observable` ViewModel. Owns the current document, handles text changes, coordinates with `AutoSaveManager`. |

---

## Sizing strategy

`NSScrollView` has a subtle interaction with SwiftUI's layout engine: its `intrinsicContentSize` is driven by the document view's content size, not the available space. For an empty or short document, this collapses the scroll view to one line of height. SwiftUI honours this intrinsic size even when the parent requests `maxHeight: .infinity`.

The fix is a two-part approach:

**1. EditorContainerView pattern**

`makeNSView` returns an `EditorContainerView` — a typed `NSView` subclass — instead of the `NSScrollView` directly. The subclass holds a `let scrollView: NSScrollView` property and pins it to all four edges of the container in its initializer:

```swift
final class EditorContainerView: NSView {
    let scrollView: NSScrollView
    init(scrollView: NSScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}
```

SwiftUI owns the outer frame; AppKit constraints ensure the scroll view always fills it. `updateNSView` receives `EditorContainerView` and accesses `container.scrollView` directly — no subview searching, no casting. This is safer than `NSView.tag` (which is read-only in AppKit) or a positional `subviews[0]` lookup.

**2. HSplitView frame in ContentView**

`HSplitView` (backed by `NSSplitView`) has no intrinsic height of its own. Without an explicit `.frame(maxHeight: .infinity)` on the `HSplitView`, SwiftUI may not propagate the full window height to its children:

```swift
HSplitView { ... }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
```

Both fixes are required. The AutoLayout approach alone does not work if the SwiftUI layout never proposes full height to the container.

---

## The updateNSView guard

`updateNSView` is called by SwiftUI on every render pass — window resize, focus change, toolbar update, anything. Two guards prevent it from corrupting editor state:

**Guard 1 — isUserEditing**

```swift
guard !context.coordinator.isUserEditing else { return }
```

Set in `shouldChangeTextIn` (before AppKit applies the change) and cleared in `textDidChange` (after the ViewModel is updated). Prevents a race where SwiftUI renders with a stale `text` value during the brief window between a keystroke and `@Observable` propagating.

**Guard 2 — string equality**

```swift
if textView.string != text {
    textView.string = text
    textView.typingAttributes = Self.defaultTypingAttributes
}
```

Only writes to the text view when content changed *externally* (e.g. a new document was opened). Without this, every render pass calls `textView.string = text`, which resets the cursor to position 0 and triggers a full re-layout. Setting `.string` also clears typing attributes, so they must be restored afterward.

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

`NSTextView.scrollableTextView()` is used to create the scroll view + text view pair. This class method correctly sets up the sizing relationships (vertical resize, horizontal wrap, scroll view linkage) between the two views.

---

## Data flow

```
User types
    │
    ▼ NSTextViewDelegate.shouldChangeTextIn → isUserEditing = true
    ▼ NSTextViewDelegate.textDidChange (on main thread, inside text system)
EditorCoordinator.textDidChange
    │ calls onTextChange(string) — isUserEditing = false
    ▼
EditorViewModel.handleTextChange
    │ updates content, document.content, document.modifiedAt
    │ calls AutoSaveManager.schedule(document:)
    ▼
SwiftUI detects @Observable property change (content)
    │
    ▼ updateNSView called
Guard 1: isUserEditing == false ✓
Guard 2: textView.string == text → no-op ✓ (cursor preserved)
```

---

## EditorViewModel

`@MainActor @Observable` — why `@Observable` over `ObservableObject`:

`@Observable` (Observation framework, macOS 14+) tracks which specific properties a view accessed and only re-renders when those properties change. `ObservableObject` with `@Published` re-renders any subscriber when *any* `@Published` property changes. For a typing-intensive app where `content` changes on every keystroke, `@Observable`'s surgical precision matters.

The ViewModel also exposes `renderedHTML: String` (currently empty — populated in Phase 4) so the preview pane can observe it without knowing about the debounce implementation.
