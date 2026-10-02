import BashCutDocument
import BashCutProject
import BashCutStorage
import Foundation
import Testing

@MainActor
struct FileSyncControllerTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Opens `name` saved at `url` like the document does: write it, then start from those bytes.
    private func opened(_ name: String, at url: URL) async throws -> (FileSyncController, ProjectHistory) {
        let sync = FileSyncController()
        let history = ProjectHistory(project: Project(name: name))
        let data = try await sync.storage.save(history, to: url, expectedDisk: nil)
        sync.reset(diskData: data)
        return (sync, history)
    }

    /// Simulates another program rewriting the file.
    private func writeOutside(_ name: String, to url: URL) throws {
        try Project(name: name).data().write(to: url, options: .atomic)
    }

    @Test("Saves write against the last bytes read and keep working after each save")
    func saves() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("project.bashcut.json")
        let (sync, history) = try await opened("One", at: url)
        #expect(try await sync.save(history, to: url))
        #expect(try await sync.save(ProjectHistory(project: Project(name: "Two")), to: url))
        #expect(try Project.decode(Data(contentsOf: url)).name == "Two")
        #expect(!sync.conflict && !sync.saving)
    }

    @Test("A clean document reloads an outside edit once; a dirty one gets a conflict")
    func diskChecks() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("project.bashcut.json")
        let (sync, _) = try await opened("One", at: url)
        #expect(try await sync.checkDisk(url, dirty: false) == .unchanged)

        try writeOutside("Outside", to: url)
        guard case .reload(let project, let data) = try await sync.checkDisk(url, dirty: false) else {
            Issue.record("Expected a reload")
            return
        }
        #expect(project.name == "Outside")
        sync.accept(data)
        #expect(try await sync.checkDisk(url, dirty: false) == .unchanged)

        try writeOutside("Again", to: url)
        #expect(try await sync.checkDisk(url, dirty: true) == .conflict)
        #expect(sync.conflict)
        #expect(sync.externalProject?.name == "Again")
        await #expect(throws: ProjectError.self) { try await sync.save(ProjectHistory(project: Project(name: "Mine")), to: url) }

        let disk = try #require(try await sync.readDisk(url))
        sync.resolve(with: disk)
        #expect(!sync.conflict && sync.externalProject == nil)
        #expect(try await sync.save(ProjectHistory(project: Project(name: "Mine")), to: url))
    }

    @Test("Saving over an outside edit refuses, captures the disk version and marks a conflict")
    func saveConflict() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("project.bashcut.json")
        let (sync, history) = try await opened("One", at: url)
        try writeOutside("Outside", to: url)
        await #expect(throws: StorageError.self) { try await sync.save(history, to: url) }
        #expect(sync.conflict)
        #expect(sync.externalProject?.name == "Outside")
        sync.reset()
        #expect(!sync.conflict && sync.diskData == nil && sync.externalProject == nil)
    }
}
