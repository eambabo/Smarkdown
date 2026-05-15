import Foundation

/// Thin wrapper around the Anthropic Messages API.
///
/// Conforms to both LLMClassifying (structured JSON output) and LLMGenerating
/// (free-form text) using the same endpoint and auth setup.
///
/// Model choice: claude-haiku-4-5 — fast and cheap for background tasks
/// that may run frequently.
@MainActor
final class AnthropicAPIClient: LLMClassifying, LLMGenerating {

    static let shared = AnthropicAPIClient()
    private init() {}

    // MARK: - Private types

    private struct Response: Decodable {
        let content: [ContentBlock]
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
    }

    // MARK: - Constants

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - Shared request builder

    private func makeRequest(apiKey: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func resolvedAPIKey() throws -> String {
        let key = (UserDefaults.standard.string(forKey: LLMProvider.Keys.anthropicKey) ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw LLMError.notConfigured }
        return key
    }

    private func firstTextContent(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.content.first(where: { $0.type == "text" })?.text ?? ""
    }

    // MARK: - LLMClassifying

    func classify(text: String, prompt: ClassificationPrompt) async throws -> [LLMClassificationItem] {
        let apiKey = try resolvedAPIKey()

        // Build messages: few-shot pairs (user-context, not system-context) then
        // the document to classify as the final user message.
        var messages: [[String: Any]] = prompt.fewShotMessages.map {
            ["role": $0.role, "content": $0.content]
        }
        messages.append(["role": "user", "content": text])

        let body: [String: Any] = [
            "model":      "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "system":     prompt.systemPrompt,
            "messages":   messages
        ]
        let request = try makeRequest(apiKey: apiKey, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return extractLLMItems(from: try firstTextContent(from: data))
    }

    // MARK: - LLMGenerating

    func generate(systemPrompt: String, userMessage: String) async throws -> String {
        let apiKey = try resolvedAPIKey()

        let body: [String: Any] = [
            "model":      "claude-haiku-4-5-20251001",
            "max_tokens": 512,
            "system":     systemPrompt,
            "messages":   [["role": "user", "content": userMessage]]
        ]
        let request = try makeRequest(apiKey: apiKey, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try firstTextContent(from: data)
    }
}
