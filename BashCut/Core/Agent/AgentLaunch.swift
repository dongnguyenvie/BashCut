import Foundation

public enum TerminalProvider: String, CaseIterable, Sendable {
    case claude, codex, shell
    public var title: String { self == .claude ? "Claude" : self == .codex ? "Codex" : "Shell" }
}

public struct AgentSessionContext: Sendable {
    public let project: URL?
    public let token: String
    public let socket: String
    public let toolsDirectory: String
    public let prompt: String
    public init(project: URL?, token: String, socket: String, toolsDirectory: String, prompt: String) {
        self.project = project
        self.token = token
        self.socket = socket
        self.toolsDirectory = toolsDirectory
        self.prompt = prompt
    }
}

public struct AgentLaunch: Sendable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
    public let directory: String

    public static func make(
        provider: TerminalProvider, workspace: URL, context: AgentSessionContext,
        resumeID: String = "", environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AgentLaunch {
        let project = context.project
        let token = context.token
        let socket = context.socket
        let toolsDirectory = context.toolsDirectory
        let prompt = context.prompt
        var env = environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            toolsDirectory, "/usr/local/bin", "/opt/homebrew/bin", home + "/.local/bin",
            home + "/.cargo/bin",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS",
            env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        env["PATH"] = paths.joined(separator: ":")
        env["BASHCUT_SESSION_TOKEN"] = token
        env["BASHCUT_SOCKET"] = socket
        env["BASHCUT_PROJECT"] = project?.path ?? ""
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        let mcpExecutable = URL(fileURLWithPath: toolsDirectory).appendingPathComponent("bashcut-mcp").path
        if provider == .claude { env.removeValue(forKey: "ANTHROPIC_API_KEY") }
        let command = provider == .shell ? "zsh" : provider.rawValue
        guard
            let executable = env["PATH"]?.components(separatedBy: ":")
                .map({ URL(fileURLWithPath: $0).appendingPathComponent(command).path })
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else {
            throw ModelError.invalid("\(command) is not installed or is not on PATH")
        }
        let arguments: [String]
        switch provider {
        case .shell: arguments = ["-i"]
        case .claude:
            arguments =
                (resumeID.isEmpty ? [] : ["--resume", resumeID])
                + ["--mcp-config", claudeMCPConfig(command: mcpExecutable), "--append-system-prompt", prompt]
        case .codex:
            let socketDirectory = URL(fileURLWithPath: socket).deletingLastPathComponent().path
            let agentDirectory = URL(fileURLWithPath: socketDirectory)
                .appendingPathComponent("agent-workspace", isDirectory: true)
            try FileManager.default.createDirectory(
                at: agentDirectory, withIntermediateDirectories: true)
            let permissionProfile = """
                permissions.bashcut={ extends = ":workspace", \
                filesystem = { \(tomlString(socketDirectory)) = "write" }, \
                network = { enabled = true, unix_sockets = { \(tomlString(socket)) = "allow" } } }
                """
            arguments = [
                "-m", "gpt-5.6-luna",
                "-c", "model_reasoning_effort=\"low\"",
                "-c", "default_permissions=\"bashcut\"",
                "-c", permissionProfile,
                "-c", "mcp_servers.bashcut={ command = \(tomlString(mcpExecutable)), env_vars = [\"BASHCUT_SOCKET\", \"BASHCUT_SESSION_TOKEN\"] }",
                "-c", "features.network_proxy=true",
                "-c", "developer_instructions=\(tomlString(prompt))",
            ]
                + (resumeID.isEmpty ? [] : ["resume", resumeID])
            return AgentLaunch(
                executable: executable, arguments: arguments, environment: env,
                directory: agentDirectory.path)
        }
        return AgentLaunch(
            executable: executable, arguments: arguments, environment: env, directory: workspace.path)
    }

    private static func tomlString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return encoded.replacingOccurrences(of: "\\/", with: "/")
    }

    private static func claudeMCPConfig(command: String) -> String {
        let value = ["mcpServers": ["bashcut": ["command": command]]]
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let encoded = String(data: data, encoding: .utf8)
        else { return "{}" }
        return encoded
    }
}
