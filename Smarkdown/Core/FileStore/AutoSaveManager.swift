import AppKit

/// Debounces saves so rapid typing doesn't hammer the disk.
///
/// Design: on each content change, cancel the previous pending save Task and
/// start a new one that sleeps 1.5 seconds before writing. If the app
/// resigns active (user switches away), the pending task is cancelled and
/// the document is saved immediately.
///
/// The 1.5s debounce is intentionally longer than the preview debounce (300ms)
/// because disk I/O has no user-visible benefit from being faster.
@MainActor
final class AutoSaveManager {
    private var pendingTask: Task<Void, Never>?
    private var observerTask: Task<Void, Never>?
    private var currentDocument: MarkdownDocument?
    private let fileStore: FileStore

    init(fileStore: FileStore = .shared) {
        self.fileStore = fileStore
        observeResignActive()
    }

    deinit {
        // Task is Sendable — safe to cancel from nonisolated deinit.
        pendingTask?.cancel()
        observerTask?.cancel()
    }

    // MARK: - Public API

    /// Call this whenever the document content changes.
    /// Cancels any pending save and schedules a new one 1.5 seconds out.
    func schedule(document: MarkdownDocument) {
        currentDocument = document
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            self.flush()
        }
    }

    /// Cancels any pending debounced save and writes to disk immediately.
    /// Called automatically when the app resigns active, and available
    /// for callers that need an explicit save (e.g. before closing a window).
    func saveNow() {
        pendingTask?.cancel()
        pendingTask = nil
        flush()
    }

    // MARK: - Private

    private func flush() {
        guard let document = currentDocument else { return }
        do {
            try fileStore.save(document)
        } catch {
            // V1: log save failures to the console so they surface during development.
            // V2: surface to the user via an error bar or status indicator.
            assertionFailure("AutoSaveManager: save failed — \(error)")
        }
    }

    private func observeResignActive() {
        // Capture the notification name here while on @MainActor —
        // NSApplication is @MainActor so its static properties can't be
        // accessed from inside a non-isolated Task closure.
        let name = NSApplication.willResignActiveNotification
        observerTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: name) {
                self?.saveNow()
            }
        }
    }
}
