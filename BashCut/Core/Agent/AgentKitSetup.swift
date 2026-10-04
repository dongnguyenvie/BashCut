import Foundation

/// Sets up Claude Code and Codex *outside* BashCut with the agent kit, like the kit's README does by hand:
/// Claude Code gets the `bashcut` plugin from the kit's marketplace (skills and the BashCut MCP server); Codex gets
/// the skills linked into `~/.agents/skills` and the MCP server registered with `codex mcp add`.
public enum AgentKitSetup {
    public enum Target: String, CaseIterable, Sendable { case claude, codex }

    public static let marketplace = "bashcut-agent-kit"
    public static let claudePlugin = "bashcut@bashcut-agent-kit"

    public struct Status: Sendable, Equatable {
        /// The CLI found on the search path, or nil.
        public let executable: String?
        public let installed: Bool
        public let detail: String
        /// Set up, but with an older kit than BashCut has: Update refreshes it. Claude Code caches per version.
        public let outdated: Bool

        public init(executable: String?, installed: Bool, detail: String, outdated: Bool = false) {
            self.executable = executable
            self.installed = installed
            self.detail = detail
            self.outdated = outdated
        }
    }

    /// Where the agent CLIs and their configuration are found.
    public struct Environment: Sendable {
        public let path: String
        public let home: URL
        public let variables: [String: String]
        public init(
            path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser,
            variables: [String: String] = ProcessInfo.processInfo.environment
        ) {
            self.path = path
            self.home = home
            self.variables = variables
        }
        var codexSkills: URL { home.appendingPathComponent(".agents/skills", isDirectory: true) }
    }

    public static func status(_ target: Target, kit: AgentKit?, environment: Environment) async -> Status {
        let executable = AgentLaunch.find(target.rawValue, path: environment.path)
        switch target {
        case .claude:
            guard let executable else { return Status(executable: nil, installed: false, detail: "Claude Code not found") }
            let result = await run(executable, ["plugin", "list", "--json"], environment)
            let plugins = (try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [[String: Any]]) ?? []
            let entry = plugins.first { $0["id"] as? String == claudePlugin }
            let enabled = entry?["enabled"] as? Bool ?? false
            let version = entry?["version"] as? String
            let outdated = entry != nil && kit != nil && version != kit?.version
            return Status(
                executable: executable, installed: entry != nil && enabled,
                detail: entry == nil ? "Plugin not installed"
                    : !enabled ? "Plugin installed but turned off"
                    : outdated ? "Plugin \(version ?? "?") installed; the kit is \(kit?.version ?? "?")"
                    : "Plugin \(version ?? "") installed",
                outdated: outdated)
        case .codex:
            let linked = kit.map { AgentKitInstall.linkedSkills(of: $0, in: environment.codexSkills).count } ?? 0
            let total = kit?.skills.count ?? 0
            var server = false
            if let executable { server = await run(executable, ["mcp", "get", "bashcut"], environment).status == 0 }
            return Status(
                executable: executable, installed: total > 0 && linked == total && server,
                detail: "\(linked) of \(total) skills linked; MCP server \(server ? "registered" : "missing")"
                    + (executable == nil ? "; Codex not found" : ""))
        }
    }

    /// Installs or refreshes the kit for `target`. Returns what was done.
    public static func install(_ target: Target, kit: AgentKit, environment: Environment) async throws -> String {
        let executable = try require(target, environment)
        switch target {
        case .claude:
            // Adding an existing marketplace fails; refreshing it then picks up the kit's current files.
            if await run(executable, ["plugin", "marketplace", "add", kit.root.path], environment).status != 0 {
                try await check(run(executable, ["plugin", "marketplace", "update", marketplace], environment))
            }
            let installed = await run(executable, ["plugin", "install", claudePlugin, "--scope", "user"], environment)
            if installed.status != 0 {
                try await check(run(executable, ["plugin", "update", claudePlugin], environment))
            }
            return "Claude Code: plugin \(claudePlugin) \(kit.version) installed"
        case .codex:
            let linked = try AgentKitInstall.linkSkills(of: kit, into: environment.codexSkills)
            _ = await run(executable, ["mcp", "remove", "bashcut"], environment)
            let launcher = kit.root.appendingPathComponent("scripts/bashcut-mcp.sh").path
            try await check(run(executable, ["mcp", "add", "bashcut", "--", launcher], environment))
            let skipped = kit.skills.count - linked.count
            return "Codex: \(linked.count) skills linked in \(environment.codexSkills.path), MCP server registered"
                + (skipped > 0 ? "; \(skipped) skipped because a folder with that name is not a link" : "")
        }
    }

    public static func remove(_ target: Target, kit: AgentKit?, environment: Environment) async throws -> String {
        let executable = try require(target, environment)
        switch target {
        case .claude:
            try await check(run(executable, ["plugin", "uninstall", claudePlugin], environment))
            _ = await run(executable, ["plugin", "marketplace", "remove", marketplace], environment)
            return "Claude Code: plugin \(claudePlugin) removed"
        case .codex:
            let names = kit.map { AgentKitInstall.linkedSkills(of: $0, in: environment.codexSkills) } ?? []
            let removed = AgentKitInstall.unlinkSkills(named: names, in: environment.codexSkills)
            _ = await run(executable, ["mcp", "remove", "bashcut"], environment)
            return "Codex: \(removed.count) skill links and the MCP server removed"
        }
    }

    private static func require(_ target: Target, _ environment: Environment) throws -> String {
        guard let executable = AgentLaunch.find(target.rawValue, path: environment.path) else {
            throw AgentKitError("\(target == .claude ? "Claude Code" : "Codex") is not installed or not on PATH")
        }
        return executable
    }

    struct Result: Sendable {
        let status: Int32
        let output: String
        let error: String
    }

    private static func check(_ result: Result) throws {
        guard result.status == 0 else {
            let message = (result.error.isEmpty ? result.output : result.error)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentKitError(String(message.prefix(500)))
        }
    }

    /// Runs a CLI with no input (so it can never wait on a prompt) for at most two minutes.
    static func run(_ executable: String, _ arguments: [String], _ environment: Environment) async -> Result {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var variables = environment.variables
            variables["PATH"] = environment.path
            variables["HOME"] = environment.home.path
            process.environment = variables
            process.standardInput = FileHandle.nullDevice
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            do { try process.run() } catch { return Result(status: -1, output: "", error: error.localizedDescription) }
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timeout)
            // Read before waiting, so a large output cannot fill the pipe and block the process.
            let out = output.fileHandleForReading.readDataToEndOfFile()
            let err = error.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            return Result(
                status: process.terminationStatus, output: String(bytes: out, encoding: .utf8) ?? "",
                error: String(bytes: err, encoding: .utf8) ?? "")
        }.value
    }
}
