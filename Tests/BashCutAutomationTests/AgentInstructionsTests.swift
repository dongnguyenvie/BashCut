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
        // tool rules moved here from the kit's edit-workflow skill (spec 13 §9) every agent reads anyway. 36.5k since
        // clip reframe (P3-J1); UI-parity commands agents do with ops (text line-style, clip backdrop) stay out.
        // 37k since saved voices (#532: voice clone-add, voice use; listing and removing clones stay out).
        // 37.5k since generated pictures (#550: image generate, style, disclose, library brand-pose; the list stays
        // out).
        // 38k since library favorite and library list --favorites|--recent (P1-9).
        // 38.25k since clip volume (#628: the one-liner for clip gain agents kept hunting for in timeline apply).
        // 38.3k since captions group --break-at-cuts and review run --accepted (crash report B6, B7).
        // 38.4k since plan check --save (#631: agents scripted by-ID patches into whole lists before graphics).
        // 38.75k since batch run and batch status (P2-C1; cancelling and presets stay out).
        // 39k since captions replace and music replace (P2-C3; captions style stays out: agents use patchItems).
        // 39.25k since batch retry (an agent resumes the Vietsub batch after a missing key or a quit).
        // 39.6k since timeline cut-range and rippleDeleteRange (a restart cut from every layer in one op, not 159).
        // 39.7k since the stage_pending guard and plan.cut focus (merged together with cut-range for 0.0.35).
        #expect(text.count < 39_700)
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
