import Foundation
import Testing

@testable import BashCutProject

@Suite("All assets search (P2-B1)")
struct AssetSearchTests {
    private static func sound(_ id: String, _ name: String, pack: String?, scope: LibraryScope, tags: [String] = []) -> LibraryItem {
        LibraryItem(id: id, kind: .audio, name: name, tags: tags, pack: pack, params: ["role": .string("sfx")], scope: scope)
    }

    private static func media(_ id: String, _ path: String, kind: String = "video") -> Media {
        Media(fields: ["id": .string(id), "path": .string(path), "kind": .string(kind)])
    }

    private static let library: [LibraryItem] = [
        sound("whoosh-1", "Whoosh fast", pack: "Mixkit SFX", scope: .plugin),
        sound("air", "Air swish", pack: "Freesound", scope: .user, tags: ["whoosh", "transition"]),
        sound("whoosh-2", "Big whoosh", pack: "Pixabay SFX", scope: .project),
        LibraryItem(id: "fire", kind: .sticker, name: "Fire", params: ["emoji": .string("🔥")]),
        LibraryItem(id: "whip", kind: .transitionPreset, name: "Whip pan whoosh", pack: "Motion"),
    ]

    @Test("Whoosh finds the SFX of every pack and the matching media in one list, grouped by kind")
    func whooshAcrossPacksAndMedia() {
        let media = [Self.media("m1", "media/whoosh-take.mov"), Self.media("m2", "media/interview.mov")]
        let sections = AssetSearch.search("whoosh", library: Self.library, media: media, selects: [])
        #expect(sections.map(\.group) == [.media, .library(.audio), .library(.transitionPreset)])
        #expect(sections[0].results.map(\.id) == ["media:m1"])
        let packs = Set(sections[1].results.compactMap { result -> String? in
            if case .library(let item) = result.asset { return item.pack }
            return nil
        })
        #expect(packs == ["Mixkit SFX", "Freesound", "Pixabay SFX"])
    }

    @Test("A name that starts with the query ranks first; a match only in tags ranks last; ties keep their order")
    func ranking() {
        let sections = AssetSearch.search("whoosh", library: Self.library, media: [], selects: [])
        #expect(sections[0].results.map(\.id) == ["library:plugin:whoosh-1", "library:project:whoosh-2", "library:user:air"])
        #expect(sections[0].results.map(\.score) == [3, 2, 0])
    }

    @Test("Every word must match, in any field, ignoring case and Vietnamese diacritics")
    func wordsAndDiacritics() {
        let items = [
            LibraryItem(id: "a", kind: .textPreset, name: "Tiêu đề lớn", pack: "Tin tức"),
            LibraryItem(id: "b", kind: .textPreset, name: "Phụ đề"),
        ]
        #expect(AssetSearch.search("TIEU DE", library: items, media: [], selects: []).first?.results.map(\.id) == ["library:built-in:a"])
        #expect(AssetSearch.search("de tin", library: items, media: [], selects: []).first?.results.map(\.id) == ["library:built-in:a"])
        #expect(AssetSearch.search("de", library: items, media: [], selects: []).first?.total == 2)
        #expect(AssetSearch.search("  ", library: items, media: [], selects: []).isEmpty)
    }

    @Test("An id saved in several scopes is listed once, from the first (the scope in use)")
    func oneEntryPerItem() {
        let items = [
            Self.sound("swoosh", "Swoosh", pack: nil, scope: .project),
            Self.sound("swoosh", "Swoosh", pack: nil, scope: .user),
            LibraryItem(id: "swoosh", kind: .sticker, name: "Swoosh arrow"),
        ]
        let sections = AssetSearch.search("swoosh", library: items, media: [], selects: [])
        #expect(sections.map(\.group) == [.library(.audio), .library(.sticker)])
        #expect(sections[0].results.map(\.id) == ["library:project:swoosh"])
    }

    @Test("Selects match by quote, reason or their media's name; a section lists up to the limit and counts the rest")
    func selectsAndLimit() {
        let media = [Self.media("m1", "media/cafe.mov")]
        let select = ProjectSelect(fields: [
            "id": .string("s1"), "media": .string("m1"), "from": .number(1), "to": .number(3),
            "quote": .string("The best coffee in town"),
        ])
        #expect(AssetSearch.search("coffee", library: [], media: media, selects: [select]).map(\.group) == [.selects])
        #expect(AssetSearch.search("cafe", library: [], media: media, selects: [select]).map(\.group) == [.media, .selects])
        let many = (0..<5).map { Self.sound("s\($0)", "Click \($0)", pack: nil, scope: .user) }
        let section = AssetSearch.search("click", library: many, media: [], selects: [], limit: 3)[0]
        #expect(section.results.count == 3)
        #expect(section.total == 5)
        #expect(AssetSearch.flattened([section]).count == 3)
    }
}
