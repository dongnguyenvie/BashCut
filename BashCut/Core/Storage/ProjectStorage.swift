import BashCutProject
import Foundation

public struct ProjectLoad: Sendable {
    public let history: ProjectHistory
    public let diskData: Data
    public let recovery: ProjectHistory?
    public let warning: String?
}

public enum StorageError: Error, LocalizedError {
    case changedOnDisk
    public var errorDescription: String? {
        "The project changed on disk. Resolve the conflict before saving."
    }
}

private struct Recovery: Codable {
    let baseline: Data
    let history: ProjectHistory
}

/// Serializes atomic writes and checks the caller's disk version before replacing the project.
public actor ProjectStorage {
    public static let projectFileName = "project.bashcut.json"

    public init() {}

    /// The project file a path names: the path itself, or `project.bashcut.json` inside a folder.
    /// Nil when nothing usable is there (a folder without a project, or a missing file).
    public nonisolated static func projectFile(for url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        let url = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        guard isDirectory.boolValue else { return url }
        let file = url.appendingPathComponent(projectFileName)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    public func readData(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    public func load(_ url: URL) throws -> ProjectLoad {
        let data = try Data(contentsOf: url)
        let project = try Project.decode(data)
        var history = ProjectHistory(project: project)
        var warning: String?
        let journal = cache(url).appendingPathComponent("history.jsonl")
        if FileManager.default.fileExists(atPath: journal.path) {
            do {
                let restored = try JSONDecoder().decode(
                    ProjectHistory.self, from: Data(contentsOf: journal))
                if restored.project == project { history = restored }
            } catch { warning = "History could not be restored; the project is intact." }
        }
        let recoveryURL = cache(url).appendingPathComponent("autosave/latest.json")
        var recovery: ProjectHistory?
        if FileManager.default.fileExists(atPath: recoveryURL.path) {
            do {
                let record = try JSONDecoder().decode(Recovery.self, from: Data(contentsOf: recoveryURL))
                try record.history.project.validate()
                if record.baseline == data && record.history.project != project {
                    recovery = record.history
                }
            } catch { warning = "Autosave could not be read; the saved project is intact." }
        }
        return ProjectLoad(history: history, diskData: data, recovery: recovery, warning: warning)
    }

    @discardableResult
    public func save(_ history: ProjectHistory, to url: URL, expectedDisk: Data?) throws -> Data {
        let data = try history.project.data()
        let exists = FileManager.default.fileExists(atPath: url.path)
        if exists {
            guard let expectedDisk, try Data(contentsOf: url) == expectedDisk else {
                throw StorageError.changedOnDisk
            }
        } else if expectedDisk != nil {
            throw StorageError.changedOnDisk
        }
        try FileManager.default.createDirectory(at: cache(url), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var journal = try encoder.encode(history)
        journal.append(0x0a)
        // A mismatched journal is ignored after a crash between the two atomic renames.
        try journal.write(to: cache(url).appendingPathComponent("history.jsonl"), options: .atomic)
        try data.write(to: url, options: .atomic)
        return data
    }

    public func autosave(_ history: ProjectHistory, at url: URL, baseline: Data) throws {
        try history.project.validate()
        let directory = cache(url).appendingPathComponent("autosave")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Recovery(baseline: baseline, history: history))
        try data.write(to: directory.appendingPathComponent("latest.json"), options: .atomic)
    }

    public func discardRecovery(at url: URL) throws {
        let recovery = cache(url).appendingPathComponent("autosave/latest.json")
        if FileManager.default.fileExists(atPath: recovery.path) {
            try FileManager.default.removeItem(at: recovery)
        }
    }

    private func cache(_ url: URL) -> URL {
        // Projects have one canonical JSON; other filenames get isolated cache folders.
        let name =
            url.lastPathComponent == "project.bashcut.json"
            ? ".bashcut" : ".bashcut-" + url.lastPathComponent
        return url.deletingLastPathComponent().appendingPathComponent(name)
    }
}
