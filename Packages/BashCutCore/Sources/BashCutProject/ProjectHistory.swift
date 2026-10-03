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

    /// Snapshot steps are journaled as `ProjectDelta`s, each against the next newer state (the current
    /// project for the newest step), so the journal grows with what changed rather than with project size.
    /// Journals written with full `operation` snapshots still load.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        project = try container.decode(Project.self, forKey: .project)
        undoStack = Deque(try Self.expand(container.decode([StoredEntry].self, forKey: .undoStack), newest: project))
        redoStack = Deque(try Self.expand(container.decode([StoredEntry].self, forKey: .redoStack), newest: project))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(project, forKey: .project)
        try container.encode(Self.compact(undoStack, newest: project), forKey: .undoStack)
        try container.encode(Self.compact(redoStack, newest: project), forKey: .redoStack)
    }

    private struct StoredEntry: Codable {
        let label: String
        let author: Author
        var operation: EditOperation?
        var delta: JSONValue?
    }

    /// Oldest first, like the stacks; walked newest first so each delta's base is already known.
    private static func compact(_ entries: Deque<HistoryEntry>, newest: Project) -> [StoredEntry] {
        var base = newest
        var stored: [StoredEntry] = []
        stored.reserveCapacity(entries.count)
        for entry in entries.reversed() {
            var value = StoredEntry(label: entry.label, author: entry.author)
            if case .restore(let snapshot) = entry.operation {
                value.delta = ProjectDelta.encode(snapshot, from: base)
                base = snapshot
            } else {
                value.operation = entry.operation
            }
            stored.append(value)
        }
        return stored.reversed()
    }

    private static func expand(_ stored: [StoredEntry], newest: Project) throws -> [HistoryEntry] {
        var base = newest
        var entries: [HistoryEntry] = []
        entries.reserveCapacity(stored.count)
        for value in stored.reversed() {
            let operation: EditOperation
            if let delta = value.delta {
                let snapshot = try ProjectDelta.apply(delta, to: base)
                operation = .restore(snapshot)
                base = snapshot
            } else if let stored = value.operation {
                operation = stored
                if case .restore(let snapshot) = stored { base = snapshot }
            } else {
                throw ProjectError.invalid("History entry has neither an operation nor a delta")
            }
            entries.append(HistoryEntry(label: value.label, author: value.author, operation: operation))
        }
        return entries.reversed()
    }

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
