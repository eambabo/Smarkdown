import Foundation

/// Owns the current document and drives the editor surface.
///
/// Why @Observable over ObservableObject:
/// @Observable tracks which specific properties a view accessed and only
/// re-renders when those change. ObservableObject re-renders all subscribers
/// when any @Published property changes. For a typing-intensive editor where
/// `content` changes on every keystroke, @Observable's precision matters.
@MainActor
@Observable
final class EditorViewModel {

    // MARK: - State

    /// The document currently open in the editor. Nil until the user
    /// creates or opens a document.
    private(set) var document: MarkdownDocument?

    /// The live text content of the editor. Updated on every keystroke.
    /// Also used by the preview pane (Phase 4) to trigger re-renders.
    var content: String = ""

    /// Placeholder for the rendered HTML string produced by MarkdownRenderer.
    /// Populated in Phase 4 when PreviewDebouncer is wired up.
    var renderedHTML: String = ""

    // MARK: - Dependencies

    private let fileStore: FileStore
    private let autoSaveManager: AutoSaveManager

    // MARK: - Init

    init(fileStore: FileStore = .shared) {
        self.fileStore = fileStore
        self.autoSaveManager = AutoSaveManager(fileStore: fileStore)
    }

    // MARK: - Text changes

    /// Called by EditorCoordinator on every keystroke.
    /// Updates in-memory state and schedules a debounced save.
    /// The guard prevents unnecessary work when the string hasn't changed
    /// (e.g. pressing an arrow key fires textDidChange but doesn't alter content).
    func handleTextChange(_ newContent: String) {
        guard newContent != content else { return }
        content = newContent

        guard var doc = document else { return }
        doc.content = newContent
        doc.modifiedAt = Date()
        document = doc
        autoSaveManager.schedule(document: doc)
    }

    // MARK: - Document lifecycle

    /// Loads full content for a document selected from the file list.
    /// `metadata` comes from FileStore.loadAll() and has an empty content field;
    /// this method fetches the actual text from disk.
    func openDocument(_ metadata: MarkdownDocument) throws {
        let doc = try fileStore.load(metadata)
        document = doc
        content = doc.content
        autoSaveManager.saveNow() // flush any pending save from the previous document
    }

    /// Creates a new timestamped .md file on disk and opens it in the editor.
    func createNewDocument() throws {
        autoSaveManager.saveNow() // flush any pending save from the previous document
        let doc = try fileStore.createNew()
        document = doc
        content = doc.content
    }

    /// Flushes any pending auto-save immediately.
    /// Call before the window closes or the app terminates.
    func saveNow() {
        autoSaveManager.saveNow()
    }
}
