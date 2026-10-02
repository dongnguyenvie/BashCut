import BashCutProject
import Foundation
import Testing

@testable import BashCutStorage

struct ProjectStorageTests {
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private func addCaption(_ history: inout ProjectHistory) throws {
        var caption = Item(id: UUID().uuidString, at: 0, duration: 30)
        caption["text"] = .string("Tiếng Việt")
        try history.apply(.insert(track: "t1", item: caption), label: "Caption")
    }

    @Test("A project path may name the file or its folder; anything else has no project")
    func projectFileForPath() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(ProjectStorage.projectFile(for: folder) == nil)
        let file = folder.appendingPathComponent(ProjectStorage.projectFileName)
        try Data("{}".utf8).write(to: file)
        #expect(ProjectStorage.projectFile(for: folder)?.lastPathComponent == ProjectStorage.projectFileName)
        #expect(ProjectStorage.projectFile(for: file)?.path == file.standardizedFileURL.path)
        #expect(ProjectStorage.projectFile(for: folder.appendingPathComponent("missing.json")) == nil)
    }

    @Test("Project file monitor receives directory write events")
    func fileMonitor() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("project.bashcut.json")
        try Data("{}".utf8).write(to: url)
        let event = MonitorEvent()
        let monitor = try ProjectFileMonitor(fileURL: url) {
            Task { await event.receive() }
        }
        defer { monitor.cancel() }
        try Data("{\"rev\":1}".utf8).write(to: url, options: .atomic)
        for _ in 0..<50 {
            if await event.received { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Project directory change was not observed")
    }

    @Test("Atomic save restores undo and redo across reopen")
    func saveAndReopen() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("project.bashcut.json")
        let store = ProjectStorage()
        var history = ProjectHistory(project: Project(name: "Test"))
        try addCaption(&history)
        try history.undo()
        let data = try await store.save(history, to: url, expectedDisk: nil)
        var loaded = try await store.load(url).history
        #expect(loaded.project == history.project)
        #expect(loaded.redoEntries.count == 1)
        try loaded.redo()
        #expect(loaded.project.tracks[2].items.count == 1)
        try await store.save(loaded, to: url, expectedDisk: data)
        #expect(try await store.load(url).history.undoEntries.count == 1)
    }

    @Test("External changes and deletion cannot be overwritten by stale saves")
    func conflict() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("project.bashcut.json")
        let store = ProjectStorage()
        var history = ProjectHistory(project: Project(name: "Test"))
        let baseline = try await store.save(history, to: url, expectedDisk: nil)
        let external = try Project(name: "External").data()
        try external.write(to: url, options: .atomic)
        try addCaption(&history)
        await #expect(throws: StorageError.self) {
            try await store.save(history, to: url, expectedDisk: baseline)
        }
        #expect(try Data(contentsOf: url) == external)
        try FileManager.default.removeItem(at: url)
        await #expect(throws: StorageError.self) {
            try await store.save(history, to: url, expectedDisk: baseline)
        }
    }

    @Test("Autosave preserves unsaved work and does not overwrite the saved project")
    func recovery() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("project.bashcut.json")
        let store = ProjectStorage()
        var history = ProjectHistory(project: Project(name: "Test"))
        let baseline = try await store.save(history, to: url, expectedDisk: nil)
        try addCaption(&history)
        try await store.autosave(history, at: url, baseline: baseline)
        #expect(try Data(contentsOf: url) == baseline)
        let loaded = try await store.load(url)
        #expect(loaded.recovery?.project == history.project)
        try await store.discardRecovery(at: url)
        #expect(try await store.load(url).recovery == nil)
    }

    @Test("Stale or damaged cache never replaces a valid project")
    func damagedCache() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("project.bashcut.json")
        let store = ProjectStorage()
        var history = ProjectHistory(project: Project(name: "Test"))
        let baseline = try await store.save(history, to: url, expectedDisk: nil)
        try addCaption(&history)
        try await store.autosave(history, at: url, baseline: baseline)
        let external = Project(name: "External")
        try external.data().write(to: url, options: .atomic)
        let loaded = try await store.load(url)
        #expect(loaded.history.project == external)
        #expect(loaded.recovery == nil)
        try Data("broken".utf8).write(to: root.appendingPathComponent(".bashcut/history.jsonl"))
        #expect(try await store.load(url).warning != nil)
    }
}

private actor MonitorEvent {
    private(set) var received = false
    func receive() { received = true }
}
