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

    @Test("Sticker library commands (#64): place with position and size, add a file, save an overlay item")
    func stickerLibraryCommands() throws {
        let place = try CommandLineParser.parse([
            "library", "place", "project:arrow", "--at-frame", "12", "--duration", "45", "--position", "top-right",
            "--size", "0.25", "--track", "v2", "--base-rev", "7",
        ])
        #expect(place.spec.name == "library.place")
        #expect(place.params == [
            "id": .string("project:arrow"), "atFrame": .integer(12), "duration": .integer(45),
            "position": .string("top-right"), "size": .number(0.25), "track": .string("v2"), "baseRev": .integer(7),
        ])
        let point = try CommandLineParser.parse(["library", "place", "arrow", "--position", "0.2,0.7", "--base-rev", "1"])
        #expect(point.params["position"] == .string("0.2,0.7"))
        let properties = try #require(CommandCatalog.spec(named: "library.place")).inputSchema.object["properties"]?.object
        #expect(properties?["position"]?.object["type"] == .string("string"))
        #expect(properties?["size"]?.object["type"] == .string("number"))
        #expect(throws: (any Error).self) { try CommandLineParser.parse(["library", "place", "arrow", "--size", "3", "--base-rev", "1"]) }

        let add = try CommandLineParser.parse([
            "library", "add", "--kind", "sticker", "--name", "Arrow", "--file", "/tmp/arrow.png", "--pack", "Arrows",
            "--params", #"{"size":0.2,"position":"bottom-right","animation":"pop-in"}"#, "--license", "CC0",
        ])
        #expect(add.params["kind"] == .string("sticker") && add.params["file"] == .string("/tmp/arrow.png"))
        #expect(add.params["params"]?.object["position"] == .string("bottom-right"))

        let save = try CommandLineParser.parse([
            "library", "save-selection", "--kind", "sticker", "--name", "Logo", "--item", "c9", "--scope", "user",
        ])
        #expect(save.params == [
            "kind": .string("sticker"), "name": .string("Logo"), "item": .string("c9"), "scope": .string("user"),
        ])
        let kinds = try #require(CommandCatalog.spec(named: "library.save-selection")).inputSchema.object["properties"]?
            .object["kind"]?.object["enum"]?.array
        #expect(kinds?.contains(.string("sticker")) == true)
        // Remove, packs and listing the Stickers panel need nothing new.
        for name in ["library.remove", "library.import-pack", "library.export-pack", "library.list", "library.update"] {
            #expect(CommandCatalog.spec(named: name) != nil)
        }
        let list = try CommandLineParser.parse(["library", "list", "--panel", "stickers", "--pack", "Arrows"])
        #expect(list.params == ["panel": .string("stickers"), "pack": .string("Arrows")])
    }

    @Test("Plugin library commands (#81): search and generate run as jobs, add saves a candidate, the sheets open")
    @MainActor func pluginLibraryCommands() throws {
        let search = try CommandLineParser.parse([
            "library", "search", "rain on a window", "--kind", "audio", "--provider", "example.sounds", "--limit", "5",
            "--page", "2", "--save", "0", "--scope", "user",
        ])
        #expect(search.spec.name == "library.search" && search.spec.execution == .job)
        #expect(search.params == [
            "query": .string("rain on a window"), "kind": .string("audio"), "provider": .string("example.sounds"),
            "limit": .integer(5), "page": .integer(2), "save": .integer(0), "scope": .string("user"),
        ])
        #expect(throws: (any Error).self) { try CommandLineParser.parse(["library", "search", "rain", "--kind", "audio", "--limit", "99"]) }
        let searchSchema = try #require(CommandCatalog.spec(named: "library.search")).inputSchema.object
        #expect(searchSchema["required"] == .array([.string("query"), .string("kind")]))

        let generate = try CommandLineParser.parse([
            "library", "generate", "calm piano", "--kind", "audio", "--params", #"{"seconds":30}"#,
        ])
        #expect(generate.spec.name == "library.generate" && generate.spec.execution == .job)
        #expect(generate.params["prompt"] == .string("calm piano"))
        #expect(generate.params["params"]?.object["seconds"] == .integer(30))
        #expect(try #require(CommandCatalog.spec(named: "library.generate")).parameters.first?.sensitive == true)

        // A candidate is saved with library add; kind and name come from it.
        let add = try CommandLineParser.parse(["library", "add", "--from-result", "job-1:2", "--scope", "user", "--tags", "rain"])
        #expect(add.params == ["fromResult": .string("job-1:2"), "scope": .string("user"), "tags": .string("rain")])
        let addSchema = try #require(CommandCatalog.spec(named: "library.add")).inputSchema.object
        #expect(addSchema["required"] == nil || addSchema["required"] == .array([]))

        for method in ["library.search", "library.generate"] {
            #expect(ChatCommandSession.allowedMethods.contains(method))
        }
        #expect(CommandCatalog.dialogs.contains("library-search") && CommandCatalog.dialogs.contains("library-generate"))
        let open = try CommandLineParser.parse(["ui", "open", "library-search"])
        #expect(open.params["dialog"] == .string("library-search"))
    }
}
