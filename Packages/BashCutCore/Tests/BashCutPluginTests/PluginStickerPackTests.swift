import BashCutPlugin
import Foundation
import Testing

@Suite("Plugin API 6: sticker packs")
struct PluginStickerPackTests {
    private func manifest(_ stickers: String, apiVersion: Int = 6) throws -> PluginManifest {
        try JSONDecoder().decode(PluginManifest.self, from: Data("""
            {"schema": "bashcut.plugin/1", "id": "example.stickers", "name": "Stickers", "version": "1.0.0",
             "apiVersion": \(apiVersion), "entrypoint": "bin/provider", "contributes": {"stickers": \(stickers)}}
            """.utf8))
    }

    @Test("A plugin that only contributes sticker packs decodes and validates")
    func validManifest() throws {
        let plugin = try manifest(
            #"[{"id": "example.stickers.food", "title": {"en": "Food", "vi": "Đồ ăn"}, "path": "packs/food"}]"#)
        try plugin.validate()
        #expect(plugin.stickerPacks.map(\.id) == ["example.stickers.food"])
        #expect(plugin.stickerPacks.first?.title.text(for: "vi") == "Đồ ăn")
        #expect(plugin.stickerPacks.first?.path == "packs/food")
    }

    @Test("Packs need API 6, an id under the plugin's, unique ids and a path inside the bundle", arguments: [
        (#"[{"id": "example.stickers.a", "title": "A", "path": "a"}]"#, 5),
        (#"[{"id": "other.a", "title": "A", "path": "a"}]"#, 6),
        (#"[{"id": "example.stickers.a", "title": "A", "path": "../a"}]"#, 6),
        (#"[{"id": "example.stickers.a", "title": "A", "path": "/tmp/a"}]"#, 6),
        (#"[{"id": "example.stickers.a", "title": "A", "path": ""}]"#, 6),
        (#"[{"id": "example.stickers.a", "title": "", "path": "a"}]"#, 6),
        (#"[{"id": "example.stickers.a", "title": "A", "path": "a"}, {"id": "example.stickers.a", "title": "B", "path": "b"}]"#, 6),
    ])
    func invalidManifest(stickers: String, apiVersion: Int) throws {
        let plugin = try manifest(stickers, apiVersion: apiVersion)
        #expect(throws: PluginError.self) { try plugin.validate() }
    }

    @Test("A pack folder resolves inside the plugin; a missing folder or a symlink out of it does not")
    func stickerFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("plugin")
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("stickers"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("escape"), withDestinationURL: outside)
        defer { try? FileManager.default.removeItem(at: root) }
        let plugin = InstalledPlugin(
            manifest: try manifest(#"[{"id": "example.stickers.a", "title": "A", "path": "stickers"}]"#), directory: directory)
        func pack(_ path: String) -> PluginStickerPack { PluginStickerPack(id: "example.stickers.a", title: "A", path: path) }
        #expect(plugin.stickerFolder(pack("stickers"))?.lastPathComponent == "stickers")
        #expect(plugin.stickerFolder(pack("missing")) == nil)
        #expect(plugin.stickerFolder(pack("escape")) == nil)
    }
}
