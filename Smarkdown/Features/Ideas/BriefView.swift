import SwiftUI

/// Sheet that displays a generated brief for an idea or question.
///
/// Shown when the user clicks the brief button on an idea or question row.
/// Async-loads by calling BriefService on appear, shows a spinner during load.
struct BriefView: View {
    let classification: Classification

    @State private var result: BriefResult? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    @Environment(\.dismiss) private var dismiss

    private var title: String {
        classification.type == .question ? "Question Brief" : "Idea Brief"
    }

    private var typeIcon: String {
        classification.type == .question ? "questionmark.circle.fill" : "lightbulb.fill"
    }

    private var typeColor: Color {
        classification.type == .question ? .purple : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: typeIcon)
                        .foregroundStyle(typeColor)
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.escape)
                }
                Text(classification.contentText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding()

            Divider()

            // ── Body ──────────────────────────────────────────────
            ScrollView {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Generating brief…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)

                } else if let msg = errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)

                } else if let result {
                    briefContent(result)
                }
            }
        }
        .frame(width: 520)
        .frame(minHeight: 400)
        .task { await loadBrief() }
    }

    // MARK: - Content sections

    @ViewBuilder
    private func briefContent(_ result: BriefResult) -> some View {
        VStack(alignment: .leading, spacing: 20) {

            // Synthesis
            briefSection(
                icon: "sparkles",
                title: classification.type == .question ? "Answer" : "Synthesis",
                color: typeColor
            ) {
                Text(result.synthesis)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Document matches
            if !result.documentMatches.isEmpty {
                briefSection(icon: "doc.text", title: "From Your Notes", color: .secondary) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(result.documentMatches, id: \.documentName) { match in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(match.documentName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(match.excerpt)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .lineLimit(4)
                            }
                        }
                    }
                }
            }

            // Web results
            if !result.webResults.isEmpty {
                briefSection(icon: "globe", title: "From the Web", color: .secondary) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(result.webResults, id: \.url) { web in
                            VStack(alignment: .leading, spacing: 3) {
                                if let url = URL(string: web.url) {
                                    Link(web.title, destination: url)
                                        .font(.callout.weight(.semibold))
                                } else {
                                    Text(web.title)
                                        .font(.callout.weight(.semibold))
                                }
                                if !web.snippet.isEmpty {
                                    Text(web.snippet)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                Text(web.url)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private func briefSection<Content: View>(
        icon: String,
        title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Loading

    private func loadBrief() async {
        do {
            result = try await BriefService.shared.generateBrief(for: classification)
        } catch {
            errorMessage = "Could not generate brief: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
