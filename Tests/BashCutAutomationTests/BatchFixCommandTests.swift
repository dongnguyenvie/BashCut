import BashCutProject
import Testing

@testable import BashCutAutomation

/// The batch-fix actions (P2-C3) on the CLI and MCP, and as batch steps.
struct BatchFixCommandTests {
    @Test("captions replace, captions style and music replace parse on the CLI and are edits chat agents may run")
    @MainActor func commands() throws {
        let replace = try CommandLineParser.parse([
            "captions", "replace", "acme", "--with", "Zeta", "--match-case", "--whole-word", "false", "--dry-run",
            "--base-rev", "4",
        ])
        #expect(replace.spec.name == "captions.replace")
        #expect(replace.params == [
            "find": .string("acme"), "with": .string("Zeta"), "matchCase": .bool(true), "wholeWord": .bool(false),
            "dryRun": .bool(true), "baseRev": .integer(4),
        ])
        let remove = try CommandLineParser.parse(["captions", "replace", "um", "--base-rev", "4"])
        #expect(remove.params["with"] == nil)

        let style = try CommandLineParser.parse([
            "captions", "style", "--preset", "user:bold-yellow", "--word-style", "karaoke", "--base-rev", "4",
        ])
        #expect(style.params == ["preset": .string("user:bold-yellow"), "wordStyle": .string("karaoke"), "baseRev": .integer(4)])

        let music = try CommandLineParser.parse(["music", "replace", "--media", "m2", "--from", "4.5", "--loop", "false", "--base-rev", "4"])
        #expect(music.params == ["media": .string("m2"), "from": .number(4.5), "loop": .bool(false), "baseRev": .integer(4)])
        let library = try CommandLineParser.parse(["music", "replace", "--library", "user:calm-bed", "--base-rev", "4"])
        #expect(library.params["library"] == .string("user:calm-bed"))

        for name in ["captions.replace", "captions.style", "music.replace"] {
            let spec = try #require(CommandCatalog.spec(named: name))
            #expect(spec.mode == .edit && spec.execution == .immediate)
            #expect(ChatCommandSession.allowedMethods.contains(name))
            #expect(spec.inputSchema.object["properties"]?.object["baseRev"] != nil)
        }
    }
}
