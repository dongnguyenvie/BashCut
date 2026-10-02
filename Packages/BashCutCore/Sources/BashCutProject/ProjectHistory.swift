import DequeModule

public struct HistoryEntry: Codable, Sendable {
    public let label: String
    public let author: Author
    public let operation: EditOperation
}

public struct ProjectHistory: Codable, Sendable {
    public private(set) var project: Project
    public private(set) var undoEntries: Deque<HistoryEntry> = []
    public private(set) var redoEntries: Deque<HistoryEntry> = []
    public init(project: Project) { self.project = project }

    public mutating func apply(
        _ operation: EditOperation, label: String, author: Author = .user,
        baseRevision: Int? = nil
    ) throws {
        let result = try project.applying(operation, baseRevision: baseRevision)
        undoEntries.append(HistoryEntry(label: label, author: author, operation: result.inverse))
        redoEntries.removeAll()
        project = result.project
    }
    public mutating func undo() throws {
        guard let entry = undoEntries.last else { return }
        let result = try project.applying(entry.operation)
        undoEntries.removeLast()
        redoEntries.append(
            HistoryEntry(label: entry.label, author: entry.author, operation: result.inverse))
        project = result.project
    }
    public mutating func redo() throws {
        guard let entry = redoEntries.last else { return }
        let result = try project.applying(entry.operation)
        redoEntries.removeLast()
        undoEntries.append(
            HistoryEntry(label: entry.label, author: entry.author, operation: result.inverse))
        project = result.project
    }
}
