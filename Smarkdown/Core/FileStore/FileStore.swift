import Foundation

/// Single source of truth for all file I/O.
///
/// Runs on the main actor for V1 simplicity — file operations on typical
/// Markdown documents (< 1MB) complete fast enough to not block the UI.
/// In V2, heavy operations can be moved to a background actor.
///
/// iOS portability: inject a custom `baseDirectory` at init. On macOS the
/// default is ~/Documents/Markdown Files/. On iOS, pass the app's sandbox
/// Documents directory instead.
@MainActor
final class FileStore {
    static let shared = FileStore()

    let baseDirectory: URL

    init(baseDirectory: URL? = nil) {
        if let base = baseDirectory {
            self.baseDirectory = base
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.baseDirectory = docs.appending(path: "Markdown Files", directoryHint: .isDirectory)
        }
        createDirectoryIfNeeded()
    }

    // MARK: - Directory setup

    private func createDirectoryIfNeeded() {
        // withIntermediateDirectories: true succeeds silently if the directory
        // already exists, so no pre-flight fileExists check is needed.
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Loading

    /// Returns all .md files sorted reverse-chronologically by modification date.
    /// Content is NOT loaded — use `load(_:)` to get the full content when opening a document.
    /// This keeps the file-list scan fast even with hundreds of files.
    func loadAll() throws -> [MarkdownDocument] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles
        ).filter { $0.pathExtension == "md" }

        let docs: [MarkdownDocument] = try urls.map { url in
            let values = try url.resourceValues(forKeys: keys)
            return MarkdownDocument(
                filename: url.lastPathComponent,
                content: "",
                fileURL: url,
                createdAt: values.creationDate ?? Date(),
                modifiedAt: values.contentModificationDate ?? Date()
            )
        }

        return docs.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Reads the full content of a document from disk.
    /// Call this when the user opens a document from the file list.
    func load(_ document: MarkdownDocument) throws -> MarkdownDocument {
        let content = try String(contentsOf: document.fileURL, encoding: .utf8)
        var loaded = document
        loaded.content = content
        return loaded
    }

    // MARK: - Saving

    /// Writes content to disk atomically. The `atomically: true` flag writes to a
    /// temporary file first, then renames it — preventing partial writes on crash.
    func save(_ document: MarkdownDocument) throws {
        try document.content.write(to: document.fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Creating

    // DateFormatter is expensive to initialize — allocate once and reuse.
    private static let filenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()

    /// Creates a new empty .md file with a timestamp-based filename and returns it.
    /// Filename format: YYYY-MM-DD-HHmmss.md
    func createNew() throws -> MarkdownDocument {
        let filename = "\(FileStore.filenameFormatter.string(from: Date())).md"
        let url = baseDirectory.appending(path: filename, directoryHint: .notDirectory)
        let now = Date()

        let document = MarkdownDocument(
            filename: filename,
            content: "",
            fileURL: url,
            createdAt: now,
            modifiedAt: now
        )
        try save(document)
        return document
    }
}
