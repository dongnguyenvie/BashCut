import Foundation
import Testing

@testable import BashCutProject

@Suite("Library favourites and recent items")
struct LibraryFavoritesTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("library-favorites-\(UUID().uuidString)", isDirectory: true)

    private func catalog(project name: String = "project") -> LibraryCatalog {
        LibraryCatalog(
            builtIn: [], user: .user(applicationSupport: folder.appendingPathComponent("support")),
            project: .project(root: folder.appendingPathComponent(name)))
    }

    private static func sticker(_ id: String) -> LibraryItem {
        LibraryItem(id: id, kind: .sticker, name: id, params: ["emoji": .string("🔥")])
    }

    @Test("Favourites are global: they follow the user library, not the project, and starring twice keeps one")
    func favoritesAreGlobal() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = catalog(project: "one")
        let item = try first.add(Self.sticker("fire"), into: .user)
        try first.setFavorite(item, true)
        try first.setFavorite(item, true)
        #expect(try first.favorites() == ["user:fire"])
        // Another project, same Mac.
        #expect(try catalog(project: "two").favorites() == ["user:fire"])
        try first.setFavorite(item, false)
        #expect(try catalog(project: "two").favorites().isEmpty)
    }

    @Test("Read-only items can be favourites; removing a saved item drops it from the list")
    func favoritesOfAnyScope() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalog = catalog()
        let builtIn = LibraryItem(fields: Self.sticker("star").fields, scope: .builtIn)
        let saved = try catalog.add(Self.sticker("fire"), into: .user)
        try catalog.setFavorite(builtIn, true)
        try catalog.setFavorite(saved, true)
        #expect(try catalog.favorites() == ["built-in:star", "user:fire"])
        try catalog.store(.user).remove("fire")
        #expect(try catalog.favorites() == ["built-in:star"])
    }

    @Test("Favourites keep fields they do not know and never touch library.json or usage.json")
    func favoritesFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalog = catalog()
        let item = try catalog.add(Self.sticker("fire"), into: .user)
        let store = try catalog.store(.user)
        let items = try Data(contentsOf: store.file)
        try Data(#"{"format":1,"favorites":["user:a"],"future":{"sort":"name"}}"#.utf8).write(to: store.favoritesFile)
        try catalog.setFavorite(item, true)
        #expect(try Data(contentsOf: store.file) == items)
        #expect(!FileManager.default.fileExists(atPath: store.usageFile.path))
        let saved = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: store.favoritesFile))
        #expect(saved.object["future"] == .object(["sort": .string("name")]))
        #expect(try store.favorites() == ["user:a", "user:fire"])
    }

    @Test("Recent is per project: newest first, no repeats, at most 20, and another project starts empty")
    func recentIsPerProject() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = catalog(project: "one")
        var items: [LibraryItem] = []
        for index in 0..<25 { items.append(try one.add(Self.sticker("s\(index)"), into: .user)) }
        for item in items { try one.recordUse(item) }
        try one.recordUse(items[10])
        let recent = try one.recent()
        #expect(recent.count == LibraryStore.maximumRecent)
        #expect(recent.first == "user:s10")
        #expect(Set(recent).count == recent.count)
        #expect(recent[1] == "user:s24")
        // Global counts stay: the user library counts the use.
        #expect(try one.user!.usage()["user:s10"]?.count == 2)
        #expect(try catalog(project: "two").recent().isEmpty)
    }

    @Test("Without a saved project nothing is recorded and Recent is empty")
    func recentNeedsProject() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let loose = LibraryCatalog(builtIn: [], user: .user(applicationSupport: folder.appendingPathComponent("support")), project: nil)
        let item = try loose.add(Self.sticker("fire"), into: .user)
        try loose.recordUse(item)
        #expect(try loose.recent().isEmpty)
        #expect(try loose.user!.usage()["user:fire"]?.count == 1)
    }

    @Test("Moving an item between scopes keeps it a favourite and recent")
    func moveKeepsFavorite() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalog = catalog()
        let item = try catalog.add(Self.sticker("fire"), into: .project)
        try catalog.setFavorite(item, true)
        try catalog.recordUse(item)
        let moved = try catalog.move(item, to: .user)
        #expect(try catalog.favorites() == ["user:fire"])
        #expect(try catalog.recent() == ["user:fire"])
        _ = moved
    }

    @Test("The home view lists Recent, then Favorites, then packs with saved items first; unknown references are skipped")
    func homeSections() {
        func item(_ id: String, pack: String? = nil, scope: LibraryScope = .builtIn) -> LibraryItem {
            LibraryItem(fields: LibraryItem(id: id, kind: .sticker, name: id, pack: pack, params: ["emoji": .string("x")]).fields, scope: scope)
        }
        let items = [
            item("a", pack: "Food"), item("b", pack: "food"), item("c", pack: "Travel"), item("d"),
            item("mine", scope: .user), item("p", pack: "Mine pack", scope: .project),
        ]
        let sections = LibraryHome.sections(
            items: items, favorites: ["built-in:a", "built-in:c", "built-in:gone"], recent: ["user:mine", "built-in:b", "other:x"])
        #expect(sections.map(\.id) == [
            "recent", "favorites", "scope:user", "pack:mine pack", "pack:food", "pack:travel", "scope:built-in",
        ])
        #expect(sections[0].items.map(\.id) == ["mine", "b"])
        // The newest star first.
        #expect(sections[1].items.map(\.id) == ["c", "a"])
        // Packs merge without case; their items keep the order they came in.
        #expect(sections[4].items.map(\.id) == ["a", "b"])
        #expect(LibraryHome.sections(items: [], favorites: ["user:x"], recent: ["user:x"]).isEmpty)
        #expect(LibrarySource.mine.contains(.project) && LibrarySource.mine.contains(.user))
        #expect(LibrarySource.packs.contains(.plugin) && LibrarySource.packs.contains(.builtIn))
        #expect(!LibrarySource.packs.contains(.user))
    }
}
