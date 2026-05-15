import Foundation

/// LLM client for any OpenAI-compatible local server — Ollama, LM Studio, etc.
///
/// Conforms to both LLMClassifying (structured JSON output) and LLMGenerating
/// (free-form text) using the same endpoint and auth setup.
///
/// The OpenAI chat completions format:
///   - Endpoint:  <baseURL>/v1/chat/completions
///   - Auth:      no API key required for local servers (sends "local" as Bearer)
///   - System:    sent as a message with role "system"
///   - Response:  choices[0].message.content
@MainActor
final class OpenAICompatibleClient: LLMClassifying, LLMGenerating {

    static let shared = OpenAICompatibleClient()
    private init() {}

    // MARK: - Private types

    private struct Response: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let message: Message
        }
        struct Message: Decodable {
            let content: String
        }
    }

    // MARK: - Shared helpers

    private func resolvedEndpointAndModel() throws -> (URL, String) {
        let rawBase = (UserDefaults.standard.string(forKey: LLMProvider.Keys.localBaseURL)
            ?? LLMProvider.Defaults.localBaseURL)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let model = (UserDefaults.standard.string(forKey: LLMProvider.Keys.localModel)
            ?? LLMProvider.Defaults.localModel)
            .trimmingCharacters(in: .whitespaces)

        guard !rawBase.isEmpty, !model.isEmpty else { throw LLMError.notConfigured }
        guard let endpoint = URL(string: "\(rawBase)/v1/chat/completions") else {
            throw LLMError.notConfigured
        }
        return (endpoint, model)
    }

    private func makeRequest(endpoint: URL, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        // Local servers typically don't require auth; sending a placeholder keeps
        // some servers (like LM Studio) happy without breaking others.
        request.setValue("Bearer local",     forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 60   // local models can be slower than cloud
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func firstChoiceContent(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    // MARK: - LLMClassifying

    func classify(text: String, prompt: ClassificationPrompt) async throws -> [LLMClassificationItem] {
        let (endpoint, model) = try resolvedEndpointAndModel()

        // System prompt first, then few-shot pairs (user-context), then document.
        var messages: [[String: Any]] = [["role": "system", "content": prompt.systemPrompt]]
        messages += prompt.fewShotMessages.map { ["role": $0.role, "content": $0.content] }
        messages.append(["role": "user", "content": text])

        let body: [String: Any] = [
            "model":    model,
            "stream":   false,
            "messages": messages
        ]
        let request = try makeRequest(endpoint: endpoint, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return extractLLMItems(from: try firstChoiceContent(from: data))
    }

    // MARK: - LLMGenerating

    func generate(systemPrompt: String, userMessage: String) async throws -> String {
        let (endpoint, model) = try resolvedEndpointAndModel()

        let body: [String: Any] = [
            "model":  model,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userMessage]
            ]
        ]
        let request = try makeRequest(endpoint: endpoint, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try firstChoiceContent(from: data)
    }
}
