import Foundation

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

    /// Builds the launch for `provider`: an allowlisted environment with the BashCut session
    /// variables, the executable found on the extended PATH, and the provider's command line.
    public static func make(
        provider: any AgentProvider, workspace: URL, context: AgentSessionContext,
        resumeID: String = "", kit: AgentKitLaunch? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AgentLaunch {
        var env = AgentEnvironment.filtered(environment, allowing: provider.environmentAllowlist)
        env["PATH"] = searchPath(toolsDirectory: context.toolsDirectory, environment: environment)
        env["BASHCUT_SESSION_TOKEN"] = context.token
        env["BASHCUT_SOCKET"] = context.socket
        env["BASHCUT_PROJECT"] = context.project?.path ?? ""
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        guard let executable = find(provider.command, path: env["PATH"] ?? "") else {
            throw AgentLaunchError.notInstalled(provider.command)
        }
        let request = AgentLaunchRequest(
            workspace: workspace, context: context,
            resumeID: provider.isAgent ? resumeID.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            mcpExecutable: URL(fileURLWithPath: context.toolsDirectory).appendingPathComponent("bashcut-mcp").path,
            kit: provider.isAgent ? kit : nil)
        let commandLine = try provider.commandLine(for: request)
        return AgentLaunch(
            executable: executable, arguments: commandLine.arguments, environment: env,
            directory: (commandLine.directory ?? workspace).path)
    }

    /// BashCut's tools first, then where agent CLIs usually live (including the ChatGPT app's Codex), then the
    /// inherited PATH.
    public static func searchPath(
        toolsDirectory: String, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            toolsDirectory, "/usr/local/bin", "/opt/homebrew/bin", home + "/.local/bin", home + "/.cargo/bin",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS",
            environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
        ].joined(separator: ":")
    }

    /// The first executable named `command` on `path`.
    public static func find(_ command: String, path: String) -> String? {
        path.components(separatedBy: ":")
            .map { URL(fileURLWithPath: $0).appendingPathComponent(command).path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

public enum AgentLaunchError: Error, LocalizedError {
    case notInstalled(String)
    public var errorDescription: String? {
        switch self {
        case .notInstalled(let command): "\(command) is not installed or is not on PATH"
        }
    }
}
