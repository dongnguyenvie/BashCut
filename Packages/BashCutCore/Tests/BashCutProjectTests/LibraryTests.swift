import Foundation
import Testing

@testable import BashCutProject

@Suite("Library items, scopes and packs")
struct LibraryTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("library-tests-\(UUID().uuidString)", isDirectory: true)

    private func catalog(builtIn: [LibraryItem] = []) -> LibraryCatalog {
        LibraryCatalog(
            builtIn: builtIn, user: .user(applicationSupport: folder.appendingPathComponent("support")),
            project: .project(root: folder.appendingPathComponent("project")))
    }

    private func file(_ name: String, _ text: String) throws -> URL {
        let url = folder.appendingPathComponent("sources/\(name)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private static let fire = LibraryItem(
        id: "fire", kind: .sticker, name: "Fire", tags: ["hot"], pack: "Food", params: ["emoji": .string("🔥")])

    @Test("Each kind checks what it needs to be applied or placed")
    func validation() throws {
        try Self.fire.validate()
        let bad: [(LibraryItem, String)] = [
            (LibraryItem(id: "Bad ID", kind: .sticker, name: "x", params: ["emoji": .string("x")]), "lowercase"),
            (LibraryItem(id: "s", kind: .sticker, name: "Sticker"), "params.emoji"),
            (LibraryItem(id: "t", kind: .textPreset, name: "T", params: ["textPreset": .string("")]), "textPreset"),
            (LibraryItem(id: "e", kind: .effectPreset, name: "E"), "params.patch"),
            (LibraryItem(id: "a", kind: .audio, name: "A"), "file"),
            (LibraryItem(id: "l", kind: .look, name: "L", params: ["color": .object(["contrast": .integer(9)])]), "contrast"),
            (LibraryItem(id: "x", kind: .sticker, name: " ", params: ["emoji": .string("x")]), "name"),
        ]
        for (item, message) in bad {
            #expect(throws: ProjectError.self) { try item.validate() }
            #expect((try? item.validate()) == nil)
            do { try item.validate() } catch { #expect(error.localizedDescription.contains(message)) }
        }
        var escaping = Self.fire
        escaping["file"] = .string("../secret.png")
        #expect(throws: ProjectError.self) { try escaping.validate() }
        #expect(LibraryKind.textPreset.panel == "text")
        #expect(LibraryKind.kinds(inPanel: "stickers") == [.sticker])
    }

    @Test("A clip (P2-H5) needs a movie or image file, keeps any params and lists in the Media panel")
    func clipItems() throws {
        let noFile = LibraryItem(id: "c", kind: .clip, name: "Clip")
        do { try noFile.validate() } catch { #expect(error.localizedDescription.contains("needs a file")) }
        #expect((try? noFile.validate()) == nil)
        var wrong = noFile
        wrong["file"] = .string("files/clip.wav")
        do { try wrong.validate() } catch { #expect(error.localizedDescription.contains("movie")) }
        #expect((try? wrong.validate()) == nil)
        var clip = LibraryItem(
            id: "drone", kind: .clip, name: "Drone shot",
            params: ["model": .string("any-model"), "aspect": .string("9:16"), "seconds": .number(5)])
        clip["file"] = .string("files/drone.mp4")
        try clip.validate()
        var still = clip
        still["file"] = .string("files/still.png")
        try still.validate()
        #expect(LibraryClip.isImage("files/still.png") && !LibraryClip.isImage("files/drone.mp4"))
        #expect(LibraryKind.kinds(inPanel: "media") == [.clip])
        #expect(clip.json().object["panel"] == .string("media"))
    }

    @Test("Stores add, version, copy and remove items; built-in items stay read-only")
    func storeChanges() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let builtIn = LibraryItem(
            id: "bold", kind: .textPreset, name: "Bold", params: ["textPreset": .string("bold-outline")])
        let catalog = catalog(builtIn: [builtIn])
        var fire = Self.fire
        fire["createdBy"] = LibraryItem.creator(author: .claude, session: "s1")
        let added = try catalog.add(fire, into: .project, file: try file("fire.png", "v1"))
        #expect(added.file == "files/fire/v1/fire.png")
        #expect(added.createdBy["agent"] == .string("claude"))
        #expect(throws: ProjectError.self) { try catalog.add(fire, into: .project) }
        #expect(throws: ProjectError.self) { try catalog.add(builtIn, into: .user) }
        #expect(throws: ProjectError.self) { try catalog.store(.builtIn) }

        let updated = try catalog.store(.project).update(
            "fire", changes: ["name": .string("Fire!"), "version": .integer(99)], file: try file("fire.png", "v2"))
        #expect(updated.version == 2)
        #expect(updated.history.count == 1)
        #expect(updated.history[0].object["name"] == .string("Fire"))
        #expect(updated.file == "files/fire/v2/fire.png")
        let root = catalog.project!.root
        #expect(try String(contentsOf: root.appendingPathComponent("files/fire/v1/fire.png"), encoding: .utf8) == "v1")

        // The same id in two scopes: the project wins, `scope:id` picks one.
        try catalog.add(Self.fire, into: .user)
        #expect(try catalog.item("fire").scope == .project)
        #expect(try catalog.item("user:fire").scope == .user)
        #expect(try catalog.items(matching: .init(scope: .user)).map(\.id) == ["fire"])
        #expect(try catalog.items(matching: .init(kinds: [.textPreset])).map(\.id) == ["bold"])
        #expect(try catalog.items(matching: .init(tag: "HOT", creator: "agent")).map(\.reference) == ["project:fire"])

        let copy = try catalog.copy(
            builtIn, as: "bold-yellow", into: .user, changes: ["name": .string("Bold yellow")],
            createdBy: LibraryItem.creator(author: .user))
        #expect(copy.fields["basedOn"] == .string("built-in:bold@v1"))
        #expect(copy.version == 1)
        let fileCopy = try catalog.copy(
            updated, as: "fire-2", into: .user, changes: [:], createdBy: LibraryItem.creator(author: .user))
        #expect(fileCopy.file == "files/fire-2/v1/fire.png")

        let removed = try catalog.store(.project).remove("fire")
        #expect(removed.scope == .project)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("files/fire").path))
        #expect(try catalog.item("fire").scope == .user)
    }

    @Test("Moving an item keeps its versions, files and use count; read-only items do not move")
    func move() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let builtIn = LibraryItem(
            id: "bold", kind: .textPreset, name: "Bold", params: ["textPreset": .string("bold-outline")])
        let catalog = catalog(builtIn: [builtIn])
        try catalog.add(Self.fire, into: .project, file: try file("fire.png", "v1"))
        let updated = try catalog.store(.project).update("fire", changes: ["name": .string("Fire!")])
        try catalog.recordUse(updated)

        let moved = try catalog.move(updated, to: .user)
        #expect(moved.scope == .user)
        #expect(moved.version == 2 && moved.history.count == 1)
        #expect(moved["createdAt"] == updated["createdAt"])
        let userRoot = catalog.user!.root
        #expect(try String(contentsOf: userRoot.appendingPathComponent("files/fire/v1/fire.png"), encoding: .utf8) == "v1")
        #expect(try catalog.project!.items().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: catalog.project!.root.appendingPathComponent("files/fire").path))
        #expect(try catalog.user!.usage()["user:fire"]?.count == 1)
        #expect(try catalog.project!.usage().isEmpty)

        #expect(throws: ProjectError.self) { try catalog.move(moved, to: .user) }
        #expect(throws: ProjectError.self) { try catalog.move(try catalog.item("bold"), to: .user) }
        // The destination already has the id: nothing changes.
        try catalog.add(Self.fire, into: .project)
        #expect(throws: ProjectError.self) { try catalog.move(moved, to: .project) }
        #expect(try catalog.user!.items().map(\.id) == ["fire"])
    }

    @Test("Save selection as… takes a text style, framing, the clip's transition or a grade without its LUT")
    func selection() throws {
        var text = Item(at: 0, duration: 30)
        text["text"] = .string("Hello")
        text["textPreset"] = .string("hook-title")
        #expect(try LibrarySelection.params(.textPreset, item: text) == [
            "textPreset": .string("hook-title"), "text": .string("Hello"),
        ])
        var clip = Item(at: 0, duration: 30)
        #expect(throws: ProjectError.self) { try LibrarySelection.params(.effectPreset, item: clip) }
        #expect(throws: ProjectError.self) { try LibrarySelection.params(.textPreset, item: clip) }
        #expect(throws: ProjectError.self) { try LibrarySelection.params(.look, item: clip) }
        clip["transform"] = .object(["zoom": .number(1.3)])
        clip["color"] = .object(["contrast": .number(1.1), "lut": .string("lut-1"), "lutStrength": .number(0.5)])
        let effect = try LibrarySelection.params(.effectPreset, item: clip)
        #expect(effect == ["steps": .array([.object([
            "op": .string("patch"), "patch": .object(["transform": .object(["zoom": .number(1.3)])]),
        ])])])
        #expect(try LibrarySelection.params(.look, item: clip) == ["color": .object(["contrast": .number(1.1)])])
        #expect(throws: ProjectError.self) { try LibrarySelection.params(.transitionPreset, item: clip) }
        let transition = TimelineTransition(kind: "whip", from: "a", to: "b", duration: 9)
        let preset = try LibrarySelection.params(.transitionPreset, item: clip, transition: transition)
        #expect(preset == ["kind": .string("whip"), "duration": .integer(9)])
        // Audio needs its file (LibraryAudioTests); an image sticker its media (LibraryStickerTests).
        for kind in LibrarySelection.kinds where kind != .audio {
            let params = kind == .transitionPreset
                ? preset : try LibrarySelection.params(kind, item: [.textPreset, .sticker].contains(kind) ? text : clip)
            try LibraryItem(id: "x", kind: kind, name: "X", params: params).validate()
        }
        #expect(throws: ProjectError.self) { try LibrarySelection.params(.sticker, item: clip) }
        #expect(throws: ProjectError.self) { try LibrarySelection.params(.voice, item: text) }
    }

    @Test("Usage goes to the project for its items and to this Mac for the rest; stats find unused and duplicates")
    func usageAndStats() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalog = catalog()
        let project = try catalog.add(Self.fire, into: .project)
        var twin = Self.fire
        twin["id"] = .string("flame")
        let user = try catalog.add(twin, into: .user)
        try catalog.recordUse(project)
        try catalog.recordUse(project)
        #expect(try catalog.project!.usage()["project:fire"]?.count == 2)
        #expect(try catalog.user!.usage().isEmpty)
        let stats = try catalog.stats().object
        #expect(stats["unused"] == .array([.string(user.reference)]))
        #expect(stats["duplicates"] == .array([.array([.string("project:fire"), .string("user:flame")])]))
        try catalog.store(.project).remove("fire")
        #expect(try catalog.project!.usage().isEmpty)
    }

    @Test("Counting a use writes only usage.json; counts older versions kept in library.json move there")
    func usageFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try catalog().store(.user)
        try store.add(Self.fire)
        let items = try Data(contentsOf: store.file)
        try store.recordUse("user:fire")
        try store.recordUse("plugin:x")
        #expect(try Data(contentsOf: store.file) == items)
        #expect(try store.usage()["user:fire"]?.count == 1)
        #expect(try store.usage()["plugin:x"]?.count == 1)

        // A library an older version wrote: usage inside library.json, no usage.json.
        try FileManager.default.removeItem(at: store.usageFile)
        var old = try store.load()
        old.usage = ["user:fire": LibraryUsage(count: 3, lastUsed: "2026-01-01T00:00:00Z")]
        try JSONEncoder().encode(JSONValue.object(old.fields)).write(to: store.file)
        #expect(try store.usage()["user:fire"]?.count == 3)
        try store.update("fire", changes: ["name": .string("Fire!")])
        #expect(try store.load().fields["usage"] == nil)
        #expect(try store.usage()["user:fire"]?.count == 3)
        try store.recordUse("user:fire")
        #expect(try store.usage()["user:fire"]?.count == 4)
        try store.remove("fire")
        #expect(try store.usage()["user:fire"] == nil)
    }

    @Test("A stored file's SHA-256 is saved when it is copied in and stats use it")
    func fileHash() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalog = catalog()
        let audio = LibraryItem(id: "whoosh", kind: .audio, name: "Whoosh")
        let source = try file("whoosh.wav", "audio")
        let added = try catalog.add(audio, into: .user, file: source)
        let digest = try #require(added["fileSHA256"]?.string)
        #expect(digest == (try LibraryStore.sha256(of: source)))
        #expect(digest.count == 64)
        // Changes cannot write it; a new file replaces it.
        let renamed = try catalog.store(.user).update("whoosh", changes: ["fileSHA256": .string("x")])
        #expect(renamed["fileSHA256"]?.string == digest)
        let replaced = try catalog.store(.user).update("whoosh", changes: [:], file: try file("other.wav", "other"))
        #expect(replaced["fileSHA256"]?.string != digest)
        // A copy hashes its own copied file.
        let copy = try catalog.copy(replaced, as: "whoosh-2", into: .project, changes: [:], createdBy: .null)
        #expect(copy["fileSHA256"] == replaced["fileSHA256"])
        // Stats trust the stored hash instead of reading the file again.
        try Data("changed".utf8).write(to: try #require(catalog.fileURL(of: copy)))
        let stats = try catalog.stats().object
        #expect(stats["duplicates"] == .array([.array([.string("project:whoosh-2"), .string("user:whoosh")])]))
    }

    @Test("Packs export with their files and import into another scope")
    func packs() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalog = catalog()
        let audio = LibraryItem(id: "whoosh", kind: .audio, name: "Whoosh", tags: ["sfx"], pack: "Transitions")
        try catalog.add(audio, into: .user, file: try file("whoosh.wav", "audio"))
        try catalog.add(Self.fire, into: .user)
        let out = folder.appendingPathComponent("out/Pack")
        try LibraryPack.export(try catalog.user!.items(), name: "Mine", catalog: catalog, to: out)
        #expect(throws: ProjectError.self) {
            try LibraryPack.export(try catalog.user!.items(), name: "Mine", catalog: catalog, to: out)
        }

        let pack = try LibraryPack.read(out)
        #expect(pack.name == "Mine")
        #expect(pack.items.map(\.file) == ["files/whoosh/whoosh.wav", nil])
        let imported = try LibraryPack.importItems(
            pack, into: .project, catalog: catalog, replace: false, createdBy: LibraryItem.creator(author: .user))
        #expect(imported.map(\.reference) == ["project:whoosh", "project:fire"])
        #expect(imported[0].fields["importedFrom"] == .string("Mine"))
        #expect(FileManager.default.fileExists(atPath: catalog.project!.url(of: imported[0].file!).path))
        #expect(throws: ProjectError.self) {
            try LibraryPack.importItems(
                pack, into: .project, catalog: catalog, replace: false, createdBy: LibraryItem.creator(author: .user))
        }
        let again = try LibraryPack.importItems(
            pack, into: .project, catalog: catalog, replace: true, createdBy: LibraryItem.creator(author: .user))
        #expect(again.map(\.version) == [2, 2])

        // A file outside the pack is refused.
        var manifest = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: out.appendingPathComponent("pack.json")))
        var items = manifest.object["items"]!.array
        var first = items[0].object
        first["file"] = .string("link.wav")
        items[0] = .object(first)
        manifest = .object(manifest.object.merging(["items": .array(items)]) { $1 })
        try FileManager.default.createSymbolicLink(
            at: out.appendingPathComponent("link.wav"), withDestinationURL: try file("outside.wav", "x"))
        try JSONEncoder().encode(manifest).write(to: out.appendingPathComponent("pack.json"))
        #expect(throws: ProjectError.self) { try LibraryPack.read(out) }
    }

    @Test("Zipped packs unpack from their root or one top folder")
    func zippedPack() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalog = catalog()
        try catalog.add(Self.fire, into: .user)
        let out = folder.appendingPathComponent("zip/Food")
        try LibraryPack.export(try catalog.user!.items(), name: "Food", catalog: catalog, to: out)
        let zip = folder.appendingPathComponent("Food.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", out.path, zip.path]
        try process.run()
        process.waitUntilExit()
        let unpacked = try LibraryPack.folder(at: zip, scratch: folder.appendingPathComponent("scratch"))
        #expect(try LibraryPack.read(unpacked).items.map(\.id) == ["fire"])
        #expect(throws: ProjectError.self) {
            try LibraryPack.folder(at: try file("notes.txt", "x"), scratch: folder.appendingPathComponent("scratch2"))
        }
    }

    @Test("Built-in packs hold the panels' former hard-coded items, valid and in their order")
    func builtInPacks() throws {
        let items = LibraryBuiltIns.items
        for item in items { try item.validate() }
        #expect(Set(items.map(\.id)).count == items.count)
        // One text preset per caption renderer preset, in the panel's order.
        #expect(LibraryBuiltIns.textPresets.map(\.id) == TextPreset.all)
        #expect(LibraryBuiltIns.textPresets.map { $0.params["textPreset"]?.string } == TextPreset.all)
        #expect(LibraryBuiltIns.textPresets[0].params["text"] == .string("Quá là ngon!"))
        #expect(LibraryBuiltIns.stickers.compactMap { $0.params["emoji"]?.string } == ["🔥", "😋", "👍", "💯", "⭐", "📍", "🍲", "😂"])
        #expect(LibraryBuiltIns.effects.map(\.name).prefix(2) == ["Punch in 1.3×", "Reset framing"])
        #expect(LibraryBuiltIns.effects[0].params["patch"] == .object(["transform": .object(["zoom": .number(1.3)])]))
        #expect(LibraryBuiltIns.transitions.map(\.id) == ["soft-dissolve", "quick-whip", "zoom-punch"])
        #expect(LibraryBuiltIns.looks.map(\.id) == ["original", "vivid", "muted-film", "black-white", "bright-airy", "moody"])
        #expect(Set(items.compactMap(\.kind)) == [.textPreset, .sticker, .effectPreset, .transitionPreset, .look])
    }

    @Test("Panels list built-in items first, then saved ones, each ID once")
    func panelItems() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalog = LibraryCatalog(
            user: .user(applicationSupport: folder.appendingPathComponent("support")),
            project: .project(root: folder.appendingPathComponent("project")))
        #expect(throws: ProjectError.self) { try catalog.add(Self.fire, into: .project) }
        var mine = Self.fire
        mine["id"] = .string("my-fire")
        try catalog.add(mine, into: .project)
        try catalog.add(mine, into: .user)
        let stickers = try catalog.panelItems([.sticker])
        #expect(stickers.prefix(8).map(\.scope) == Array(repeating: .builtIn, count: 8))
        #expect(stickers.dropFirst(8).map(\.reference) == ["project:my-fire"])
        #expect(try catalog.panelItems([.effectPreset]).map(\.id) == LibraryBuiltIns.effects.map(\.id))
        #expect(try catalog.item("fire").scope == .builtIn)
    }

    @Test("Unknown fields round-trip through the store")
    func unknownFields() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore.user(applicationSupport: folder)
        var item = Self.fire
        item["future"] = .object(["a": .integer(1)])
        try store.add(item)
        var contents = try store.load()
        contents.fields["futureTop"] = .bool(true)
        try store.save(contents)
        try store.update("fire", changes: ["tags": .array([.string("spicy")])])
        let reloaded = try store.load()
        #expect(reloaded.fields["futureTop"] == .bool(true))
        #expect(reloaded.items[0]["future"] == .object(["a": .integer(1)]))
        #expect(reloaded.items[0].tags == ["spicy"])
    }
}
