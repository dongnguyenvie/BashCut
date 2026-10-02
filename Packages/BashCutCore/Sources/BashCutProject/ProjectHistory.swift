import DequeModule
import Foundation

public struct HistoryEntry: Codable, Sendable {
    public let label: String
    public let author: Author
    public let operation: EditOperation

    /// The project before this step, when the step stores a snapshot inverse (every `applying` does).
    public var before: Project? {
        if case .restore(let project) = operation { return project }
        return nil
    }
}

/// Undo/redo over full-project snapshot inverses. Depth is bounded so memory and the on-disk
/// journal stay proportional to `maximumDepth`, not to the length of an editing session.
public struct ProjectHistory: Codable, Sendable {
    public static let maximumDepth = 200

    public private(set) var project: Project
    private var undoStack: Deque<HistoryEntry> = []
    private var redoStack: Deque<HistoryEntry> = []
    private var coalescing: (key: String, revision: Int, author: Author, date: Date)?

    private enum CodingKeys: String, CodingKey {
        case project
        case undoStack = "undoEntries"
        case redoStack = "redoEntries"
    }

    public init(project: Project) { self.project = project }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// Oldest first.
    public var undoEntries: [HistoryEntry] { Array(undoStack) }
    public var redoEntries: [HistoryEntry] { Array(redoStack) }
    public var lastUndo: HistoryEntry? { undoStack.last }

    /// A non-nil `coalescingKey` merges continuous input into the previous step when that step used
    /// the same key and author less than a second ago and nothing else changed the project since.
    /// The kept entry's snapshot inverse still restores the state before the first merged edit.
    public mutating func apply(
        _ operation: EditOperation, label: String, author: Author = .user,
        baseRevision: Int? = nil, coalescingKey: String? = nil, now: Date = Date()
    ) throws {
        let result = try project.applying(operation, baseRevision: baseRevision)
        var merges = false
        if let key = coalescingKey, let last = coalescing, !undoStack.isEmpty, redoStack.isEmpty {
            merges = last.key == key && last.revision == project.revision && last.author == author
                && now.timeIntervalSince(last.date) < 1
        }
        if !merges {
            undoStack.append(HistoryEntry(label: label, author: author, operation: result.inverse))
            if undoStack.count > Self.maximumDepth { undoStack.removeFirst(undoStack.count - Self.maximumDepth) }
        }
        redoStack.removeAll()
        project = result.project
        coalescing = coalescingKey.map { ($0, project.revision, author, now) }
    }

    public mutating func undo() throws {
        coalescing = nil
        guard let entry = undoStack.last else { return }
        let result = try project.applying(entry.operation)
        undoStack.removeLast()
        redoStack.append(HistoryEntry(label: entry.label, author: entry.author, operation: result.inverse))
        project = result.project
    }

    public mutating func redo() throws {
        coalescing = nil
        guard let entry = redoStack.last else { return }
        let result = try project.applying(entry.operation)
        redoStack.removeLast()
        undoStack.append(HistoryEntry(label: entry.label, author: entry.author, operation: result.inverse))
        project = result.project
    }
}
