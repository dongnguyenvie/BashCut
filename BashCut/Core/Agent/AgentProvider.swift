import BashCutProject
import Foundation

/// Stable provider identifier, used for preferences and per-project session bookmarks.
public struct AgentProviderID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let claude: AgentProviderID = "claude"
    public static let codex: AgentProviderID = "codex"
    public static let shell: AgentProviderID = "shell"
}

/// Everything a provider needs to build its command line.
public struct AgentLaunchRequest: Sendable {
    public let workspace: URL
    public let context: AgentSessionContext
    /// Session to resume, already trimmed; empty starts a new session.
    public let resumeID: String
    /// Path of the bundled `bashcut-mcp` server.
    public let mcpExecutable: String
    /// The agent kit to load, or nil when Settings › Agents turns it off or no kit is found.
    public var kit: AgentKitLaunch?
}

/// The installed agent kit and the skills-only Claude plugin made from it (`AgentKitInstall`).
public struct AgentKitLaunch: Sendable {
    public let kit: AgentKit
    public let claudePlugin: URL
    public init(kit: AgentKit, claudePlugin: URL) {
        self.kit = kit
        self.claudePlugin = claudePlugin
    }
}

/// Arguments and working directory for one terminal launch.
public struct AgentCommandLine: Sendable {
    public var arguments: [String]
    /// nil runs in the request's workspace.
    public var directory: URL?
    public init(arguments: [String], directory: URL? = nil) {
        self.arguments = arguments
        self.directory = directory
    }
}

/// A terminal program the agent dock can launch: an agent CLI or a plain shell.
/// Adding a provider means one conforming type registered in `AgentProviders.all`, plus a test.
public protocol AgentProvider: Sendable {
    var id: AgentProviderID { get }
    var title: String { get }
    /// Executable name looked up on the launch PATH.
    var command: String { get }
    /// Author of edits made with this provider's session token.
    var author: Author { get }
    /// AI agents get session bookmarks, discovery and handoff; a plain shell does not.
    var isAgent: Bool { get }
    /// Variables this provider may inherit beyond `AgentEnvironment.common`.
    /// A trailing `*` matches a prefix.
    var environmentAllowlist: [String] { get }
    /// Folder of the provider's `.jsonl` session transcripts, relative to the home folder.
    var sessionFolder: String? { get }
    /// A session started in the workspace counts as the project's even without naming the project.
    var matchesWorkspaceSessions: Bool { get }
    func commandLine(for request: AgentLaunchRequest) throws -> AgentCommandLine
}

extension AgentProvider {
    public var isAgent: Bool { true }
    public var environmentAllowlist: [String] { [] }
    public var sessionFolder: String? { nil }
    public var matchesWorkspaceSessions: Bool { false }
}

public enum AgentProviders {
    public static let all: [any AgentProvider] = [ClaudeAgentProvider(), CodexAgentProvider(), ShellAgentProvider()]
    public static var agents: [any AgentProvider] { all.filter(\.isAgent) }

    public static func provider(_ id: AgentProviderID) -> (any AgentProvider)? {
        all.first { $0.id == id }
    }
}
