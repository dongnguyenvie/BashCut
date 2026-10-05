import BashCutProject
import BashCutStorage
import Foundation
import Testing

struct ProjectCreationTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    @Test("New project preserves settings and creates standard folders without altering footage")
    func createWithFootage() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let shoot = root.appendingPathComponent("shoot")
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: false)
        let original = shoot.appendingPathComponent("original.txt")
        try Data("untouched".utf8).write(to: original)
        var setup = ProjectSetup()
        setup.name = "  Lẩu Bò Đất  "
        setup.canvas = .landscape
        setup.resolution = .ultraHD
        setup.rate = .thirty
        setup.contentLanguage = "en-US"
        let store = ProjectStorage()
        let created = try await store.create(setup, in: root, footage: shoot)
        #expect(created.url.deletingLastPathComponent().lastPathComponent == "lau-bo-dat")
        let loaded = try await store.load(created.url)
        #expect(loaded.diskData == created.diskData)
        #expect(loaded.history.project.name == "Lẩu Bò Đất")
        #expect(loaded.history.project.width == 3840)
        #expect(loaded.history.project.height == 2160)
        #expect(loaded.history.project.fps == FrameRate(30, 1))
        #expect(loaded.history.project["contentLanguage"] == .string("en-US"))
        #expect(loaded.history.project["schema"] == .string(Project.schema))
        #expect(loaded.history.project["style"] == nil)
        #expect(loaded.history.project.revision == 0)
        let folder = created.url.deletingLastPathComponent()
        for name in ["media", "voiceover", "khao-sat", "subtitles", "render", ".bashcut"] {
            #expect(try folder.appendingPathComponent(name).resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        }
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".bashcut/.gitignore").path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: folder.appendingPathComponent("footage").path) == shoot.path)
        #expect(try String(contentsOf: original, encoding: .utf8) == "untouched")
    }

    @Test("Existing folders and dangling symlinks are never overwritten; staging folders are cleaned")
    func collisions() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var setup = ProjectSetup()
        setup.name = "Existing"
        let store = ProjectStorage()
        let created = try await store.create(setup, in: root)
        await #expect(throws: (any Error).self) { try await store.create(setup, in: root) }
        #expect(try Data(contentsOf: created.url) == created.diskData)
        setup.name = "Link"
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("missing"))
        await #expect(throws: (any Error).self) { try await store.create(setup, in: root) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path).hasSuffix("/missing"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["existing", "link"])
    }

    @Test("Invalid setup and missing footage leave the parent unchanged")
    func invalidSettings() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStorage()
        var setup = ProjectSetup()
        setup.name = "../.."
        await #expect(throws: (any Error).self) { try await store.create(setup, in: root) }
        setup.name = "My video"
        setup.contentLanguage = "not a tag"
        await #expect(throws: (any Error).self) { try await store.create(setup, in: root) }
        setup.contentLanguage = "vi"
        await #expect(throws: (any Error).self) {
            try await store.create(setup, in: root, footage: root.appendingPathComponent("missing"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        let created = try await store.create(setup, in: root)
        #expect(created.project.fps == FrameRate(30000, 1001))
        #expect(created.project.width == 1080 && created.project.height == 1920)
    }
}
