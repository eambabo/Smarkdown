import Foundation

/// Debounces Markdown→HTML rendering so the preview only re-renders 300ms
/// after the user stops typing, not on every keystroke.
///
/// Same Task-based debounce pattern as AutoSaveManager: cancel the previous
/// Task on each new call, start a fresh one that sleeps before doing work.
/// If the user types again within 300ms, the Task is cancelled and replaced.
///
/// The 300ms window is chosen to feel responsive (preview "snaps in" quickly)
/// while avoiding render work during fast typing bursts.
@MainActor
final class PreviewDebouncer {

    private var pendingTask: Task<Void, Never>?

    deinit {
        pendingTask?.cancel()
    }

    /// Schedule a preview render 300ms from now.
    /// If called again before the timer fires, the previous render is cancelled.
    ///
    /// - Parameters:
    ///   - markdown: The current raw Markdown source.
    ///   - onRendered: Called on the main actor with the rendered HTML body fragment
    ///     when the debounce window elapses. The caller is responsible for deciding
    ///     whether to do a full page reload or an incremental body update.
    func schedule(markdown: String, onRendered: @escaping (String) -> Void) {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, self != nil else { return }
            let body = MarkdownRenderer.renderBody(from: markdown)
            onRendered(body)
        }
    }
}
