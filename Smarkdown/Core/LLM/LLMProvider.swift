import Foundation

/// Which LLM backend is active.
enum LLMProvider: String {
    case anthropic = "anthropic"
    case local     = "local"

    /// Reads the stored preference, defaulting to Anthropic.
    static var current: LLMProvider {
        LLMProvider(rawValue: UserDefaults.standard.string(forKey: Keys.provider) ?? "") ?? .anthropic
    }

    /// Resolves the concrete classification client for the current provider.
    @MainActor
    static var activeClient: any LLMClassifying {
        switch current {
        case .anthropic: return AnthropicAPIClient.shared
        case .local:     return OpenAICompatibleClient.shared
        }
    }

    /// Resolves the concrete generation client for the current provider.
    /// Used by BriefService for idea and question briefs.
    @MainActor
    static var activeGeneratingClient: any LLMGenerating {
        switch current {
        case .anthropic: return AnthropicAPIClient.shared
        case .local:     return OpenAICompatibleClient.shared
        }
    }
}

// MARK: - UserDefaults keys

extension LLMProvider {
    enum Keys {
        static let provider       = "llmProvider"
        static let anthropicKey   = "anthropicAPIKey"
        static let localBaseURL   = "localLLMBaseURL"
        static let localModel     = "localLLMModel"
        static let braveAPIKey    = "braveAPIKey"
    }

    enum Defaults {
        static let localBaseURL = "http://localhost:11434"
        static let localModel   = "llama3.1:8b"
    }
}
