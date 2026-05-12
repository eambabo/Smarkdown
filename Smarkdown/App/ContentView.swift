import SwiftUI

struct ContentView: View {
    @State private var viewModel = EditorViewModel()

    var body: some View {
        HSplitView {
            MarkdownEditorView(
                text: viewModel.content,
                onTextChange: { viewModel.handleTextChange($0) }
            )
            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)

            MarkdownPreviewView(
                pageHTML: viewModel.previewPageHTML,
                bodyHTML: viewModel.previewBodyHTML
            )
            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(viewModel.document?.displayName ?? "Smarkdown")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    try? viewModel.createNewDocument()
                } label: {
                    Label("New Document", systemImage: "doc.badge.plus")
                }
                // Explicit shortcut so this button is never triggered by
                // bare Return/Enter, which .primaryAction placement can cause
                // on macOS when the responder chain resolves ambiguously.
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onAppear {
            // Open the most recent document on launch, or create a new one
            // if the Markdown Files directory is empty.
            if viewModel.document == nil {
                if let mostRecent = try? FileStore.shared.loadAll().first {
                    try? viewModel.openDocument(mostRecent)
                } else {
                    try? viewModel.createNewDocument()
                }
            }
        }
    }
}
