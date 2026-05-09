import Foundation

// Phase 2: full FileStore implementation will flesh this out.
struct MarkdownDocument: Identifiable, Equatable, Sendable {
    let id: UUID
    var filename: String
    var content: String
    var fileURL: URL
    var createdAt: Date
    var modifiedAt: Date
}
