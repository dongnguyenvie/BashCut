import BashCutPlugin
import Foundation
import Testing

@Suite("Plugin author")
struct PluginAuthorTests {
    private func manifest(author: String) throws -> PluginManifest {
        let json = """
            {"schema": "bashcut.plugin/1", "id": "example.author", "name": "Author", "version": "1.0.0",
             "apiVersion": 2, "entrypoint": "bin/provider", "capabilities": ["audio.beats"]\(author)}
            """
        return try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
    }

    @Test("The manifest's author decodes with or without a url and is optional")
    func decode() throws {
        let linked = try manifest(author: #", "author": {"name": "Luan Tran", "url": "https://github.com/luantran069"}"#)
        try linked.validate()
        #expect(linked.author?.name == "Luan Tran")
        #expect(linked.author?.link?.absoluteString == "https://github.com/luantran069")
        let plain = try manifest(author: #", "author": {"name": "Luan Tran", "url": null}"#)
        try plain.validate()
        #expect(plain.author?.url == nil && plain.author?.link == nil)
        let none = try manifest(author: "")
        try none.validate()
        #expect(none.author == nil)
    }

    @Test("A blank name or a url that is not a web link is refused")
    func invalid() throws {
        for author in [
            #"{"name": ""}"#, #"{"name": "  Luan"}"#, #"{"name": "Luan", "url": "javascript:alert(1)"}"#,
            #"{"name": "Luan", "url": "file:///etc/passwd"}"#, #"{"name": "Luan", "url": "github.com/luan"}"#,
        ] {
            let plugin = try manifest(author: ", \"author\": \(author)")
            #expect(throws: PluginError.self) { try plugin.validate() }
        }
    }

    @Test("Registry entries carry the author, and search finds it")
    func registry() throws {
        let json = #"""
            {"schemaVersion": 1, "publishers": {},
             "plugins": [{"id": "bashcut.antigravity", "name": "Antigravity", "publisher": "bashcut",
              "author": {"name": "Luan Tran", "url": "https://github.com/luantran069"},
              "versions": [{"version": "0.0.3", "apiVersion": 5, "url": "https://github.com/a.zip", "sha256": "ab"}]},
             {"id": "bashcut.silence-markers", "name": "Silence Markers",
              "versions": [{"version": "0.0.4", "apiVersion": 2, "url": "https://github.com/b.zip", "sha256": "cd"}]}]}
            """#
        let document = try PluginRegistryClient.decode(Data(json.utf8))
        let entry = try #require(document.entry("bashcut.antigravity"))
        #expect(entry.author == PluginAuthor(name: "Luan Tran", url: "https://github.com/luantran069"))
        #expect(entry.matches("luan tran"))
        #expect(document.entry("bashcut.silence-markers")?.author == nil)
    }
}
