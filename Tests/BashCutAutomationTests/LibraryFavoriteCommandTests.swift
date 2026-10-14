import BashCutProject
import Foundation
import Testing

@testable import BashCutAutomation

struct LibraryFavoriteCommandTests {
    @Test("library favorite takes an ID or scope:id, one scope, and --off")
    func favoriteParses() throws {
        let star = try CommandLineParser.parse(["library", "favorite", "user:fire"])
        #expect(star.spec.name == "library.favorite")
        #expect(star.spec.mode == .edit)
        #expect(star.params == ["id": .string("user:fire")])
        let unstar = try CommandLineParser.parse(["library", "favorite", "fire", "--scope", "built-in", "--off"])
        #expect(unstar.params == ["id": .string("fire"), "scope": .string("built-in"), "off": .bool(true)])
        #expect(throws: CommandLineParser.Failure.self) { try CommandLineParser.parse(["library", "favorite"]) }
        #expect(throws: CommandLineParser.Failure.self) {
            try CommandLineParser.parse(["library", "favorite", "fire", "--scope", "nowhere"])
        }
    }

    @Test("library list filters to favorites or recent, and ui view sets the source chip and the list")
    func listAndViewParse() throws {
        let starred = try CommandLineParser.parse(["library", "list", "--favorites", "--panel", "stickers"])
        #expect(starred.spec.mode == .read)
        #expect(starred.params == ["favorites": .bool(true), "panel": .string("stickers")])
        #expect(try CommandLineParser.parse(["library", "list", "--recent"]).params == ["recent": .bool(true)])
        let view = try CommandLineParser.parse(["ui", "view", "--library-source", "mine", "--library-collection", "recent"])
        #expect(view.params == ["librarySource": .string("mine"), "libraryCollection": .string("recent")])
        #expect(throws: CommandLineParser.Failure.self) { try CommandLineParser.parse(["ui", "view", "--library-source", "online"]) }
        #expect(throws: CommandLineParser.Failure.self) {
            try CommandLineParser.parse(["ui", "view", "--library-collection", "everything"])
        }
    }

    @MainActor @Test("Chat agents may star items")
    func agentsMayFavorite() {
        #expect(ChatCommandSession.allowedMethods.contains("library.favorite"))
    }
}
