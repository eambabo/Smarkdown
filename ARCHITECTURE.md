# Smarkdown — Architecture

## Overview

Smarkdown is a macOS Markdown editor built with Swift and SwiftUI, designed from the ground up for speed: fast capture, fast typing response, and fast rendering. It is also architected to be portable to iPadOS and iOS.

---

## Core Strategy: SwiftUI over AppKit

SwiftUI is used as the **composition layer** — layout, navigation, state management, and the overall view hierarchy are all SwiftUI. AppKit is used **only where SwiftUI's abstractions are insufficient for performance or capability**:

| Component | Why SwiftUI alone isn't enough | AppKit solution |
|---|---|---|
| Editor | `TextEditor` fires a `Binding<String>` on every keystroke, triggering SwiftUI diffs and potential full-hierarchy redraws | `NSTextView` via `NSViewRepresentable` |
| Preview | No native HTML rendering in SwiftUI | `WKWebView` via `NSViewRepresentable` |
| Print | `NSPrintOperation` not accessible from SwiftUI directly | Called from SwiftUI via `NSViewRepresentable` coordinator |

Every AppKit component is wrapped in `NSViewRepresentable`. This is the **portability seam**: on iOS, `NSViewRepresentable` becomes `UIViewRepresentable`, and `NSTextView` / `WKWebView` become `UITextView` / `WKWebView` (which is already cross-platform). The wrapping pattern is identical.

---

## Directory Structure

```
Smarkdown/
├── App/
│   ├── SmarkdownApp.swift       — @main entry point, two WindowGroup scenes
│   └── ContentView.swift        — Root view for the editor window
│
├── Features/                    — Vertical feature slices; each is self-contained
│   ├── Editor/                  — NSTextView wrapper, EditorViewModel (Phase 3)
│   ├── Preview/                 — WKWebView wrapper, PreviewViewModel (Phase 4)
│   ├── FileList/                — Document list window, FileListViewModel (Phase 5)
│   └── Export/                  — Google Docs export sheet, ExportViewModel (Phase 7)
│
├── Core/                        — Business logic with no UI dependency; fully testable
│   ├── Markdown/                — MarkdownRenderer (wraps Down), PreviewDebouncer (Phase 4)
│   ├── FileStore/               — MarkdownDocument model, FileStore, AutoSaveManager (Phase 2)
│   └── Auth/                    — GoogleAuthService, OAuth token management (Phase 7)
│
├── Shared/
│   └── UI/                      — Reusable SwiftUI views and modifiers
│
├── Resources/
│   └── preview-styles.css       — CSS for the WKWebView preview pane
│
└── Supporting Files/
    ├── Info.plist               — App metadata, custom URL scheme for OAuth redirect
    └── Smarkdown.entitlements   — App Sandbox, file access, network entitlements
```

---

## Window Architecture

The app has two independent windows, each configured as a `WindowGroup` scene:

```swift
WindowGroup("Editor", id: "editor")      // 1200×800 default — the editing environment
WindowGroup("Documents", id: "documents") // 380×640 default  — reverse-chrono file list
```

**Why two `WindowGroup` scenes (not a panel or sheet):** The document list must be a peer window — it has its own entry in the Window menu, its own focus behavior, and proper App Sandbox first-responder handling. `NSPanel` floats above all apps and behaves incorrectly under sandboxing. A SwiftUI sheet is modal and tied to the editor lifecycle. `WindowGroup` is the correct, idiomatic solution.

**iOS/iPadOS equivalent:** On iOS, two `WindowGroup` scenes map to separate full-screen scenes (iPadOS multi-window) or a `NavigationSplitView`/`TabView` combining both surfaces in one scene. The ViewModels are OS-agnostic; only the scene configuration needs `#if os(macOS)` guards.

---

## State Management

SwiftUI's **Observation framework** (`@Observable`, available macOS 14+ / iOS 17+) is used instead of `ObservableObject`:

