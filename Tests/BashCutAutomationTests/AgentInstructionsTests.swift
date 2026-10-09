import BashCutProject
import Foundation
import Testing

@testable import BashCutAutomation

struct AgentInstructionsTests {
    @Test("Agent instructions list every agent command in short, leave out user-only ones, and no fixed track IDs")
    func instructions() {
        let text = CommandCatalog.instructions
        for spec in CommandCatalog.specs {
            let listed = text.contains("`\(CommandCatalog.compactUsage(spec))`:")
            #expect(listed == !CommandCatalog.hiddenFromAgents.contains(spec.name), "\(spec.name)")
        }
        #expect(CommandCatalog.hiddenFromAgents.isSubset(of: Set(CommandCatalog.specs.map(\.name))))
        // About 8k tokens (flexibility audit, D15): full descriptions are in `bashcut help` and the MCP tools. The
        // tool rules moved here from the kit's edit-workflow skill (spec 13 §9) every agent reads anyway.
        #expect(text.count < 36_000)
        for rule in ["-32004", "held: true", "capability_missing", "agentPermissions", "Library first", "audit_missing"] {
            #expect(text.contains(rule), "\(rule)")
        }
        #expect(!text.contains(#""v1""#))
        #expect(!text.contains(#""t1""#))
        #expect(text.contains("bashcut timeline get"))
    }

    @Test("A summary's gist ends at its first sentence, colon or semicolon outside brackets, within about 160 characters")
    func gist() {
        #expect(CommandCatalog.firstSentence("Read the whole thing (a, b. c). Then more.") == "Read the whole thing (a, b. c).")
        #expect(CommandCatalog.firstSentence("Read the shots on Main in order: index, id") == "Read the shots on Main in order")
        let long = String(repeating: "word ", count: 60)
        #expect(CommandCatalog.firstSentence(long).count <= 161 && CommandCatalog.firstSentence(long).hasSuffix("…"))
    }

    @Test("Provider jobs take a request ID and a dry run; the capability list comes from the catalog")
    func providerJobs() throws {
        for (name, _) in CommandCatalog.capabilities {
            let spec = try #require(CommandCatalog.spec(named: name), "\(name)")
            guard spec.execution == .job else { continue }
            #expect(spec.parameters.contains { $0.name == "requestId" }, "\(name)")
            #expect(spec.parameters.contains { $0.name == "dryRun" }, "\(name)")
        }
        #expect(CommandCatalog.spec(named: "audio.energy")?.capability == "audio.energy")
    }
}
