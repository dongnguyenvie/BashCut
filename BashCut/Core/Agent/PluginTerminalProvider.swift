import BashCutPlugin
import BashCutProject
import Foundation

/// An agent CLI that a plugin adds to the dock (`agent.terminal`, docs/specs/12-terminal-agents.md). The plugin's
/// `launch` answer is checked into a `PluginTerminalLaunch` first; this provider then hands that command line to
/// `AgentLaunch.make` like the built-in Claude and Codex providers. Its ID is the plugin ID, which always has a dot,
/// so it never clashes with a built-in provider.
public struct PluginTerminalProvider: AgentProvider {
    public let id: AgentProviderID
    public let title: String
    public let command: String
    public let author = Author.agent
    public let environmentAllowlist: [String]
    public let environment: [String: String]
    let arguments: [String]
    let directory: URL?

    public init(plugin: InstalledPlugin, launch: PluginTerminalLaunch) {
        id = AgentProviderID(rawValue: plugin.id)
        title = plugin.manifest.displayName
        command = launch.executable
        environmentAllowlist = plugin.manifest.terminal?.environment ?? []
        environment = launch.environment
        arguments = launch.arguments
        directory = launch.directory
    }

    public func commandLine(for request: AgentLaunchRequest) throws -> AgentCommandLine {
        AgentCommandLine(arguments: arguments, directory: directory)
    }
}

/// A plugin's answer to `launch`, validated before anything starts.
public struct PluginTerminalLaunch: Sendable, Equatable {
    /// A name looked up on PATH, or an absolute path (paths inside the plugin are resolved).
    public let executable: String
    public let arguments: [String]
    public let directory: URL?
    public let environment: [String: String]
    /// Inside the agent folder: where the kit's skills are linked.
    public let skillsFolder: URL?

    static let reservedVariables: Set<String> = ["PATH", "HOME", "TERM", "COLORTERM"]

    public init(result: JSONValue, pluginDirectory: URL, agentFolder: URL) throws {
        let fields = result.object
        guard let executable = fields["executable"]?.string, !executable.isEmpty, !executable.contains("\0") else {
            throw PluginError.invalid("The terminal launch needs an executable")
        }
        if executable.hasPrefix("/") || !executable.contains("/") {
            self.executable = executable
        } else {
            let inside = pluginDirectory.appendingPathComponent(executable).standardizedFileURL
            guard inside.path.hasPrefix(pluginDirectory.standardizedFileURL.path + "/") else {
                throw PluginError.invalid("The terminal executable must stay inside the plugin folder")
            }
            self.executable = inside.path
        }
        let arguments = fields["arguments"]?.array ?? []
        guard arguments.count <= 256, arguments.allSatisfy({ $0.string.map { !$0.contains("\0") } ?? false }) else {
            throw PluginError.invalid("Terminal arguments must be at most 256 strings")
        }
        self.arguments = arguments.compactMap(\.string)
        directory = try fields["directory"]?.string.map { try Self.folder($0, field: "directory") }
        let environment = fields["environment"]?.object ?? [:]
        guard environment.count <= 64 else { throw PluginError.invalid("A terminal sets at most 64 variables") }
        var variables: [String: String] = [:]
        for (name, value) in environment {
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil,
                !name.hasPrefix("BASHCUT_"), !Self.reservedVariables.contains(name),
                let text = value.string, !text.contains("\0")
            else { throw PluginError.invalid("The terminal cannot set \(name)") }
            variables[name] = text
        }
        self.environment = variables
        if let skills = fields["skillsFolder"]?.string {
            let folder = URL(fileURLWithPath: skills).standardizedFileURL
            guard skills.hasPrefix("/"), folder.path.hasPrefix(agentFolder.standardizedFileURL.path + "/") else {
                throw PluginError.invalid("skillsFolder must be inside the agent folder")
            }
            skillsFolder = folder
        } else {
            skillsFolder = nil
        }
    }

    private static func folder(_ path: String, field: String) throws -> URL {
        var isFolder: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isFolder),
            isFolder.boolValue
        else { throw PluginError.invalid("The terminal \(field) must be an existing absolute folder") }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// The request side of `agent.terminal`.
public enum PluginTerminals {
    /// A folder BashCut owns for one plugin's tabs, where the plugin may write CLI configuration.
    public static func agentFolder(support: URL, pluginID: String) -> URL {
        support.appendingPathComponent("agent-workspaces/\(pluginID)", isDirectory: true)
    }

    // swiftlint:disable function_parameter_count
    /// Parameters of op `launch`, without `options` (the capability service adds them).
    public static func launchParams(
        workspace: URL, agentFolder: URL, project: URL?, prompt: String, mcpExecutable: String, kit: AgentKit?,
        resume: String, canEdit: Bool
    ) -> [String: JSONValue] {
        [
            "op": .string("launch"), "workspace": .string(workspace.path), "agentFolder": .string(agentFolder.path),
            "project": project.map { .string($0.path) } ?? .null, "prompt": .string(prompt),
            "mcp": .object([
                "name": .string("bashcut"), "command": .string(mcpExecutable), "arguments": .array([]),
                "environment": .array([.string("BASHCUT_SOCKET"), .string("BASHCUT_SESSION_TOKEN")]),
            ]),
            "kit": kit.map(kitJSON) ?? .null, "resume": .string(resume), "canEdit": .bool(canEdit),
        ]
    }
    // swiftlint:enable function_parameter_count

    /// Parameters of op `session`.
    public static func sessionParams(workspace: URL, agentFolder: URL, project: URL, notBefore: Date?) -> [String: JSONValue] {
        [
            "op": .string("session"), "workspace": .string(workspace.path), "agentFolder": .string(agentFolder.path),
            "project": .string(project.path), "notBefore": notBefore.map { .number($0.timeIntervalSince1970) } ?? .null,
        ]
    }

    /// The session ID in a `session` answer, when it is a plain identifier.
    public static func sessionID(from result: JSONValue) -> String? {
        guard let id = result.object["id"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
            id.count <= 256, id.range(of: "^[A-Za-z0-9._:-]+$", options: .regularExpression) != nil
        else { return nil }
        return id
    }

    /// The kit as chat and terminal agents receive it: folder, version and each skill's description.
    public static func kitJSON(_ kit: AgentKit) -> JSONValue {
        .object([
            "root": .string(kit.root.path), "skillsFolder": .string(kit.skillsFolder.path),
            "version": .string(kit.version),
            "skills": .array(kit.skills.map { name in
                .object(["name": .string(name), "description": .string(kit.description(of: name))])
            }),
        ])
    }
}
