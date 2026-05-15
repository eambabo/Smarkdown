import Foundation

/// Any LLM backend that can generate free-form text from a prompt.
///
/// Used by BriefService for idea and question briefs — a different task from
/// structured JSON classification, so a separate protocol keeps the contracts
/// clean. Both AnthropicAPIClient and OpenAICompatibleClient conform.
@MainActor
protocol LLMGenerating: AnyObject {
    /// Generate a free-form text response.
    /// - Parameters:
    ///   - systemPrompt: Trusted instructions from the host app.
    ///   - userMessage:  The content to respond to.
    /// - Returns: The model's response as a plain string.
    func generate(systemPrompt: String, userMessage: String) async throws -> String
}
