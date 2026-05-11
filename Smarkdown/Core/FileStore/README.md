# Core/FileStore

Handles all file I/O for Smarkdown. Three files, no external dependencies.

---

## MarkdownDocument

A value type (`struct`) representing a single `.md` file. Key design decisions:

- **`id: URL { fileURL }`** — the file URL is the stable identity. Using a `UUID` would generate a different ID each time `loadAll()` runs, breaking SwiftUI list diffing and any identity-based state. The file URL is always unique and stable for a given file.
- **`content` starts empty** — `loadAll()` populates metadata only. Content is fetched lazily via `FileStore.load(_:)` when the user opens a document. This keeps the file list fast regardless of how large individual documents are.
- **`displayName`** — strips the `.md` extension for UI display. Computed, not stored.

---

## FileStore

`@MainActor final class` — the single source of truth for file I/O.

### Why `@MainActor` for file I/O?

For V1, Markdown documents are small (< 1MB typical). Reading/writing them synchronously on the main thread takes under 5ms — imperceptible. Making `FileStore` `@MainActor` avoids the complexity of async actor hops, background queue management, and thread-safe state across the app.

V2 path: if Instruments shows main-thread blocking (documents > ~5MB or slow storage), move `FileStore` to a custom `actor` and mark its methods `async`. The call sites — `EditorViewModel` and `AutoSaveManager` — would need `await`, but the logic stays the same.

### iOS portability

`FileStore` accepts an optional `baseDirectory: URL` at init:

```swift
// macOS (default)
FileStore.shared  // ~/Documents/Markdown Files/

// iOS — pass this at app startup
FileStore(baseDirectory: FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask)[0])
```

The rest of `FileStore` is identical on both platforms.

### Atomic writes

`save(_:)` uses `String.write(to:atomically:encoding:)` with `atomically: true`. This writes to a temp file in the same directory, then renames it into place. The rename is atomic at the filesystem level, so the file is never left in a partial state if the app crashes mid-write.

### Methods

| Method | Description |
|---|---|
| `loadAll()` | Scans `baseDirectory` for `.md` files using a single `contentsOfDirectory` call (includes metadata). Returns documents sorted reverse-chronologically by `modifiedAt`. Content is empty — call `load(_:)` to get it. |
| `load(_:)` | Reads full content from disk. Call when user opens a document. |
| `save(_:)` | Atomically writes `document.content` to `document.fileURL`. |
| `createNew()` | Creates a timestamped empty file (`YYYY-MM-DD-HHmmss.md`), saves it, and returns the new document. |

---

## AutoSaveManager

`@MainActor final class` — debounces saves so rapid typing doesn't hammer the disk.

### Debounce mechanism

Uses Swift Concurrency's `Task` as a debounce timer:

```
On content change → schedule(document:)
  1. Cancel the previous pending Task (if any)
  2. Start a new Task that sleeps 1.5 seconds
  3. After sleep, if not cancelled, call flush()
```

This is the Swift-native debounce pattern. No Combine, no DispatchWorkItem, no Timer — just structured concurrency.

### Why 1.5 seconds?

- Preview debounce is 300ms (user-visible, needs to feel responsive)
- Auto-save debounce is 1.5s (disk I/O, no visual feedback needed)
- 1.5s is aggressive enough to protect against data loss while avoiding a write on every pause between words

### Immediate save on resign

`NSApplication.willResignActiveNotification` triggers `saveNow()`, which cancels the pending Task and flushes immediately. This ensures content is never lost when the user switches to another app.

The observer is implemented as a long-lived `Task { @MainActor in for await _ in ... }` loop over `NotificationCenter`'s async notification sequence. This pattern was chosen over `NotificationCenter.addObserver(forName:queue:using:)` for a Swift 6 concurrency reason: the callback-based `addObserver` returns an `NSObjectProtocol`, which is not `Sendable`. Storing it as a property and releasing it from `deinit` (which is nonisolated) would be a compiler error in Swift 6. `Task` is `Sendable`, so it can safely be cancelled from `deinit`.

```swift
// Safe in Swift 6 — Task is Sendable
deinit {
    pendingTask?.cancel()
    observerTask?.cancel()
}
```

### Error handling

`flush()` catches save errors and calls `assertionFailure` in debug builds, which crashes the app in development so failures don't go unnoticed. In release builds, `assertionFailure` is a no-op and the save is silently skipped. V2 should surface persistent failures to the user via a status bar indicator or alert.

### iOS portability

Replace `NSApplication.willResignActiveNotification` with `UIApplication.willResignActiveNotification`. Everything else is identical.
