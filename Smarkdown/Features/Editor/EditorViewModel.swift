import Foundation

/// Owns the current document and drives both the editor and preview surfaces.
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
    var content: String = ""

    /// Full HTML page for the preview pane (includes doctype, head, CSS).
    /// Set immediately when a document is opened so the first render is instant.
    /// Serves as the "baseline" the web view loads on a document switch.
    private(set) var previewPageHTML: String = ""

    /// Debounced body HTML fragment. Nil means "no incremental update pending."
    /// The preview view uses this to swap body content without reloading the page.
    private(set) var previewBodyHTML: String = ""

    // MARK: - Dependencies

    private let fileStore: FileStore
    private let autoSaveManager: AutoSaveManager
    private let previewDebouncer: PreviewDebouncer

    // MARK: - Init

    init(fileStore: FileStore = .shared) {
        self.fileStore = fileStore
        self.autoSaveManager = AutoSaveManager(fileStore: fileStore)
        self.previewDebouncer = PreviewDebouncer()
    }

    // MARK: - Text changes

    /// Called by EditorCoordinator on every keystroke.
    /// Updates in-memory state, schedules a debounced save, and schedules
    /// a debounced preview render (300ms).
    func handleTextChange(_ newContent: String) {
        guard newContent != content else { return }
        content = newContent

        guard var doc = document else { return }
        doc.content = newContent
        doc.modifiedAt = Date()
        document = doc
        autoSaveManager.schedule(document: doc)

        previewDebouncer.schedule(markdown: newContent) { [weak self] bodyHTML in
            self?.previewBodyHTML = bodyHTML
        }
    }

    // MARK: - Document lifecycle

    /// Loads full content for a document selected from the file list.
    /// Renders an immediate (non-debounced) preview so the pane is populated
    /// the moment the document opens, not 300ms later.
    func openDocument(_ metadata: MarkdownDocument) throws {
        let doc = try fileStore.load(metadata)
        document = doc
        content = doc.content
        renderPreviewImmediately(markdown: doc.content)
        autoSaveManager.saveNow()
    }

    /// Creates a new timestamped .md file on disk and opens it in the editor.
    func createNewDocument() throws {
        autoSaveManager.saveNow()
        let doc = try fileStore.createNew()
        document = doc
        content = doc.content
        renderPreviewImmediately(markdown: doc.content)
    }

    /// Flushes any pending auto-save immediately.
    func saveNow() {
        autoSaveManager.saveNow()
    }

    // MARK: - Private

    /// Renders and sets the full page HTML synchronously — used on document
    /// open/create where we want the preview populated instantly, not after a
    /// 300ms debounce window. Also resets previewBodyHTML so the web view does
    /// a full reload (picking up the new page) rather than an incremental update.
    private func renderPreviewImmediately(markdown: String) {
        previewPageHTML = MarkdownRenderer.renderPage(from: markdown)
        previewBodyHTML = ""
    }
}
