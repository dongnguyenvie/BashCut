import BashCutProject
import BashCutStorage
import Foundation
import Observation

/// Keeps the open project file and the editor in step: saves and autosaves against the bytes last
/// read from disk, watches the folder for edits made outside BashCut, and holds the disk version
/// while the user resolves a conflict. History itself stays with the document, which applies any
/// reload this controller reports.
@MainActor @Observable
public final class FileSyncController {
    /// What a disk check found.
    public enum DiskChange: Equatable {
        /// The file still matches what BashCut last read or wrote (or a check is not possible now).
        case unchanged
        /// The file changed while the document had unsaved edits; `conflict` is now true.
        case conflict
        /// The file changed and the document had no unsaved edits: show `project`, then call
        /// `accept(_:)` with `data` once it is in history.
        case reload(Project, data: Data)
    }

    public let storage: ProjectStorage
    /// The project file's bytes as BashCut last read or wrote them; saves refuse to overwrite anything else.
    public private(set) var diskData: Data?
    /// The disk version during a conflict, for the differences sheet.
    public private(set) var externalProject: Project?
    public private(set) var conflict = false
    public private(set) var saving = false
    @ObservationIgnored private var externalData: Data?
    @ObservationIgnored private var checking = false
    @ObservationIgnored private var monitor: ProjectFileMonitor?
    @ObservationIgnored private var lastAutosaveRevision = -1
    /// Bumped by `reset`; work that started for an older file drops its result.
    @ObservationIgnored private var generation = 0

    public init(storage: ProjectStorage = ProjectStorage()) {
        self.storage = storage
    }

    /// Starts over for a newly opened or created file whose bytes are `diskData`.
    public func reset(diskData: Data? = nil) {
        monitor?.cancel()
        monitor = nil
        generation += 1
        self.diskData = diskData
        externalData = nil
        externalProject = nil
        conflict = false
        lastAutosaveRevision = -1
    }

    /// Records bytes that are now on disk because BashCut wrote or loaded them.
    public func accept(_ data: Data) {
        diskData = data
    }

    /// Calls `onChange` when anything in the project folder changes, until the next `reset`.
    public func watch(_ fileURL: URL, onChange: @escaping @MainActor () -> Void) {
        monitor?.cancel()
        let current = generation
        monitor = try? ProjectFileMonitor(fileURL: fileURL) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == current else { return }
                onChange()
            }
        }
    }

    /// Saves `history` unless the file changed on disk since BashCut last read it. Returns false when
    /// another file was opened meanwhile. A disk change sets `conflict`, captures the disk version
    /// and throws the `StorageError`.
    public func save(_ history: ProjectHistory, to fileURL: URL) async throws -> Bool {
        guard !saving else { throw ProjectError.invalid("A save is already running") }
        guard !conflict else { throw ProjectError.invalid(String(localized: "Resolve the file conflict before editing.")) }
        let current = generation
        saving = true
        defer { saving = false }
        do {
            let written = try await storage.save(history, to: fileURL, expectedDisk: diskData)
            guard current == generation else { return false }
            diskData = written
            return true
        } catch let error as StorageError {
            guard current == generation else { throw error }
            conflict = true
            if let data = try? await storage.readData(fileURL), current == generation,
                let decoded = try? Project.decode(data)
            {
                externalData = data
                externalProject = decoded
            }
            throw error
        }
    }

    /// Writes the recovery file when `history` has unsaved edits not autosaved yet.
    public func autosave(_ history: ProjectHistory, at fileURL: URL, dirty: Bool) async throws {
        guard let diskData, dirty, !saving, lastAutosaveRevision != history.project.revision else { return }
        let current = generation
        try await storage.autosave(history, at: fileURL, baseline: diskData)
        if current == generation { lastAutosaveRevision = history.project.revision }
    }

    /// Reads the file and reports whether it changed outside BashCut. `dirty` decides between a
    /// conflict and a reload.
    public func checkDisk(_ fileURL: URL, dirty: Bool) async throws -> DiskChange {
        guard let diskData, !saving, !checking, !conflict else { return .unchanged }
        checking = true
        defer { checking = false }
        let current = generation
        let data = try await storage.readData(fileURL)
        guard current == generation, data != diskData, data != externalData else { return .unchanged }
        let project = try Project.decode(data)
        externalData = data
        if dirty {
            externalProject = project
            conflict = true
            return .conflict
        }
        externalProject = nil
        return .reload(project, data: data)
    }

    /// Reads the disk version to end a conflict; nil when another file was opened meanwhile. Call
    /// `resolve(with:)` once the document has kept or loaded it.
    public func readDisk(_ fileURL: URL) async throws -> Data? {
        let current = generation
        let data = try await storage.readData(fileURL)
        return current == generation ? data : nil
    }

    /// Ends a conflict: `data` is what is on disk now.
    public func resolve(with data: Data) {
        diskData = data
        externalData = nil
        externalProject = nil
        conflict = false
    }
}
