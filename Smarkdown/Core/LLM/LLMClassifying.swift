import Foundation

// MARK: - Message type

/// A single chat message exchanged with an LLM.
/// Used to pass few-shot examples as user/assistant turns rather than
/// embedding them in the system prompt, which reduces prompt injection risk.
struct LLMMessage {
    let role: String    // "user" or "assistant"
    let content: String
}

// MARK: - Classification prompt

/// The complete input for a classification request.
///
/// Separating the system prompt from few-shot messages is the key security
/// improvement in Phase 8 Part 4: user-authored example text stays in the
/// user-message context rather than the high-authority system-prompt context.
///
/// Cold start: fewShotMessages is empty — the system prompt stands alone.
/// Warm/refined: fewShotMessages carries personalised examples as a
/// user/assistant pair, appended before the document-to-classify user message.
struct ClassificationPrompt {
    let systemPrompt: String
    let fewShotMessages: [LLMMessage]
}

// MARK: - Protocol

/// Any LLM backend that can classify document text into tasks, ideas, and questions.
@MainActor
protocol LLMClassifying: AnyObject {
    func classify(
        text: String,
        prompt: ClassificationPrompt
    ) async throws -> [LLMClassificationItem]
}

// MARK: - Shared result type

/// A single task, idea, or question extracted from a document.
/// Shared between all LLM backends — stored the same way regardless of source.
struct LLMClassificationItem: Decodable {
    let type: String   // "task", "idea", or "question"
    let text: String
}

// MARK: - Base system prompt

/// The static baseline prompt used by PromptBuilder when there is not yet
/// enough user history to generate personalised few-shot examples.
let llmBaseSystemPrompt = """
    You are an expert at identifying actionable tasks, ideas, and questions in personal notes.

    Given a markdown document, extract:
    - Tasks: specific action items, to-dos, or things the author needs or intends to do
    - Ideas: insights, creative thoughts, concepts worth exploring, observations
    - Questions: genuine questions the author has — things they want to find out or understand

    Rules:
    - Only extract items clearly present in the text — do not infer or add your own
    - Each "text" value must be a verbatim or very close excerpt (under 200 characters)
    - If nothing qualifies, return an empty array
    - Return ONLY a valid JSON array, no preamble or explanation

    Format: [{"type":"task","text":"..."},{"type":"idea","text":"..."},{"type":"question","text":"..."}]
    """

// MARK: - Shared JSON extractor

/// Extracts the JSON array from an LLM response string.
/// Searching for `[...]` bounds tolerates any accidental preamble text.
func extractLLMItems(from text: String) -> [LLMClassificationItem] {
    guard let start = text.firstIndex(of: "["),
          let end   = text.lastIndex(of: "]"),
          start     <= end
    else { return [] }

    let substring = String(text[start...end])
    guard let data  = substring.data(using: .utf8),
          let items = try? JSONDecoder().decode([LLMClassificationItem].self, from: data)
    else { return [] }

    return items
}
