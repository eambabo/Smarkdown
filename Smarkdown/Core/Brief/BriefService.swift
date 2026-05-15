import Foundation

/// Generates idea and question briefs by combining document context,
/// optional web search results, and LLM synthesis.
///
/// Pipeline:
///   1. Search the user's documents for relevant excerpts (FileStore.search)
///   2. Search the web via Brave Search (skipped if API key not configured)
///   3. Build a synthesis prompt and call the active LLM (LLMGenerating)
@MainActor
final class BriefService {

    static let shared = BriefService()
    private init() {}

    // MARK: - System prompts

    private let ideaSystemPrompt = """
        You are a research assistant helping a user develop an idea.
        Given an idea and relevant context from their notes and the web, write a concise brief (3-5 sentences) that:
        - Connects the idea to what they already know
        - Surfaces one related concept worth exploring
        - Suggests one concrete next step
        Be direct and practical. Write in second person.
        """

    private let questionSystemPrompt = """
        You are a research assistant helping a user find an answer.
        Given a question and relevant context from their notes and the web, provide a direct answer (3-5 sentences).
        Lead with the answer if the context supports it. Note important caveats. If the context is insufficient, say so and suggest where to look.
        """

    // MARK: - API

    /// Generates a brief for the given classification.
    /// - Searches user documents for relevant excerpts
    /// - Searches the web if a Brave API key is configured
    /// - Synthesizes both into a brief using the active LLM
    func generateBrief(for classification: Classification) async throws -> BriefResult {
        async let docTask  = fetchDocumentMatches(query: classification.contentText)
        async let webTask  = fetchWebResults(query: classification.contentText)

        let docMatches = await docTask
        let webResults = (try? await webTask) ?? []   // web search failure is non-fatal

        let synthesis = try await synthesize(
            classification: classification,
            docMatches: docMatches,
            webResults: webResults
        )

        return BriefResult(
            synthesis:       synthesis,
            documentMatches: docMatches,
            webResults:      webResults
        )
    }

    // MARK: - Private

    private func fetchDocumentMatches(query: String) async -> [DocumentMatch] {
        let results = (try? FileStore.shared.search(query: query)) ?? []
        return results
            .filter { !$0.snippet.isEmpty }   // skip filename-only matches (no useful excerpt)
            .prefix(3)
            .map { DocumentMatch(documentName: $0.document.displayName, excerpt: $0.snippet) }
    }

    private func fetchWebResults(query: String) async throws -> [WebResult] {
        guard BraveSearchClient.shared.isConfigured else { return [] }
        return try await BraveSearchClient.shared.search(query: query, count: 3)
    }

    private func synthesize(
        classification: Classification,
        docMatches: [DocumentMatch],
        webResults: [WebResult]
    ) async throws -> String {
        let client = LLMProvider.activeGeneratingClient
        let systemPrompt = classification.type == .question ? questionSystemPrompt : ideaSystemPrompt
        let userMessage  = buildUserMessage(classification: classification,
                                            docMatches: docMatches,
                                            webResults: webResults)
        return try await client.generate(systemPrompt: systemPrompt, userMessage: userMessage)
    }

    private func buildUserMessage(
        classification: Classification,
        docMatches: [DocumentMatch],
        webResults: [WebResult]
    ) -> String {
        let typeLabel = classification.type == .question ? "Question" : "Idea"
        var message = "\(typeLabel): \(classification.contentText)\n"

        if !docMatches.isEmpty {
            message += "\nContext from my notes:\n"
            for match in docMatches {
                message += "\(match.documentName): \(match.excerpt)\n"
            }
        }

        if !webResults.isEmpty {
            message += "\nContext from the web:\n"
            for result in webResults {
                message += "\(result.title) — \(result.snippet)\n"
            }
        }

        if classification.type == .question {
            message += "\nPlease answer this question directly in 3-5 sentences using the context above."
        } else {
            message += "\nPlease synthesize this into a 3-5 sentence brief that helps me develop this idea further."
        }

        return message
    }
}
