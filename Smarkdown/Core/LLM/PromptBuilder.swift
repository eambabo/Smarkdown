import Foundation

/// Builds the LLM classification prompt, personalised with few-shot examples
/// drawn from the user's own classification history.
///
/// Phase 8 Part 4 change: examples are no longer embedded in the system prompt.
/// Instead they return as `fewShotMessages` — a user/assistant pair that sits
/// between the system prompt and the document in the messages array. This keeps
/// user-authored content out of the high-authority system context.
///
/// The loop works in three phases:
///
/// 1. **Cold start** (< 3 positive examples of any type): returns the static
///    base prompt with empty fewShotMessages.
///
/// 2. **Warm** (≥ 3 positive examples): injects up to 5 positive examples per
///    type as a user/assistant message pair.
///
/// 3. **Refined** (negative examples present): also includes items the user
///    quickly dismissed (archived within 60s of LLM creation).
@MainActor
struct PromptBuilder {

    private let store = ClassificationStore.shared
    private static let minimumExamples = 3
    private static let exampleLimit    = 5

    func build() -> ClassificationPrompt {
        let taskPos     = store.positiveExamples(type: .task,     limit: Self.exampleLimit)
        let ideaPos     = store.positiveExamples(type: .idea,     limit: Self.exampleLimit)
        let questionPos = store.positiveExamples(type: .question, limit: Self.exampleLimit)
        let taskNeg     = store.negativeExamples(type: .task,     limit: Self.exampleLimit)
        let ideaNeg     = store.negativeExamples(type: .idea,     limit: Self.exampleLimit)
        let questionNeg = store.negativeExamples(type: .question, limit: Self.exampleLimit)

        let hasEnoughExamples = taskPos.count     >= Self.minimumExamples
                             || ideaPos.count     >= Self.minimumExamples
                             || questionPos.count >= Self.minimumExamples

        // Cold start — base prompt only, no few-shot messages.
        guard hasEnoughExamples else {
            return ClassificationPrompt(systemPrompt: llmBaseSystemPrompt, fewShotMessages: [])
        }

        // Warm / refined — build a user message containing all examples.
        // User-authored content lives in user-context, not system-context.
        var examplesContent = ""

        if !taskPos.isEmpty {
            examplesContent += "Examples of items I classify as tasks:\n"
            examplesContent += taskPos.map { "- \($0)" }.joined(separator: "\n")
            examplesContent += "\n\n"
        }
        if !ideaPos.isEmpty {
            examplesContent += "Examples of items I classify as ideas:\n"
            examplesContent += ideaPos.map { "- \($0)" }.joined(separator: "\n")
            examplesContent += "\n\n"
        }
        if !questionPos.isEmpty {
            examplesContent += "Examples of items I classify as questions:\n"
            examplesContent += questionPos.map { "- \($0)" }.joined(separator: "\n")
            examplesContent += "\n\n"
        }
        if !taskNeg.isEmpty {
            examplesContent += "Items I do NOT consider tasks:\n"
            examplesContent += taskNeg.map { "- \($0)" }.joined(separator: "\n")
            examplesContent += "\n\n"
        }
        if !ideaNeg.isEmpty {
            examplesContent += "Items I do NOT consider ideas:\n"
            examplesContent += ideaNeg.map { "- \($0)" }.joined(separator: "\n")
            examplesContent += "\n\n"
        }
        if !questionNeg.isEmpty {
            examplesContent += "Items I do NOT consider questions:\n"
            examplesContent += questionNeg.map { "- \($0)" }.joined(separator: "\n")
            examplesContent += "\n\n"
        }

        let fewShotMessages: [LLMMessage] = [
            LLMMessage(
                role: "user",
                content: examplesContent.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            LLMMessage(
                role: "assistant",
                content: "Understood. I'll apply your classification style when identifying tasks, ideas, and questions."
            )
        ]

        return ClassificationPrompt(
            systemPrompt: llmBaseSystemPrompt,
            fewShotMessages: fewShotMessages
        )
    }
}
