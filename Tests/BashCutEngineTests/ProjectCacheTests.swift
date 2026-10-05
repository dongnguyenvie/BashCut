import BashCutProject
import Foundation
import Testing

@testable import BashCutEngine

@Suite("Project cache folder")
struct ProjectCacheTests {
    private func project() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".bashcut"), withIntermediateDirectories: true)
        return root
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test("Older cache folders move into .bashcut/cache once; files already there win")
    func movesLegacyFolders() throws {
        let root = try project()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("old proxy", to: root.appendingPathComponent(".bashcut/proxies/m1.mov"))
        try write("old ramp", to: root.appendingPathComponent(".bashcut/ramp-audio/a.caf"))
        try write("old still", to: root.appendingPathComponent(".bashcut/stills/s1.mov"))
        try write("new still", to: ProjectCache.url(.stills, projectRoot: root).appendingPathComponent("s1.mov"))
        try write("history", to: root.appendingPathComponent(".bashcut/history.jsonl"))

        let moved = ProjectCache.prepare(projectRoot: root)
        #expect(Set(moved) == ["proxies", "ramp-audio", "stills"])
        let proxy = ProjectCache.url(.proxies, projectRoot: root).appendingPathComponent("m1.mov")
        #expect(try String(contentsOf: proxy, encoding: .utf8) == "old proxy")
        #expect(ProxyMediaSource.proxyURL(for: Media(fields: ["id": .string("m1"), "path": .string("media/m1.mov")]), root: root)?.path == proxy.path)
        let still = ProjectCache.url(.stills, projectRoot: root).appendingPathComponent("s1.mov")
        #expect(try String(contentsOf: still, encoding: .utf8) == "new still")
        for name in ["proxies", "ramp-audio", "stills"] {
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".bashcut/" + name).path))
        }
        // Project data stays where it is.
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".bashcut/history.jsonl").path))
        let values = try ProjectCache.root(projectRoot: root).resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        #expect(ProjectCache.prepare(projectRoot: root).isEmpty)
    }

    @Test("A folder without .bashcut is left alone")
    func ignoresOtherFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ProjectCache.prepare(projectRoot: root).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".bashcut").path))
    }
}
