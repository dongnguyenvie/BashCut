import BashCutProject
import Foundation

/// Claude Code with the BashCut MCP server and instructions appended to its system prompt, without permission
/// prompts, and with AskUserQuestion answered in a card over the tab (`bashcut agent hook`, `agent.ask`).
/// Uses the CLI login: `ANTHROPIC_API_KEY` is never passed through.
public struct ClaudeAgentProvider: AgentProvider {
    public init() {}
    public let id = AgentProviderID.claude
    public let title = "Claude"
    public let command = "claude"
    public let author = Author.claude
    public let environmentAllowlist = ["CLAUDE_*", "ANTHROPIC_BASE_URL", "ANTHROPIC_MODEL"]
    public let sessionFolder: String? = ".claude/projects"
    public let matchesWorkspaceSessions = true

    public func commandLine(for request: AgentLaunchRequest) throws -> AgentCommandLine {
        AgentCommandLine(
            arguments: (request.resumeID.isEmpty ? [] : ["--resume", request.resumeID])
                + ["--dangerously-skip-permissions",
                   "--mcp-config", Self.mcpConfig(command: request.mcpExecutable),
                   "--settings", Self.askHookSettings(cli: Self.cli(request)),
                   "--append-system-prompt", request.context.prompt]
                + (request.kit.map { ["--plugin-dir", $0.claudePlugin.path] } ?? []))
    }

    /// The `bashcut` CLI next to the MCP bridge in BashCut's tools folder.
    static func cli(_ request: AgentLaunchRequest) -> String {
        URL(fileURLWithPath: request.mcpExecutable).deletingLastPathComponent().appendingPathComponent("bashcut").path
    }

    /// Claude Code `--settings` with a PreToolUse hook that runs `bashcut agent hook` for AskUserQuestion
    /// (BashCutAutomation's `ClaudeHook`). Its timeout outlasts `agent.ask`'s 900 s wait, so Claude never cancels a
    /// question the user is still answering; when the hook prints nothing Claude asks in the terminal.
    static func askHookSettings(cli: String) -> String {
        let command = "'" + cli.replacingOccurrences(of: "'", with: "'\\''") + "' agent hook"
        let value: [String: Any] = [
            "hooks": ["PreToolUse": [["matcher": "AskUserQuestion",
                                      "hooks": [["type": "command", "command": command, "timeout": 930]]]]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]),
              let encoded = String(data: data, encoding: .utf8)
        else { return "{}" }
        return encoded
    }

    private static func mcpConfig(command: String) -> String {
        let value = ["mcpServers": ["bashcut": ["command": command]]]
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let encoded = String(data: data, encoding: .utf8)
        else { return "{}" }
        return encoded
    }
}
