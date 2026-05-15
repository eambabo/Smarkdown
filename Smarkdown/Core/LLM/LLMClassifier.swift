import Foundation

/// Debounces LLM classification and orchestrates the classify → deduplicate → persist pipeline.
///
/// The active backend (Anthropic or local) is resolved from LLMProvider.current at
/// the moment each run starts — so changing the provider in Preferences takes effect
/// on the next debounce window without restarting the app.
///
/// All work runs on the main actor. URLSession awaits suspend the actor without
/// blocking the main thread.
@MainActor
final class LLMClassifier {

    // MARK: - Callbacks (set by EditorViewModel)

    /// Called with `true` when a request starts, `false` when it ends.
    var onClassifyingChanged: ((Bool) -> Void)?

    /// Called after at least one new classification is stored.
    var onNewClassifications: (() -> Void)?

    // MARK: - Private

    private var debounceTask: Task<Void, Never>?
    private let store = ClassificationStore.shared

    private static let debounceInterval:      Duration = .seconds(8)
    private static let minimumContentLength:  Int      = 50

    // MARK: - API

    func schedule(document: MarkdownDocument, content: String) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled, let self else { return }
            await self.run(document: document, content: content)
        }
    }

    func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: - Private

    private func run(document: MarkdownDocument, content: String) async {
        guard content.count >= Self.minimumContentLength else { return }

        // Resolve the active client right now — not at init — so provider changes
        // in Preferences are picked up without needing to restart the app.
        let client = LLMProvider.activeClient

        onClassifyingChanged?(true)

        do {
            let prompt = PromptBuilder().build()
            let items = try await client.classify(text: content, prompt: prompt)
            var newCount = 0

            for item in items {
                guard
                    let type = ClassificationType(rawValue: item.type),
                    !item.text.isEmpty,
                    item.text.count <= 2_000,
                    !store.contentTextExists(item.text, for: document.fileURL, type: type)
                else { continue }

                store.insert(Classification(
                    id: UUID(),
                    documentURL:  document.fileURL,
                    documentName: document.displayName,
                    contentText:  item.text,
                    type:         type,
                    status:       .active,
                    source:       .llm,
                    createdAt:    Date()
                ))
                newCount += 1
            }

            if newCount > 0 { onNewClassifications?() }
        } catch {
            // Silent failure: LLMError.notConfigured, network errors, bad responses.
            // Manual slash command classification is independent and always works.
        }

        onClassifyingChanged?(false)
    }
}
