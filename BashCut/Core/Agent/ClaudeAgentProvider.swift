import BashCutProject
import Foundation

/// Claude Code with the BashCut MCP server and instructions appended to its system prompt.
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
                + ["--mcp-config", Self.mcpConfig(command: request.mcpExecutable),
                   "--append-system-prompt", request.context.prompt])
    }

    private static func mcpConfig(command: String) -> String {
        let value = ["mcpServers": ["bashcut": ["command": command]]]
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let encoded = String(data: data, encoding: .utf8)
        else { return "{}" }
        return encoded
    }
}
