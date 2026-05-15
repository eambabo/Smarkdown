import SwiftUI

struct IdeasView: View {
    let editorViewModel: EditorViewModel

    @State private var briefTarget: Classification? = nil

    var body: some View {
        let ideas     = editorViewModel.allIdeas
        let questions = editorViewModel.allQuestions

        Group {
            if ideas.isEmpty && questions.isEmpty {
                ContentUnavailableView(
                    "No Ideas or Questions",
                    systemImage: "lightbulb",
                    description: Text("Use **/i** for an idea or **/q** for a question, then press Return.")
                )
            } else {
                List {
                    if !ideas.isEmpty {
                        Section("Ideas") {
                            ForEach(ideas) { idea in
                                itemRow(idea, dotColor: .green)
                            }
                        }
                    }
                    if !questions.isEmpty {
                        Section("Questions") {
                            ForEach(questions) { question in
                                itemRow(question, dotColor: .purple)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $briefTarget) { classification in
            BriefView(classification: classification)
        }
    }

    private func itemRow(_ item: Classification, dotColor: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.contentText)
                    .font(.body)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                    Text(item.documentName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Button {
                briefTarget = item
            } label: {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(item.type == .question ? "Get Question Brief" : "Get Idea Brief")
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
