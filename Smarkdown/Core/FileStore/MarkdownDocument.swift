import Foundation

struct MarkdownDocument: Identifiable, Equatable, Sendable {
    // fileURL is the stable identity — the same file always produces the same ID
    // across multiple loadAll() calls, which UUID would not guarantee.
    var id: URL { fileURL }

    var filename: String
    var content: String
    var fileURL: URL
    var createdAt: Date
    var modifiedAt: Date

    /// Display name shown in the file list — filename without the .md extension.
    var displayName: String {
        (filename as NSString).deletingPathExtension
    }
}
