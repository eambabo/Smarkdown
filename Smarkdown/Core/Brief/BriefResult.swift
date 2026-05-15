import Foundation

/// An excerpt from one of the user's documents that matched the brief query.
struct DocumentMatch {
    let documentName: String
    let excerpt: String
}

/// A single web search result from Brave Search.
struct WebResult {
    let title: String
    let url: String
    let snippet: String
}

/// The fully generated brief for an idea or question.
struct BriefResult {
    /// LLM-synthesized summary (3-5 sentences).
    let synthesis: String
    /// Relevant excerpts from the user's own documents.
    let documentMatches: [DocumentMatch]
    /// Top web search results (empty if Brave API key is not configured).
    let webResults: [WebResult]
}
