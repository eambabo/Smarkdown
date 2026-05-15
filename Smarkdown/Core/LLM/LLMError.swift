import Foundation

enum LLMError: Error {
    /// The provider has no credentials or endpoint configured.
    case notConfigured
}
