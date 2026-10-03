import Foundation
import Testing

@testable import BashCutAutomation

struct CommandReferenceTests {
    private static let published = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/reference/commands.md")

    @Test("docs/reference/commands.md is generated from CommandCatalog (scripts/update-commands.sh)")
    func publishedFileIsCurrent() throws {
        let generated = CommandReference.markdown()
        if ProcessInfo.processInfo.environment["BASHCUT_UPDATE_COMMANDS"] == "1" {
            try Data(generated.utf8).write(to: Self.published, options: .atomic)
        }
        let published = (try? String(contentsOf: Self.published, encoding: .utf8)) ?? ""
        #expect(published == generated, "Run scripts/update-commands.sh after changing CommandCatalog")
    }

    @Test("The reference lists every command with its MCP tool")
    func everyCommandListed() {
        let text = CommandReference.markdown()
        for spec in CommandCatalog.specs {
            #expect(text.contains("### `\(spec.usage)`"), "\(spec.name)")
            #expect(text.contains("`\(spec.mcpToolName)`"), "\(spec.name)")
        }
    }
}
