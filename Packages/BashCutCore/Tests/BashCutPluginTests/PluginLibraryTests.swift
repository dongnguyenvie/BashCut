import BashCutPlugin
import BashCutProject
import Foundation
import Testing

/// Plugin API 6 (#81): library packs in `contributes.library`, and `library.search`/`library.generate` providers.
@Suite("Plugin library packs and providers")
struct PluginLibraryTests {
    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("plugin-library-\(UUID().uuidString)", isDirectory: true)
    }

    private func manifest(_ json: String) throws -> PluginManifest {
        try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
    }

    private func base(_ extra: String, apiVersion: Int = 6, capabilities: String = "[]") -> String {
        """
        {"schema": "bashcut.plugin/1", "id": "example.sounds", "name": "Example Sounds", "version": "1.2.0",
         "apiVersion": \(apiVersion), "entrypoint": "bin/provider", "capabilities": \(capabilities)\(extra)}
        """
    }

    /// A plugin folder with a music pack (`packs/music`: an audio file and an emoji sticker) and `extra` manifest
    /// fields.
    private static func plugin(
        in root: URL, id: String = "example.sounds", items: [String]? = nil, packPath: String = "packs/music"
    ) throws -> InstalledPlugin {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        let pack = directory.appendingPathComponent(packPath, isDirectory: true)
        try FileManager.default.createDirectory(at: pack.appendingPathComponent("files"), withIntermediateDirectories: true)
        try Data("RIFF fake wave".utf8).write(to: pack.appendingPathComponent("files/beat.wav"))
        let entries = items ?? [
            #"{"id": "lofi-beat", "kind": "audio", "name": "Lo-fi beat", "file": "files/beat.wav", "license": "CC0","#
                + #" "tags": ["calm"], "params": {"role": "music"}}"#,
            #"{"id": "wave-hand", "kind": "sticker", "name": "Wave", "params": {"emoji": "👋"}}"#,
        ]
        try Data(#"{"format": 1, "name": "Lo-fi", "items": [\#(entries.joined(separator: ","))]}"#.utf8)
            .write(to: pack.appendingPathComponent("pack.json"))
        let manifest = PluginManifest(
            id: id, name: LocalizedText(["en": "Example Sounds"]), version: "1.2.0", apiVersion: 6,
            entrypoint: "bin/provider", capabilities: [],
            contributes: PluginContributions(library: [PluginLibraryContribution(path: packPath)]))
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))
        return InstalledPlugin(manifest: manifest, directory: directory)
    }

    @Test("A library plugin validates: packs, search and generate providers with kinds")
    func validManifest() throws {
        let plugin = try manifest(base("""
            , "providers": [
              {"id": "example.sounds.search", "capability": "library.search", "name": "Search", "kinds": ["audio"]},
              {"id": "example.sounds.make", "capability": "library.generate", "name": "Make", "timeoutSeconds": 600}
            ],
            "contributes": {"library": [{"path": "packs/music"}, {"path": "packs/stickers"}]}
            """, capabilities: #"["library.search", "library.generate"]"#))
        try plugin.validate()
        #expect(plugin.libraryPacks.map(\.path) == ["packs/music", "packs/stickers"])
        let search = try #require(plugin.providers?.first)
        #expect(search.serves(.audio) && !search.serves(.sticker))
        #expect(plugin.providers?.last?.serves(.sticker) == true)
        #expect(plugin.incompatibility == nil)
        // A pack-only plugin needs no capabilities.
        try manifest(base(#", "contributes": {"library": [{"path": "pack"}]}"#)).validate()
    }

    @Test("Library manifests are refused when they leave the bundle or misuse kinds", arguments: [
        // Pack paths stay inside the plugin folder.
        ("[]", #", "contributes": {"library": [{"path": "../other/pack"}]}"#),
        ("[]", #", "contributes": {"library": [{"path": "/Users/me/pack"}]}"#),
        ("[]", #", "contributes": {"library": [{"path": "packs/../../x"}]}"#),
        ("[]", #", "contributes": {"library": [{"path": "~/pack"}]}"#),
        ("[]", #", "contributes": {"library": [{"path": ""}]}"#),
        // The same folder twice.
        ("[]", #", "contributes": {"library": [{"path": "pack"}, {"path": "pack/"}]}"#),
        // Kinds are for library providers, and must be library kinds.
        (#"["audio.beats"]"#, #", "providers": [{"id": "a.b", "capability": "audio.beats", "name": "B", "kinds": ["audio"]}]"#),
        (#"["library.search"]"#, #", "providers": [{"id": "a.b", "capability": "library.search", "name": "B", "kinds": ["song"]}]"#),
        (#"["library.search"]"#, #", "providers": [{"id": "a.b", "capability": "library.search", "name": "B", "kinds": []}]"#),
    ])
    func invalidManifest(capabilities: String, extra: String) throws {
        let plugin = try manifest(base(extra, capabilities: capabilities))
        #expect(throws: PluginError.self) { try plugin.validate() }
    }

    @Test("Library contributions and capabilities need API 6; older plugins stay valid")
    func apiWindow() throws {
        #expect(PluginAPI.current >= 6)
        let packs = try manifest(base(#", "contributes": {"library": [{"path": "pack"}]}"#, apiVersion: 5))
        #expect(throws: PluginError.self) { try packs.validate() }
        let search = try manifest(base(
            #", "providers": [{"id": "a.b", "capability": "library.search", "name": "B"}]"#, apiVersion: 5,
            capabilities: #"["library.search"]"#))
        #expect(throws: PluginError.self) { try search.validate() }
        let old = try manifest(base(
            #", "providers": [{"id": "a.b", "capability": "audio.beats", "name": "B"}]"#, apiVersion: 1,
            capabilities: #"["audio.beats"]"#))
        try old.validate()
        #expect(old.incompatibility == nil)
        // A provider written without kinds still decodes, and round-trips without them.
        let encoded = try JSONEncoder().encode(old)
        #expect(String(bytes: encoded, encoding: .utf8)?.contains("kinds") == false)
    }

    @Test("Pack items are listed in the plugin scope with paths under the plugin and the plugin as creator")
    func packItems() throws {
        let root = Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let plugin = try Self.plugin(in: root)
        let found = PluginLibrary.items(of: plugin)
        #expect(found.problems.isEmpty)
        #expect(found.items.map(\.id) == ["lofi-beat", "wave-hand"])
        let beat = try #require(found.items.first)
        #expect(beat.scope == .plugin && beat.file == "packs/music/files/beat.wav" && beat.pack == "Lo-fi")
        #expect(beat.createdBy["plugin"] == .string("example.sounds"))
        #expect(beat.createdBy["pluginName"] == .string("Example Sounds") && beat.creator == "plugin")

        let catalog = PluginLibrary.catalog([plugin])
        let library = LibraryCatalog(builtIn: [], plugin: catalog.items, pluginRoots: catalog.roots, user: nil, project: nil)
        let item = try library.item("plugin:lofi-beat")
        let file = try #require(library.fileURL(of: item))
        #expect(file.standardizedFileURL.path == plugin.directory.appendingPathComponent("packs/music/files/beat.wav").path)
        #expect(try library.panelItems([.audio]).map(\.reference) == ["plugin:lofi-beat"])
        #expect(try library.items(matching: LibraryCatalog.Filter(creator: "plugin")).count == 2)
    }

    @Test("A pack at the plugin's top level keeps its own paths")
    func rootPack() throws {
        let root = Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let plugin = try Self.plugin(in: root, packPath: ".")
        #expect(PluginLibrary.items(of: plugin).items.first?.file == "files/beat.wav")
    }

    @Test("Packs that reach outside the plugin are refused, with a problem plugins validate reports")
    func confinement() throws {
        let root = Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside.appendingPathComponent("secret.wav"))

        // An item path with `..`.
        let escaping = try Self.plugin(in: root, id: "example.escape", items: [
            #"{"id": "leak", "kind": "audio", "name": "Leak", "file": "../../../outside/secret.wav"}"#,
        ])
        #expect(PluginLibrary.items(of: escaping).items.isEmpty)
        #expect(PluginLibrary.items(of: escaping).problems.count == 1)

        // A file symlinked out of the pack.
        let linked = try Self.plugin(in: root, id: "example.linked", items: [
            #"{"id": "linked", "kind": "audio", "name": "Linked", "file": "files/link.wav"}"#,
        ])
        try FileManager.default.createSymbolicLink(
            at: linked.directory.appendingPathComponent("packs/music/files/link.wav"),
            withDestinationURL: outside.appendingPathComponent("secret.wav"))
        #expect(PluginLibrary.items(of: linked).items.isEmpty)

        // The pack folder itself symlinked out of the plugin.
        let directory = root.appendingPathComponent("example.folder", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let other = try Self.plugin(in: outside)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("pack"), withDestinationURL: other.directory.appendingPathComponent("packs/music"))
        let manifest = PluginManifest(
            id: "example.folder", name: LocalizedText(["en": "Folder"]), version: "1.0.0", apiVersion: 6,
            entrypoint: "bin/provider", capabilities: [],
            contributes: PluginContributions(library: [PluginLibraryContribution(path: "pack")]))
        let folder = InstalledPlugin(manifest: manifest, directory: directory)
        #expect(PluginLibrary.items(of: folder).problems.first?.contains("outside the plugin") == true)

        // `plugins validate` lists the pack problem with the manifest's own.
        let report = PluginLocalSource.validate(escaping.directory)
        #expect(report.problems.contains { $0.contains("contributes.library") && $0.contains("leak") })
    }

    @Test("Plugin items cannot take a built-in ID or another plugin's")
    func reservedIDs() throws {
        let root = Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try Self.plugin(in: root, id: "example.first")
        let second = try Self.plugin(in: root, id: "example.second", items: [
            #"{"id": "fire", "kind": "sticker", "name": "Not fire", "params": {"emoji": "🧯"}}"#,
            #"{"id": "wave-hand", "kind": "sticker", "name": "Wave again", "params": {"emoji": "🖐"}}"#,
            #"{"id": "own", "kind": "sticker", "name": "Own", "params": {"emoji": "⭐"}}"#,
        ])
        let catalog = PluginLibrary.catalog([first, second])
        #expect(catalog.items.map(\.id) == ["lofi-beat", "wave-hand", "own"])
        #expect(catalog.problems.count == 2)
        #expect(Set(catalog.roots.keys) == ["example.first", "example.second"])
    }

    @Test("Plugin items are read-only, copy into a writable scope, and placing copies their file into the project")
    func readOnlyAndPlacedCopies() throws {
        let root = Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project", isDirectory: true)
        // A plugin installed in the project itself (`.bashcut/plugins`): its files are still copied out of it.
        let plugin = try Self.plugin(in: project.appendingPathComponent(".bashcut/plugins", isDirectory: true))
        let catalog = PluginLibrary.catalog([plugin])
        let library = LibraryCatalog(
            builtIn: [], plugin: catalog.items, pluginRoots: catalog.roots,
            user: .user(applicationSupport: root.appendingPathComponent("support")), project: .project(root: project))
        let item = try library.item("lofi-beat")
        #expect(item.scope == .plugin)
        #expect(throws: ProjectError.self) { try library.store(.plugin) }
        #expect(throws: ProjectError.self) { try library.move(item, to: .project) }

        // library update --as: an editable copy with the file.
        let copy = try library.copy(
            item, as: "my-beat", into: .project, changes: ["name": .string("My beat")],
            createdBy: LibraryItem.creator(author: .user))
        #expect(copy.scope == .project && copy["basedOn"] == .string("plugin:lofi-beat@v1"))
        #expect(library.fileURL(of: copy).map { FileManager.default.fileExists(atPath: $0.path) } == true)

        // library place: the file is copied into the project by content, not used where the plugin keeps it.
        let source = try #require(library.fileURL(of: item))
        let placed = try LibraryAudio.projectCopy(of: source, root: project, folder: "music")
        #expect(placed.path.hasPrefix(project.appendingPathComponent("music").path))
        #expect(placed.lastPathComponent.hasPrefix("library-"))

        // Removing the plugin removes its items; the placed copy and the saved copy stay.
        try FileManager.default.removeItem(at: plugin.directory)
        let after = LibraryCatalog(
            builtIn: [], plugin: PluginLibrary.catalog([]).items,
            user: .user(applicationSupport: root.appendingPathComponent("support")), project: .project(root: project))
        #expect(throws: ProjectError.self) { try after.item("plugin:lofi-beat") }
        #expect(FileManager.default.fileExists(atPath: placed.path))
        #expect(try after.item("my-beat").scope == .project)
    }

    @Test("The example library plugin in Fixtures validates and lists its Party pack")
    func fixture() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../Fixtures/plugins/example.library").standardizedFileURL
        let report = PluginLocalSource.validate(folder)
        #expect(report.problems.isEmpty)
        let manifest = try #require(report.manifest)
        let found = PluginLibrary.items(of: InstalledPlugin(manifest: manifest, directory: folder))
        #expect(found.problems.isEmpty)
        #expect(found.items.count == 5 && found.items.allSatisfy { $0.pack == "Party" })
        #expect(Set(found.items.compactMap(\.kind)) == [.sticker, .textPreset, .look, .transitionPreset])
    }
}
