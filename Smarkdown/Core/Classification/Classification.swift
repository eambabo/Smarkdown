import Foundation

enum ClassificationType: String, CaseIterable {
    case task     = "task"
    case idea     = "idea"
    case question = "question"
}

enum ClassificationStatus: String {
    case active    = "active"
    case completed = "completed"
    case archived  = "archived"
}

/// Whether a classification was created manually by the user or by the LLM.
/// Used by the feedback loop to build few-shot examples for the dynamic prompt.
enum ClassificationSource: String {
    case manual = "manual"
    case llm    = "llm"
}

struct Classification: Identifiable {
    let id: UUID
    let documentURL: URL
    let documentName: String
    let contentText: String
    let type: ClassificationType
    var status: ClassificationStatus
    /// How this classification was created. Defaults to .manual for backwards
    /// compatibility — pre-7b rows read from SQLite will have DEFAULT 'manual'.
    let source: ClassificationSource
    let createdAt: Date
    /// Set when status transitions to .archived. Used by the feedback loop to
    /// identify LLM suggestions the user rejected quickly (negative examples).
    var archivedAt: Date?
}

/// Extended attributes for a task classification.
/// Stored in the `task_details` table, keyed by taskID.
struct TaskDetail {
    let taskID: UUID
    var dueDate: Date?
    /// Duration stored as total minutes. Convert for display using TimeEstimateUnit.
    var estimatedMinutes: Int?
    var details: String
}

/// A pre-computed (range, type) pair used to draw gutter dots in the editor.
/// Ranges are recomputed from the database after every text change by
/// searching for contentText in the current document.
struct ClassificationMarker {
    let range: NSRange
    let type: ClassificationType
}
