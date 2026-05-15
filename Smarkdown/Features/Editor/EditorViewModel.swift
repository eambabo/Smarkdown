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

    // MARK: - Right panel

    enum RightPanel: Equatable {
        case preview, ideas, tasks
    }

    /// The panel currently shown to the right of the editor. Nil collapses the panel area.
    var rightPanel: RightPanel? = .preview

    /// Toggles the given panel on; if it is already active, collapses the panel area.
    func togglePanel(_ panel: RightPanel) {
        rightPanel = (rightPanel == panel) ? nil : panel
    }

    // MARK: - State

    /// The document currently open in the editor. Nil until the user
    /// creates or opens a document.
    private(set) var document: MarkdownDocument?

    /// Stable identity of the active document — only changes on document switch,
    /// not on every keystroke. FileListView observes this to sync selection and
    /// reload without re-rendering on every content change.
    private(set) var activeDocumentID: URL? = nil

    /// The live text content of the editor. Updated on every keystroke.
    var content: String = ""

    /// Non-observable mirrors of `content` and `document` used in handleTextChange's guards.
    ///
    /// The @Observable macro wraps property getters with ObservationRegistrar.access,
    /// which modifies an internal tracking dictionary. On macOS 26, this dictionary
    /// resize crashes when a getter is called from an AppKit notification callback
    /// (not a SwiftUI render pass). @ObservationIgnored bypasses the macro wrapper
    /// so these properties are plain ivars — safe to read from any context.
    @ObservationIgnored private var _contentSnapshot: String = ""
    @ObservationIgnored private var _documentSnapshot: MarkdownDocument?

    /// Full HTML page for the preview pane (includes doctype, head, CSS).
    /// Set immediately when a document is opened so the first render is instant.
    /// Serves as the "baseline" the web view loads on a document switch.
    private(set) var previewPageHTML: String = ""

    /// Debounced body HTML fragment. Nil means "no incremental update pending."
    /// The preview view uses this to swap body content without reloading the page.
    private(set) var previewBodyHTML: String = ""

    // MARK: - Classification

    /// Gutter dot data for the current document. Recomputed after every text
    /// change by searching for each classification's contentText in the live
    /// document content. Updated on document switch too.
    private(set) var classificationMarkers: [ClassificationMarker] = []

    /// All ideas across every document — drives the Ideas & Questions panel.
    private(set) var allIdeas: [Classification] = []

    /// All questions across every document — drives the Ideas & Questions panel.
    private(set) var allQuestions: [Classification] = []

    /// All tasks across every document — drives the Tasks panel.
    private(set) var allTasks: [Classification] = []

    /// Persists and queries classification records.
    private let classificationStore = ClassificationStore.shared

    // MARK: - LLM classification

    /// True while a background LLM classification request is in flight.
    /// ContentView observes this to show the "Classifying…" toolbar indicator.
    private(set) var isLLMClassifying: Bool = false

    /// Debounces and runs automatic LLM classification.
    private let llmClassifier = LLMClassifier()

    /// Called by the editor when a `/t`, `/i`, or `/q` slash command is detected on Enter.
    /// Saves the classification to SQLite, then refreshes markers and panels.
    func addClassification(type: ClassificationType, content: String) {
        guard let doc = _documentSnapshot else { return }
        guard content.count <= 2_000 else { return }   // ignore unreasonably long lines
        guard !classificationStore.contentTextExists(content, for: doc.fileURL, type: type) else { return }
        let classification = Classification(
            id: UUID(),
            documentURL: doc.fileURL,
            documentName: doc.displayName,
            contentText: content,
            type: type,
            status: .active,
            source: .manual,
            createdAt: Date()
        )
        classificationStore.insert(classification)
        recomputeMarkers()
        refreshClassificationLists()
    }

    /// Updates a task's status (complete / archive) and refreshes the list.
    func updateTaskStatus(_ id: UUID, status: ClassificationStatus) {
        classificationStore.updateStatus(id, status: status)
        refreshClassificationLists()
    }

    func upsertTaskDetail(_ detail: TaskDetail) {
        classificationStore.upsertTaskDetail(detail)
    }

    func fetchTaskDetail(for taskID: UUID) -> TaskDetail? {
        classificationStore.fetchTaskDetail(for: taskID)
    }

    // MARK: - Task navigation

    /// A pending scroll request. MarkdownEditorView reads this to scroll to a
    /// specific line after navigating to a document from the Tasks panel.
    struct ScrollRequest: Equatable {
        let text: String
        let id: UUID
    }

    /// True while the user has navigated to a document from the Tasks panel.
    /// ContentView shows a Back button only when this is true.
    private(set) var navigatedFromTasks: Bool = false

    /// The document URL to return to when Back is tapped. Not observable —
    /// only read in goBack(), never in a SwiftUI body.
    @ObservationIgnored private var previousDocumentURL: URL? = nil

    /// Drives a scroll-to-line request in MarkdownEditorView.
    private(set) var scrollRequest: ScrollRequest? = nil

    /// Opens the document that contains the given task and scrolls to its line.
    /// Saves the current document URL so goBack() can return to it.
    func openDocumentFromTask(_ task: Classification) {
        let prevURL = _documentSnapshot?.fileURL
        guard let metadata = try? fileStore.loadAll().first(where: { $0.fileURL == task.documentURL })
        else { return }
        try? openDocument(metadata)         // resets nav state inside
        previousDocumentURL = prevURL       // restore after reset
        navigatedFromTasks  = true
        scrollRequest       = ScrollRequest(text: task.contentText, id: UUID())
    }

    /// Returns to the document the user was on before navigating from Tasks.
    func goBack() {
        guard let url = previousDocumentURL else {
            navigatedFromTasks = false
            scrollRequest      = nil
            return
        }
        previousDocumentURL = nil
        guard let metadata = try? fileStore.loadAll().first(where: { $0.fileURL == url })
        else {
            navigatedFromTasks = false
            return
        }
        try? openDocument(metadata)         // also resets navigatedFromTasks
    }

    // MARK: - Dependencies

    private let fileStore: FileStore
    private let autoSaveManager: AutoSaveManager
    private let previewDebouncer: PreviewDebouncer

    // MARK: - Init

    init(fileStore: FileStore = .shared) {
        self.fileStore = fileStore
        self.autoSaveManager = AutoSaveManager(fileStore: fileStore)
        self.previewDebouncer = PreviewDebouncer()
        setupLLMClassifier()
    }

    private func setupLLMClassifier() {
        llmClassifier.onClassifyingChanged = { [weak self] classifying in
            self?.isLLMClassifying = classifying
        }
        llmClassifier.onNewClassifications = { [weak self] in
            self?.recomputeMarkers()
            self?.refreshClassificationLists()
        }
    }

    // MARK: - Text changes

    /// Called by EditorCoordinator on every keystroke.
    /// Updates in-memory state, schedules a debounced save, and schedules
    /// a debounced preview render (300ms).
    func handleTextChange(_ newContent: String) {
        guard newContent != _contentSnapshot else { return }
        _contentSnapshot = newContent
        content = newContent

        guard var doc = _documentSnapshot else { return }
        doc.content = newContent
        doc.modifiedAt = Date()
        document = doc
        _documentSnapshot = doc
        autoSaveManager.schedule(document: doc)

        previewDebouncer.schedule(markdown: newContent) { [weak self] bodyHTML in
            self?.previewBodyHTML = bodyHTML
        }

        // Recompute gutter dot positions — character ranges shift as text changes.
        recomputeMarkers()

        // Schedule background LLM classification (fires 8s after typing stops).
        if let doc = _documentSnapshot {
            llmClassifier.schedule(document: doc, content: newContent)
        }
    }

    // MARK: - Document lifecycle

    /// Loads full content for a document selected from the file list.
    /// Renders an immediate (non-debounced) preview so the pane is populated
    /// the moment the document opens, not 300ms later.
    func openDocument(_ metadata: MarkdownDocument) throws {
        navigatedFromTasks  = false
        previousDocumentURL = nil
        scrollRequest       = nil
        llmClassifier.cancel()
        let doc = try fileStore.load(metadata)
        document = doc
        _documentSnapshot = doc
        activeDocumentID = doc.fileURL
        content = doc.content
        _contentSnapshot = doc.content
        renderPreviewImmediately(markdown: doc.content)
        autoSaveManager.saveNow()
        recomputeMarkers()
        refreshClassificationLists()
    }

    /// Creates a new timestamped .md file on disk and opens it in the editor.
    func createNewDocument() throws {
        navigatedFromTasks  = false
        previousDocumentURL = nil
        scrollRequest       = nil
        llmClassifier.cancel()
        autoSaveManager.saveNow()
        let doc = try fileStore.createNew()
        document = doc
        _documentSnapshot = doc
        activeDocumentID = doc.fileURL
        content = doc.content
        _contentSnapshot = doc.content
        renderPreviewImmediately(markdown: doc.content)
        recomputeMarkers()
        refreshClassificationLists()
        documentsVersion += 1
    }

    /// Flushes any pending auto-save immediately.
    func saveNow() {
        autoSaveManager.saveNow()
    }

    // MARK: - File management

    /// Increments whenever the file list changes (rename, create) so FileListView
    /// can observe a single cheap integer rather than polling the filesystem.
    private(set) var documentsVersion: Int = 0

    /// Renames a document on disk and updates in-memory state if it is the active doc.
    func renameDocument(_ document: MarkdownDocument, to newName: String) throws {
        // Flush any pending auto-save first. Without this, the debounce timer
        // could fire after the rename and write content to the old (now moved) path,
        // leaving a stale file behind.
        autoSaveManager.saveNow()
        let renamed = try fileStore.rename(document, to: newName)
        if activeDocumentID == document.fileURL {
            self.document      = renamed
            _documentSnapshot  = renamed
            activeDocumentID   = renamed.fileURL
        }
        documentsVersion += 1
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

    /// Rebuilds classificationMarkers by searching the current document content
    /// for each classification's contentText. Called after every text change so
    /// gutter dot positions stay accurate as the user edits.
    ///
    /// Content-based search is intentionally simple for Phase 6a: the first
    /// occurrence of contentText in the document is used. If the text is edited
    /// after classification the marker silently disappears until Phase 6b adds
    /// more robust linking.
    private func recomputeMarkers() {
        // Use _contentSnapshot (plain ivar, @ObservationIgnored) rather than
        // content (@Observable) — this is called from handleTextChange which
        // runs inside an AppKit notification callback. Reading an @Observable
        // getter in that context triggers ObservationRegistrar.access, which
        // resizes an internal dictionary and crashes on macOS 26.
        guard !_contentSnapshot.isEmpty, let docURL = _documentSnapshot?.fileURL else {
            classificationMarkers = []
            return
        }
        let classifications = classificationStore.fetchAll(for: docURL)
        let nsContent = _contentSnapshot as NSString
        classificationMarkers = classifications.compactMap { c in
            let range = nsContent.range(of: c.contentText)
            guard range.location != NSNotFound else { return nil }
            return ClassificationMarker(range: range, type: c.type)
        }
    }

    /// Refreshes the all-documents lists used by the Ideas and Tasks panels.
    /// Called on document switch and after a new classification is added.
    private func refreshClassificationLists() {
        allIdeas     = classificationStore.fetchAll(type: .idea)
        allQuestions = classificationStore.fetchAll(type: .question)
        allTasks     = classificationStore.fetchAll(type: .task)
    }
}
