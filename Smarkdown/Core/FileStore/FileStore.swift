import Foundation

/// A document that matched a search query, paired with the first matching line.
struct SearchResult: Identifiable {
    var id: URL { document.id }
    let document: MarkdownDocument
    /// The first line of the document that contains the query string.
    /// Empty when the match was on the filename only.
    let snippet: String
}

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
    /// Throws if the file exceeds 10 MB — plain Markdown should never be that large.
    func load(_ document: MarkdownDocument) throws -> MarkdownDocument {
        let resourceValues = try document.fileURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = resourceValues.fileSize ?? 0
        guard fileSize <= 10_000_000 else {
            throw CocoaError(.fileReadTooLarge)
        }
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

    // MARK: - Renaming

    /// Renames a document on disk. The caller passes a display name (no extension);
    /// `.md` is appended automatically. If the name already has `.md`, it is stripped first.
    /// Returns the updated MarkdownDocument with the new URL and filename.
    func rename(_ document: MarkdownDocument, to newDisplayName: String) throws -> MarkdownDocument {
        var name = newDisplayName.trimmingCharacters(in: .whitespaces)
        if name.lowercased().hasSuffix(".md") {
            name = String(name.dropLast(3)).trimmingCharacters(in: .whitespaces)
        }
        // Reject empty names and any name that contains path-separator or null characters,
        // which could be used to escape baseDirectory.
        guard !name.isEmpty,
              !name.contains("/"),
              !name.contains("\0"),
              name != "..",
              name != "." else { return document }
        let newFilename = name + ".md"
        let newURL = baseDirectory.appending(path: newFilename, directoryHint: .notDirectory)
        // Belt-and-suspenders: the resolved path must stay inside baseDirectory.
        let basePath = baseDirectory.standardized.path
        guard newURL.standardized.path.hasPrefix(basePath + "/") ||
              newURL.standardized.path == basePath else { return document }
        guard newURL != document.fileURL else { return document }   // no-op rename
        try FileManager.default.moveItem(at: document.fileURL, to: newURL)
        var renamed = document
        renamed.filename = newFilename
        renamed.fileURL = newURL
        return renamed
    }

    // MARK: - Search

    /// Case-insensitive full-text search across all documents.
    ///
    /// Strategy: check the filename first (no disk read). If that misses,
    /// read the file and scan line-by-line. The first matching line becomes
    /// the snippet. This is fast enough for personal note collections
    /// (dozens to low hundreds of files, each under 1 MB).
    func search(query: String) throws -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        let docs = try loadAll()
        var results: [SearchResult] = []

        for doc in docs {
            let nameMatch = doc.displayName.lowercased().contains(q)

            // Respect the same 10 MB cap as load(_:) — skip content search on
            // oversized files rather than blocking the main thread.
            let fileSize = (try? doc.fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            let content: String
            if fileSize <= 10_000_000 {
                content = (try? String(contentsOf: doc.fileURL, encoding: .utf8)) ?? ""
            } else {
                content = ""
            }

            let matchingLine = content.components(separatedBy: .newlines)
                .first(where: { $0.lowercased().contains(q) })?
                .trimmingCharacters(in: .whitespaces)

            if nameMatch || matchingLine != nil {
                results.append(SearchResult(document: doc, snippet: matchingLine ?? ""))
            }
        }
        return results
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
