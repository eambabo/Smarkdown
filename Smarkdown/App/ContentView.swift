import SwiftUI

struct ContentView: View {
    @State private var viewModel = EditorViewModel()

    var body: some View {
        NavigationSplitView {
            FileListView(editorViewModel: viewModel)
                .navigationTitle("Documents")
        } detail: {
            HSplitView {
                MarkdownEditorView(
                    text: viewModel.content,
                    onTextChange: { viewModel.handleTextChange($0) },
                    classificationMarkers: viewModel.classificationMarkers,
                    onClassification: { viewModel.addClassification(type: $0, content: $1) },
                    scrollRequest: viewModel.scrollRequest
                )
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)

                rightPanelContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(viewModel.document?.displayName ?? "Smarkdown")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.document?.displayName ?? "Smarkdown")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            if viewModel.isLLMClassifying {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Classifying…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if viewModel.navigatedFromTasks {
                ToolbarItem(placement: .automatic) {
                    Button {
                        viewModel.goBack()
                    } label: {
                        Label("Back to Tasks", systemImage: "arrow.backward")
                    }
                    .help("Return to previous document")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    try? viewModel.createNewDocument()
                } label: {
                    Label("New Document", systemImage: "doc.badge.plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            ToolbarItemGroup(placement: .automatic) {
                panelButton(.preview, systemImage: "eye", label: "Preview")
                panelButton(.ideas,   systemImage: "lightbulb", label: "Ideas/Questions")
                panelButton(.tasks,   systemImage: "checklist", label: "Tasks")
            }
        }
        .onAppear {
            if viewModel.document == nil {
                if let mostRecent = try? FileStore.shared.loadAll().first {
                    try? viewModel.openDocument(mostRecent)
                } else {
                    try? viewModel.createNewDocument()
                }
            }
        }
    }

    // MARK: - Right panel

    @ViewBuilder
    private var rightPanelContent: some View {
        if let panel = viewModel.rightPanel {
            switch panel {
            case .preview:
                MarkdownPreviewView(
                    pageHTML: viewModel.previewPageHTML,
                    bodyHTML: viewModel.previewBodyHTML
                )
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            case .ideas:
                IdeasView(editorViewModel: viewModel)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            case .tasks:
                TasksView(editorViewModel: viewModel)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func panelButton(_ panel: EditorViewModel.RightPanel, systemImage: String, label: String) -> some View {
        Button {
            viewModel.togglePanel(panel)
        } label: {
            Label(label, systemImage: systemImage)
        }
        .help(label)
        .foregroundStyle(viewModel.rightPanel == panel ? Color.accentColor : Color.primary)
    }
}