- `@Observable` notifies only the views that accessed a specific property, not all subscribers of the object.
- `ObservableObject` with `@Published` re-renders any view holding `@StateObject` when *any* `@Published` property changes — too broad for a typing-intensive app.

All ViewModels are `@MainActor` for V1. Background actor isolation for file I/O and Markdown rendering is a planned V2 optimization once profiling confirms it is needed.

---

## External Dependencies

Only two external packages are used. The goal is a minimal binary footprint.

| Package | Version | Purpose | Justification |
|---|---|---|---|
| [`Down`](https://github.com/johnxnguyen/Down) | ≥ 0.11.0 | Markdown → HTML rendering | Wraps `cmark` (GitHub's C reference implementation); ~5ms parse time for 1MB docs; iOS-compatible; <100KB binary contribution; single-call API |
| [`AppAuth-iOS`](https://github.com/openid/AppAuth-iOS) | ≥ 1.7.0 | Google OAuth 2.0 | Recommended by Google for native apps; handles PKCE, token refresh, and secure redirect correctly; eliminates ~500 lines of security-critical code |

**What was deliberately excluded:** Alamofire (URLSession + async/await is sufficient for 2 API calls), Combine (Swift Concurrency Task-based debouncing is simpler and more portable), any UI component library (AppKit + SwiftUI covers all needs).

---

## Performance Contracts

Set in Phase 1, validated in Phase 8 with Instruments.

| Operation | Target |
|---|---|
| Keystroke-to-screen latency | < 16ms (one frame at 60fps) |
| Preview re-render debounce | 300ms after last keystroke |
| Cold launch to first editable document | < 1s |
| File list scan (1,000 files) | < 200ms |

---

## iOS/iPadOS Portability Seam

| Component | macOS API | iOS replacement |
|---|---|---|
| Editor view | `NSTextView` + `NSViewRepresentable` | `UITextView` + `UIViewRepresentable` |
| Preview view | `WKWebView` + `NSViewRepresentable` | `WKWebView` + `UIViewRepresentable` (identical) |
| Split pane | `HSplitView` | `HStack` (landscape) / `TabView` (portrait) |
| Print | `NSPrintOperation` on WKWebView | `UIPrintInteractionController` |
| File base URL | `~/Documents/Markdown Files/` (injected) | App sandbox Documents URL (injected) |
| Window management | Two `WindowGroup` scenes | `NavigationSplitView` or `TabView` |
| File monitoring | `DispatchSource` VNODE on directory | Same (`DispatchSource` is portable) |
| OAuth redirect | Custom URL scheme in `Info.plist` | Same (AppAuth supports both platforms) |

The `FileStore` accepts a base URL injected at init — the only platform-specific divergence in Core logic.

---

## Build System

The Xcode project is generated by **[XcodeGen](https://github.com/xcodegen/XcodeGen)** from `project.yml` at the repo root. Do not manually edit `Smarkdown.xcodeproj` — changes will be overwritten on the next `xcodegen generate`. Make structural changes (new files, new targets, new dependencies) in `project.yml` instead.

To regenerate after modifying `project.yml`:
```bash
xcodegen generate
```

---

## Known V1 Limitations & Planned V2 Work

| Limitation | V2 Plan |
|---|---|
| Google Docs export sends raw Markdown text, not structured Docs elements | Parse Markdown AST and emit Docs API `batchUpdate` operations for headings, bold, code blocks |
| No file management (rename, delete, move) | File management UI in document list window |
| No syntax highlighting in editor | `NSTextStorage` delegate with regex-based attribute application |
| `MarkdownRenderer.renderHTML` runs on main thread | Move to `Task.detached` if Instruments shows main-thread blocking on large docs |
| Monospace font is hardcoded (SF Mono 14pt) | Font and size picker in Preferences panel |
| No add-ons or plugin system | Extension point API using Swift protocols |
