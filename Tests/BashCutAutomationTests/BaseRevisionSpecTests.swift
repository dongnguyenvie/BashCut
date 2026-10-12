import BashCutEngine
import BashCutProject
import Foundation
import Testing

@testable import BashCutAutomation

struct BaseRevisionSpecTests {
    @Test("--base-rev last passes through to the app; a list wrapped under its own name is the list")
    func lastRevisionAndWrappedList() throws {
        let add = try CommandLineParser.parse(["adjustment", "add", "--look", "vivid", "--base-rev", "last"])
        #expect(add.params["baseRev"] == .string("last"))
        #expect(throws: (any Error).self) { try CommandLineParser.parse(["adjustment", "add", "--base-rev", "first"]) }
        let schema = try #require(CommandCatalog.spec(named: "adjustment.add")).inputSchema
        #expect(schema.object["properties"]?.object["baseRev"]?.object["type"] == .array([.string("integer"), .string("string")]))
        let describe = try #require(CommandCatalog.spec(named: "media.describe"))
        let shots: JSONValue = .array([.object(["start": .number(0), "end": .number(1), "size": .string("MS")])])
        let values = try describe.validate([
            "shots": .object(["shots": shots, "media": .string("m")]), "media": .string("m"), "baseRev": .integer(1),
        ])
        #expect(values["shots"] == shots)
    }
}
