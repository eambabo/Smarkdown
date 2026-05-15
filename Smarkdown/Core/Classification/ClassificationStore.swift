import Foundation
import SQLite3

/// Persists classifications in a SQLite database at
/// ~/Library/Application Support/Smarkdown/smarkdown.db.
///
/// All methods run on the main actor — SQLite3 is not thread-safe by default,
/// and all callers are @MainActor already. Raw SQLite3 is used directly to
/// avoid adding another SPM package; the schema is simple enough that the
/// extra boilerplate is manageable.
@MainActor
final class ClassificationStore {

    static let shared = ClassificationStore()

    private var db: OpaquePointer?

    /// sqlite3_destructor_type value for SQLITE_TRANSIENT — SQLite copies the
    /// string before bind returns, so callers don't need to keep it alive.
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() {
        openDatabase()
        createSchemaIfNeeded()
    }

    // MARK: - Setup

    private func openDatabase() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let dir = appSupport.appending(path: "Smarkdown", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appending(path: "smarkdown.db", directoryHint: .notDirectory)
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            assertionFailure("ClassificationStore: failed to open database — \(msg)")
            db = nil
        }
    }

    private func createSchemaIfNeeded() {
        let sql = """
            CREATE TABLE IF NOT EXISTS classifications (
                id           TEXT PRIMARY KEY,
                document_url TEXT NOT NULL,
                document_name TEXT NOT NULL,
                content_text TEXT NOT NULL,
                type         TEXT NOT NULL,
                status       TEXT NOT NULL DEFAULT 'active',
                created_at   REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_type ON classifications(type);
            CREATE INDEX IF NOT EXISTS idx_doc  ON classifications(document_url);
            CREATE TABLE IF NOT EXISTS task_details (
                task_id     TEXT PRIMARY KEY,
                due_date    REAL,
                est_minutes INTEGER,
                details     TEXT NOT NULL DEFAULT ''
            );
        """
        sqlite3_exec(db, sql, nil, nil, nil)

        // Additive migrations — run as separate sqlite3_exec calls so if one
        // fails (column already exists from a previous launch), the other still runs.
        sqlite3_exec(db,
            "ALTER TABLE classifications ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'",
            nil, nil, nil)
        sqlite3_exec(db,
            "ALTER TABLE classifications ADD COLUMN archived_at REAL",
            nil, nil, nil)
    }

    // MARK: - Write helpers

    /// Executes a write statement and asserts SQLITE_DONE in debug builds.
    /// SQLITE_DONE is the success code for INSERT/UPDATE/DELETE; SQLITE_OK is for
    /// non-data operations like sqlite3_exec. Confusing them causes silent failures.
    @discardableResult
    private func writeStep(_ stmt: OpaquePointer?) -> Int32 {
        let rc = sqlite3_step(stmt)
        assert(rc == SQLITE_DONE, "SQLite write failed with code \(rc): \(String(cString: sqlite3_errmsg(db)))")
        return rc
    }

    // MARK: - Write

    func insert(_ classification: Classification) {
        let sql = """
            INSERT INTO classifications
                (id, document_url, document_name, content_text, type, status, created_at, source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, classification.id.uuidString,                    -1, transient)
        sqlite3_bind_text(stmt, 2, classification.documentURL.path,                 -1, transient)
        sqlite3_bind_text(stmt, 3, classification.documentName,                     -1, transient)
        sqlite3_bind_text(stmt, 4, classification.contentText,                      -1, transient)
        sqlite3_bind_text(stmt, 5, classification.type.rawValue,                    -1, transient)
        sqlite3_bind_text(stmt, 6, classification.status.rawValue,                  -1, transient)
        sqlite3_bind_double(stmt, 7, classification.createdAt.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 8, classification.source.rawValue,                  -1, transient)

        writeStep(stmt)
    }

    // MARK: - Update

    func updateStatus(_ id: UUID, status: ClassificationStatus) {
        // Record archived_at timestamp when archiving so the feedback loop can
        // measure how quickly the user dismissed an LLM suggestion (quick dismissal
        // = negative example). Clear it if the status changes away from archived.
        let sql = "UPDATE classifications SET status = ?, archived_at = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, status.rawValue, -1, transient)
        if status == .archived {
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_text(stmt, 3, id.uuidString, -1, transient)
        writeStep(stmt)
    }

    // MARK: - Task details

    func upsertTaskDetail(_ detail: TaskDetail) {
        let sql = """
            INSERT INTO task_details (task_id, due_date, est_minutes, details)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(task_id) DO UPDATE SET
                due_date    = excluded.due_date,
                est_minutes = excluded.est_minutes,
                details     = excluded.details
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, detail.taskID.uuidString, -1, transient)
        if let d = detail.dueDate {
            sqlite3_bind_double(stmt, 2, d.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        if let m = detail.estimatedMinutes {
            sqlite3_bind_int(stmt, 3, Int32(m))
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_text(stmt, 4, detail.details, -1, transient)
        writeStep(stmt)
    }

    func fetchTaskDetail(for taskID: UUID) -> TaskDetail? {
        let sql = "SELECT due_date, est_minutes, details FROM task_details WHERE task_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, taskID.uuidString, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let dueDate: Date? = sqlite3_column_type(stmt, 0) != SQLITE_NULL
            ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
            : nil
        let estMinutes: Int? = sqlite3_column_type(stmt, 1) != SQLITE_NULL
            ? Int(sqlite3_column_int(stmt, 1))
            : nil
        let details = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""

        return TaskDetail(taskID: taskID, dueDate: dueDate, estimatedMinutes: estMinutes, details: details)
    }

    // MARK: - Deduplication

    /// Returns true if an active or completed classification with the same text,
    /// document, and type already exists. Archived items are excluded so the user
    /// can re-classify a line they previously archived.
    func contentTextExists(_ text: String, for documentURL: URL, type: ClassificationType) -> Bool {
        let sql = """
            SELECT 1 FROM classifications
            WHERE content_text = ? AND document_url = ? AND type = ? AND status != 'archived'
            LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, text,             -1, transient)
        sqlite3_bind_text(stmt, 2, documentURL.path, -1, transient)
        sqlite3_bind_text(stmt, 3, type.rawValue,    -1, transient)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    // MARK: - Read

    /// Fetches classifications, optionally filtered by document URL and/or type.
    /// Results are sorted newest-first.
    func fetchAll(for documentURL: URL? = nil, type: ClassificationType? = nil) -> [Classification] {
        var sql = """
            SELECT id, document_url, document_name, content_text, type, status, created_at,
                   source, archived_at
            FROM classifications
        """
        var conditions: [String] = []
        if documentURL != nil { conditions.append("document_url = ?") }
        if type != nil        { conditions.append("type = ?") }
        if !conditions.isEmpty { sql += " WHERE " + conditions.joined(separator: " AND ") }
        sql += " ORDER BY created_at DESC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var paramIndex: Int32 = 1
        if let url = documentURL {
            sqlite3_bind_text(stmt, paramIndex, url.path, -1, transient)
            paramIndex += 1
        }
        if let t = type {
            sqlite3_bind_text(stmt, paramIndex, t.rawValue, -1, transient)
        }

        var results: [Classification] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let col0 = sqlite3_column_text(stmt, 0),
                let col1 = sqlite3_column_text(stmt, 1),
                let col2 = sqlite3_column_text(stmt, 2),
                let col3 = sqlite3_column_text(stmt, 3),
                let col4 = sqlite3_column_text(stmt, 4),
                let col5 = sqlite3_column_text(stmt, 5)
            else { continue }

            let idStr   = String(cString: col0)
            let urlPath = String(cString: col1)
            let docName = String(cString: col2)
            let content = String(cString: col3)
            let typeStr = String(cString: col4)
            let status  = String(cString: col5)
            let ts      = sqlite3_column_double(stmt, 6)
            // col 7: source — fall back to .manual for rows written before 7b
            let sourceStr  = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? "manual"
            let archivedAt: Date? = sqlite3_column_type(stmt, 8) != SQLITE_NULL
                ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
                : nil

            guard let id         = UUID(uuidString: idStr),
                  let type       = ClassificationType(rawValue: typeStr),
                  let statusEnum = ClassificationStatus(rawValue: status)
            else { continue }

            let source = ClassificationSource(rawValue: sourceStr) ?? .manual

            results.append(Classification(
                id: id,
                documentURL: URL(fileURLWithPath: urlPath),
                documentName: docName,
                contentText: content,
                type: type,
                status: statusEnum,
                source: source,
                createdAt: Date(timeIntervalSince1970: ts),
                archivedAt: archivedAt
            ))
        }
        return results
    }

    // MARK: - Feedback loop queries

    /// Active and completed classifications for a given type, ordered manual-first.
    /// Used as positive few-shot examples in the adaptive system prompt.
    func positiveExamples(type: ClassificationType, limit: Int) -> [String] {
        let sql = """
            SELECT content_text FROM classifications
            WHERE type = ? AND status IN ('active', 'completed')
            ORDER BY CASE source WHEN 'manual' THEN 0 ELSE 1 END, created_at DESC
            LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, type.rawValue, -1, transient)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let col = sqlite3_column_text(stmt, 0) {
                results.append(String(cString: col))
            }
        }
        return results
    }

    /// LLM-sourced items the user archived within 60 seconds of creation.
    /// Quick dismissal is a strong signal of rejection — negative few-shot examples.
    func negativeExamples(type: ClassificationType, limit: Int) -> [String] {
        let sql = """
            SELECT content_text FROM classifications
            WHERE type = ? AND source = 'llm' AND status = 'archived'
              AND archived_at IS NOT NULL
              AND (archived_at - created_at) <= 60
            ORDER BY archived_at DESC
            LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, type.rawValue, -1, transient)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let col = sqlite3_column_text(stmt, 0) {
                results.append(String(cString: col))
            }
        }
        return results
    }
}
