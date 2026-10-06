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
}
