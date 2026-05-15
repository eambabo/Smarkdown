import Foundation

/// Thin wrapper around the Brave Search API.
///
/// Brave Search has a free tier (2,000 queries/month) and returns clean,
/// structured results — well-suited for a personal app.
/// API key is set in Preferences → Web Search.
///
/// Endpoint: GET https://api.search.brave.com/res/v1/web/search
/// Auth:     X-Subscription-Token header
/// Docs:     https://api.search.brave.com/app/documentation/web-search
@MainActor
final class BraveSearchClient {

    static let shared = BraveSearchClient()
    private init() {}

    // MARK: - Private response types

    private struct SearchResponse: Decodable {
        let web: WebContainer?
        struct WebContainer: Decodable {
            let results: [Result]
        }
        struct Result: Decodable {
            let title: String
            let url: String
            let description: String?
        }
    }

    // MARK: - API

    /// Returns true if an API key is configured in Preferences.
    var isConfigured: Bool {
        !(UserDefaults.standard.string(forKey: LLMProvider.Keys.braveAPIKey) ?? "")
            .trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Searches the web and returns up to `count` results.
    /// Throws `LLMError.notConfigured` if no Brave API key is set.
    func search(query: String, count: Int = 3) async throws -> [WebResult] {
        let apiKey = (UserDefaults.standard.string(forKey: LLMProvider.Keys.braveAPIKey) ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !apiKey.isEmpty else { throw LLMError.notConfigured }

        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        components.queryItems = [
            URLQueryItem(name: "q",     value: query),
            URLQueryItem(name: "count", value: "\(max(1, min(count, 20)))")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue(apiKey,              forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json",  forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (decoded.web?.results ?? []).map {
            WebResult(
                title:   $0.title,
                url:     $0.url,
                snippet: $0.description ?? ""
            )
        }
    }
}
