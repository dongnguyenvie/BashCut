import DequeModule
import Foundation

public struct HistoryEntry: Codable, Sendable {
    public let label: String
    public let author: Author
    public let operation: EditOperation
}

public struct ProjectHistory: Codable, Sendable {
    public private(set) var project: Project
    public private(set) var undoEntries: Deque<HistoryEntry> = []
    public private(set) var redoEntries: Deque<HistoryEntry> = []
    private var coalescing: (key: String, revision: Int, author: Author, date: Date)?

    private enum CodingKeys: String, CodingKey { case project, undoEntries, redoEntries }

    public init(project: Project) { self.project = project }

    /// A non-nil `coalescingKey` merges continuous input into the previous step when that step used
    /// the same key and author less than a second ago and nothing else changed the project since.
    /// The kept entry's snapshot inverse still restores the state before the first merged edit.
    public mutating func apply(
        _ operation: EditOperation, label: String, author: Author = .user,
        baseRevision: Int? = nil, coalescingKey: String? = nil, now: Date = Date()
    ) throws {
        let result = try project.applying(operation, baseRevision: baseRevision)
        var merges = false
        if let key = coalescingKey, let last = coalescing, !undoEntries.isEmpty, redoEntries.isEmpty {
            merges = last.key == key && last.revision == project.revision && last.author == author
                && now.timeIntervalSince(last.date) < 1
        }
        if !merges {
            undoEntries.append(HistoryEntry(label: label, author: author, operation: result.inverse))
        }
        redoEntries.removeAll()
        project = result.project
        coalescing = coalescingKey.map { ($0, project.revision, author, now) }
    }
    public mutating func undo() throws {
        coalescing = nil
        guard let entry = undoEntries.last else { return }
        let result = try project.applying(entry.operation)
        undoEntries.removeLast()
        redoEntries.append(
            HistoryEntry(label: entry.label, author: entry.author, operation: result.inverse))
        project = result.project
    }
    public mutating func redo() throws {
        coalescing = nil
        guard let entry = redoEntries.last else { return }
        let result = try project.applying(entry.operation)
        redoEntries.removeLast()
        undoEntries.append(
            HistoryEntry(label: entry.label, author: entry.author, operation: result.inverse))
        project = result.project
    }
}
