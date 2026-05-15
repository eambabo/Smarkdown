import SwiftUI

/// Sidebar document list.
///
/// Owns its own `documents` array and `selectedID` state so that typing in the
/// editor (which updates EditorViewModel.document on every keystroke) does NOT
/// trigger a list re-render. The only EditorViewModel properties observed here are
/// `activeDocumentID` (changes on document switch) and `documentsVersion` (increments
/// on file-system mutations like create and rename).
struct FileListView: View {
    let editorViewModel: EditorViewModel

    @State private var documents: [MarkdownDocument] = []
    @State private var selectedID: URL? = nil

    // MARK: - Search state

    @State private var searchQuery: String = ""
    @State private var searchResults: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>? = nil

    private var isSearching: Bool { !searchQuery.isEmpty }

    // MARK: - Rename state

    @State private var renamingID: URL? = nil
    @State private var renameText: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        Group {
            if isSearching {
                searchList
            } else if documents.isEmpty {
                ContentUnavailableView(
                    "No Documents",
                    systemImage: "doc.text",
                    description: Text("Press ⌘N to create your first document.")
                )
            } else {
                List(documents, selection: $selectedID) { doc in
                    rowView(for: doc)
                        .tag(doc.id)
                }
                .listStyle(.sidebar)
            }
        }
        .searchable(text: $searchQuery, placement: .sidebar, prompt: "Search")
        .toolbar {
            ToolbarItem {
                Button {
                    try? editorViewModel.createNewDocument()
                } label: {
                    Label("New Document", systemImage: "square.and.pencil")
                }
                .help("New Document")
            }
        }
        .onAppear { reload() }
        .onChange(of: searchQuery) { _, query in scheduleSearch(query: query) }
        .onChange(of: selectedID) { _, newID in
            guard let newID,
                  newID != editorViewModel.activeDocumentID else { return }
            cancelRename()
            // Look in both the normal list and search results.
            let doc = documents.first(where: { $0.id == newID })
                   ?? searchResults.first(where: { $0.document.id == newID })?.document
            guard let doc else { return }
            try? editorViewModel.openDocument(doc)
        }
        .onChange(of: editorViewModel.activeDocumentID) { _, _ in reload() }
        .onChange(of: editorViewModel.documentsVersion)  { _, _ in reload() }
        // Commit rename when the text field loses focus (click elsewhere).
        .onChange(of: renameFocused) { _, focused in
            if !focused, let id = renamingID,
               let doc = documents.first(where: { $0.id == id }) {
                commitRename(for: doc)
            }
        }
    }

    // MARK: - Search list

    @ViewBuilder
    private var searchList: some View {
        if searchResults.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
        } else {
            List(searchResults, selection: $selectedID) { result in
                searchResultRow(result)
                    .tag(result.document.id)
            }
            .listStyle(.sidebar)
        }
    }

    private func searchResultRow(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.document.displayName)
                .font(.body)
                .lineLimit(1)
            if !result.snippet.isEmpty {
                Text(result.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            searchResults = (try? FileStore.shared.search(query: query)) ?? []
        }
    }

    // MARK: - Row view

    @ViewBuilder
    private func rowView(for doc: MarkdownDocument) -> some View {
        if renamingID == doc.id {
            TextField("Document name", text: $renameText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($renameFocused)
                .onSubmit { commitRename(for: doc) }
                .onExitCommand { cancelRename() }   // Escape cancels
                .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.displayName)
                    .font(.body)
                    .lineLimit(1)
                Text(doc.modifiedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button("Rename") { startRename(for: doc) }
            }
            // Double-click to rename. List handles single-click selection independently.
            .onTapGesture(count: 2) { startRename(for: doc) }
        }
    }

    // MARK: - Rename helpers

    private func startRename(for doc: MarkdownDocument) {
        renamingID  = doc.id
        renameText  = doc.displayName
        // Give SwiftUI one cycle to insert the TextField before focusing it.
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename(for doc: MarkdownDocument) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        // Only act if there's a non-empty name that actually differs.
        if !trimmed.isEmpty, trimmed != doc.displayName {
            try? editorViewModel.renameDocument(doc, to: trimmed)
        }
        cancelRename()
    }

    private func cancelRename() {
        renamingID    = nil
        renameText    = ""
        renameFocused = false
    }

    // MARK: - Data

    private func reload() {
        documents  = (try? FileStore.shared.loadAll()) ?? []
        selectedID = editorViewModel.activeDocumentID
    }
}
