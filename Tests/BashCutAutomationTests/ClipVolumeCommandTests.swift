import BashCutProject
import Foundation
import Testing

@testable import BashCutAutomation

/// `clip volume`, the one-liner for clip gain (#628).
struct ClipVolumeCommandTests {
    @Test("clip volume mirrors clip speed: optional item or items, a dB number (negative too), shown to agents (#628)")
    @MainActor func clipVolume() throws {
        let one = try CommandLineParser.parse(["clip", "volume", "m1", "--db", "-4", "--base-rev", "7"])
        #expect(one.spec.mode == .edit)
        #expect(one.params == ["item": .string("m1"), "db": .number(-4), "baseRev": .integer(7)])
        let many = try CommandLineParser.parse(["clip", "volume", "--items", "a,b", "--db", "3", "--base-rev", "7"])
        #expect(many.params == ["items": .string("a,b"), "db": .number(3), "baseRev": .integer(7)])
        let spec = try #require(CommandCatalog.spec(named: "clip.volume"))
        #expect(throws: RPCFailure.self) { try spec.validate(["db": .number(40), "baseRev": .integer(1)]) }
        #expect(throws: RPCFailure.self) { try spec.validate(["baseRev": .integer(1)]) }
        #expect(!CommandCatalog.hiddenFromAgents.contains("clip.volume") && CommandCatalog.instructions.contains("clip volume"))
        #expect(ChatCommandSession.allowedMethods.contains("clip.volume"))
    }
}
