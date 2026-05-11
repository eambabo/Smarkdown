import SwiftUI

struct ContentView: View {
    @State private var viewModel = EditorViewModel()

    var body: some View {
        HSplitView {
            MarkdownEditorView(
                text: viewModel.content,
                onTextChange: { viewModel.handleTextChange($0) }
            )
            .frame(minWidth: 300)

            MarkdownPreviewView()
                .frame(minWidth: 300)
        }
        .navigationTitle(viewModel.document?.displayName ?? "Smarkdown")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    try? viewModel.createNewDocument()
                } label: {
                    Label("New Document", systemImage: "doc.badge.plus")
                }
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
