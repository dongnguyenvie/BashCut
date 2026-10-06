import BashCutProject
import Testing

@testable import BashCutAutomation

/// The library commands on the CLI and MCP.
struct LibraryCommandTests {
    @Test("library apply takes effect preset overrides and a from/to range on the CLI and over MCP")
    func libraryApplyEffect() throws {
        let apply = try CommandLineParser.parse([
            "library", "apply", "zoom-punch-in", "--item", "c1", "--set", "zoom=1.5,frames=12", "--from", "10", "--to", "40",
            "--base-rev", "3",
        ])
        #expect(apply.params == [
            "id": .string("zoom-punch-in"), "item": .string("c1"), "set": .string("zoom=1.5,frames=12"),
            "from": .integer(10), "to": .integer(40), "baseRev": .integer(3),
        ])
        let properties = try #require(CommandCatalog.spec(named: "library.apply")).inputSchema.object["properties"]?.object
        #expect(properties?["set"] != nil && properties?["from"] != nil && properties?["to"] != nil)
    }

    @Test("Audio library commands (#78): analyze, preview, place with a length and save-selection from media")
    @MainActor func audioLibraryCommands() throws {
        let analyze = try CommandLineParser.parse(["library", "analyze", "user:bed", "--provider", "ebur128"])
        #expect(analyze.spec.name == "library.analyze")
        #expect(analyze.params == ["id": .string("user:bed"), "provider": .string("ebur128")])
        let analyzeSpec = try #require(CommandCatalog.spec(named: "library.analyze"))
        #expect(analyzeSpec.execution == .job)
        #expect(analyzeSpec.inputSchema.object["required"] == .array([.string("id")]))

        let play = try CommandLineParser.parse(["library", "preview", "bed"])
        #expect(play.params["id"] == .string("bed"))
        let stop = try CommandLineParser.parse(["library", "preview", "--stop"])
        #expect(stop.params["stop"] == .bool(true) && stop.params["id"] == nil)

        let place = try CommandLineParser.parse([
            "library", "place", "bed", "--at-frame", "30", "--duration", "900", "--track", "a3", "--base-rev", "4",
        ])
        #expect(place.params == [
            "id": .string("bed"), "atFrame": .integer(30), "duration": .integer(900), "track": .string("a3"),
            "baseRev": .integer(4),
        ])

        let save = try CommandLineParser.parse([
            "library", "save-selection", "--kind", "audio", "--name", "Bed", "--media", "m1", "--tags", "calm,lofi",
        ])
        #expect(save.params["kind"] == .string("audio") && save.params["media"] == .string("m1"))
        let saveSpec = try #require(CommandCatalog.spec(named: "library.save-selection"))
        let saveProperties = saveSpec.inputSchema.object["properties"]?.object
        #expect(saveProperties?["media"] != nil)
        #expect(saveProperties?["kind"]?.object["enum"]?.array.contains(.string("audio")) == true)
        for method in ["library.analyze", "library.preview"] {
            #expect(ChatCommandSession.allowedMethods.contains(method))
        }
    }
}
