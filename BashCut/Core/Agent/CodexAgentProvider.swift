import BashCutPlugin
import BashCutProject
import Foundation

/// Codex CLI on the low-cost model, sandboxed to a permission profile that may only write the
/// automation socket folder and the shared plugin data and cache (uv's Python and packages for the kit's scripts),
/// and reach the BashCut socket.
public struct CodexAgentProvider: AgentProvider {
    public init() {}
    public let id = AgentProviderID.codex
    public let title = "Codex"
    public let command = "codex"
    public let author = Author.codex
    public let environmentAllowlist = ["CODEX_*", "OPENAI_API_KEY", "OPENAI_BASE_URL"]
    public let sessionFolder: String? = ".codex/sessions"
    /// Codex trims a paste's trailing newline, so text typed after a `[Scope]` block would join `[/Scope]`; Ctrl+J
    /// inserts a newline in its input without sending.
    public let newlineAfterPaste: [UInt8]? = [10]

    public func commandLine(for request: AgentLaunchRequest) throws -> AgentCommandLine {
        let socket = request.context.socket
        let socketDirectory = URL(fileURLWithPath: socket).deletingLastPathComponent().path
        let agentDirectory = URL(fileURLWithPath: socketDirectory)
            .appendingPathComponent("agent-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
        try AgentKitInstall.syncSkills(
            of: request.kit?.kit, into: agentDirectory.appendingPathComponent(".agents/skills", isDirectory: true),
            plugins: request.pluginSkills)
        let permissionProfile = """
            permissions.bashcut={ extends = ":workspace", \
            filesystem = { \(Self.tomlString(socketDirectory)) = "write", \
            \(Self.tomlString(PluginFolders.sharedData.path)) = "write", \
            \(Self.tomlString(PluginFolders.sharedCache.path)) = "write" }, \
            network = { enabled = true, unix_sockets = { \(Self.tomlString(socket)) = "allow" } } }
            """
        let arguments = [
            "-m", "gpt-5.6-luna",
            "-c", "model_reasoning_effort=\"low\"",
            "-c", "default_permissions=\"bashcut\"",
            "-c", permissionProfile,
            "-c", "mcp_servers.bashcut={ command = \(Self.tomlString(request.mcpExecutable)), "
                + "env_vars = [\"BASHCUT_SOCKET\", \"BASHCUT_SESSION_TOKEN\"] }",
            "-c", "features.network_proxy=true",
            "-c", "developer_instructions=\(Self.tomlString(request.context.prompt))",
        ]
        return AgentCommandLine(
            arguments: arguments + (request.resumeID.isEmpty ? [] : ["resume", request.resumeID]),
            directory: agentDirectory)
    }

    // Codex reads skills from `.agents/skills` in its working folder, which belongs to BashCut: it holds exactly
    // the kit's skills, or none when the kit is off.

    private static func tomlString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return encoded.replacingOccurrences(of: "\\/", with: "/")
    }
}
