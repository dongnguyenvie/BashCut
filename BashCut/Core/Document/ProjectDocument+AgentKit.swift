import BashCutAgent
import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// Settings › Agents and `agent status` / `agent setup`: the agent kit (editing skills) for BashCut's own Claude and
/// Codex tabs, and for Claude Code and Codex outside BashCut.
extension ProjectDocument {
    /// The user's login shell values of `CLAUDE_CONFIG_DIR` and `CODEX_HOME`, read once.
    @MainActor private static var shellAgentValues: [String: String]?

    var agentToolsDirectory: String { Bundle.main.executableURL?.deletingLastPathComponent().path ?? "" }
    private var agentKitInstall: AgentKitInstall { AgentKitInstall(support: StorageUsage.supportFolder) }

    /// Claude Code's and Codex's configuration folders (Settings, then BashCut's environment, then the login shell).
    func agentConfigFolders() async -> AgentConfigFolders {
        if Self.shellAgentValues == nil { Self.shellAgentValues = await AgentConfigFolders.loginShellValues() }
        return AgentConfigFolders.resolve(
            claudeSetting: settings.claudeConfigFolder, codexSetting: settings.codexHomeFolder,
            environment: ProcessInfo.processInfo.environment, shell: Self.shellAgentValues ?? [:])
    }

    /// The environment agent tabs and agent CLIs start from: BashCut's own, with the configuration folders set.
    func agentEnvironment() async -> [String: String] {
        await agentConfigFolders().applied(to: ProcessInfo.processInfo.environment)
    }

    /// `agentEnvironment()` without waiting: uses the login shell values when they were read already
    /// (`startAutomation` reads them at launch).
    var currentAgentEnvironment: [String: String] {
        currentAgentConfigFolders.applied(to: ProcessInfo.processInfo.environment)
    }

    var currentAgentConfigFolders: AgentConfigFolders {
        AgentConfigFolders.resolve(
            claudeSetting: settings.claudeConfigFolder, codexSetting: settings.codexHomeFolder,
            environment: ProcessInfo.processInfo.environment, shell: Self.shellAgentValues ?? [:])
    }

    /// The kit agents use, installed in BashCut's support folder; nil when there is none.
    func installedAgentKit() throws -> AgentKit? {
        guard let kit = AgentKit.locate(folder: settings.agentKitFolder, support: StorageUsage.supportFolder) else { return nil }
        return try agentKitInstall.stableRoot(for: kit)
    }

    /// What BashCut's Claude and Codex tabs load; nil when Settings turns the kit off or there is none.
    func agentKitLaunch() -> AgentKitLaunch? {
        guard settings.loadAgentKit else { return nil }
        do {
            guard let kit = try installedAgentKit() else { return nil }
            return AgentKitLaunch(kit: kit, claudePlugin: try agentKitInstall.claudePlugin(for: kit))
        } catch {
            DebugLog.write("agent-kit", "not loaded: \(error.localizedDescription)")
            return nil
        }
    }

    private func setupEnvironment() async -> AgentKitSetup.Environment {
        let environment = await agentEnvironment()
        return AgentKitSetup.Environment(
            path: AgentLaunch.searchPath(toolsDirectory: agentToolsDirectory, environment: environment),
            variables: environment)
    }

    /// Whether Claude Code and Codex outside BashCut have the kit.
    func agentSetupStatuses() async -> [AgentKitSetup.Target: AgentKitSetup.Status] {
        let kit = try? installedAgentKit()
        let environment = await setupEnvironment()
        var statuses: [AgentKitSetup.Target: AgentKitSetup.Status] = [:]
        for target in AgentKitSetup.Target.allCases {
            statuses[target] = await AgentKitSetup.status(target, kit: kit, environment: environment)
        }
        return statuses
    }

    func agentStatus() async -> JSONValue {
        let kit = try? installedAgentKit()
        let folders = await agentConfigFolders()
        let statuses = await agentSetupStatuses()
        var agents: [String: JSONValue] = [:]
        for target in AgentKitSetup.Target.allCases {
            guard let status = statuses[target] else { continue }
            let folder = target == .claude ? folders.claude : folders.codex
            agents[target.rawValue] = .object([
                "cli": status.executable.map(JSONValue.string) ?? .null, "installed": .bool(status.installed),
                "outdated": .bool(status.outdated),
                "detail": .string(status.detail), "configFolder": .string(folder.url.path),
                "configFrom": .string(folder.origin.rawValue),
                "configFolders": .array(
                    AgentConfigFolders.candidates(claude: target == .claude).map { .string($0.path) }),
            ])
        }
        return .object([
            "kit": kit.map { kit in
                .object([
                    "path": .string(kit.root.path), "version": .string(kit.version),
                    "source": .string(agentKitSourceName(kit)),
                    "skills": .array(kit.skills.map(JSONValue.string)),
                ])
            } ?? .null,
            "inApp": .bool(settings.loadAgentKit),
            "agents": .object(agents),
        ])
    }

    /// Sets up (or with `remove`, undoes) one target: `in-app` turns loading in BashCut's tabs on or off, `claude`
    /// and `codex` change those agents' own configuration. Returns what was done.
    func setUpAgent(_ target: String, remove: Bool) async throws -> String {
        if target == "in-app" {
            settings.loadAgentKit = !remove
            return remove ? "BashCut's Claude and Codex tabs start without the kit"
                : "New Claude and Codex tabs in BashCut load the kit"
        }
        guard let agent = AgentKitSetup.Target(rawValue: target) else {
            throw AgentKitError("Unknown agent \(target): use claude, codex or in-app")
        }
        let environment = await setupEnvironment()
        let kit = try installedAgentKit()
        let result: String
        if remove {
            result = try await AgentKitSetup.remove(agent, kit: kit, environment: environment)
        } else {
            guard let kit else { throw AgentKitError("No agent kit found: choose a kit folder in Settings › Agents") }
            result = try await AgentKitSetup.install(agent, kit: kit, environment: environment)
        }
        DebugLog.write("agent-kit", result)
        return result
    }

    private func agentKitSourceName(_ kit: AgentKit) -> String {
        guard settings.agentKitFolder == nil else { return "folder" }
        // The stable copy hides where it came from; the newest located kit tells.
        return AgentKit.locate(folder: nil, support: StorageUsage.supportFolder)?.source == .downloaded ? "downloaded" : "built-in"
    }

    private var agentKitUpdater: AgentKitUpdater { AgentKitUpdater(support: StorageUsage.supportFolder) }

    /// The newest kit release this app can install, compared with the kit in use. A chosen folder is never updated.
    func checkAgentKitUpdate() async throws -> (kit: AgentKit?, release: AgentKitRelease?) {
        let kit = AgentKit.locate(folder: settings.agentKitFolder, support: StorageUsage.supportFolder)
        guard settings.agentKitFolder == nil else { return (kit, nil) }
        let catalog = try await agentKitUpdater.catalog()
        return (kit, catalog.update(from: kit?.version ?? "0.0.0", appVersion: Self.appVersion))
    }

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    func agentKitUpdateStatus() async throws -> JSONValue {
        let (kit, release) = try await checkAgentKitUpdate()
        var fields: [String: JSONValue] = [
            "current": kit.map { .string($0.version) } ?? .null, "updateAvailable": .bool(release != nil),
            "source": kit.map { .string(settings.agentKitFolder == nil ? $0.source.rawValue : "folder") } ?? .null,
        ]
        if settings.agentKitFolder != nil { fields["note"] = .string("A chosen kit folder is used as it is; it is not updated") }
        if let release {
            fields["latest"] = .object([
                "version": .string(release.version), "releasedAt": release.releasedAt.map(JSONValue.string) ?? .null,
                "notes": release.notes?["en"].map(JSONValue.string) ?? .null, "url": .string(release.url),
            ])
        }
        return .object(fields)
    }

    /// Installs the newest release, then refreshes Claude Code and Codex where the kit was set up. Returns what was done.
    func updateAgentKit() async throws -> String {
        let (current, release) = try await checkAgentKitUpdate()
        guard let release else {
            return settings.agentKitFolder == nil
                ? "The agent kit \(current?.version ?? "") is up to date" : "A chosen kit folder is not updated"
        }
        let installed = try await agentKitUpdater.install(release)
        DebugLog.write("agent-kit", "downloaded \(installed.version)")
        var done = ["Agent kit \(installed.version) installed"]
        for (target, status) in await agentSetupStatuses().sorted(by: { $0.key.rawValue < $1.key.rawValue })
        where status.installed {
            done.append(try await setUpAgent(target.rawValue, remove: false))
        }
        return done.joined(separator: "; ")
    }

    /// Uses the kit in `path`, or the built-in kit for `built-in`.
    func chooseAgentKit(_ path: String) throws {
        if path == "built-in" {
            settings.agentKitFolder = nil
            return
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard AgentKit(root: url, source: .folder) != nil else {
            throw AgentKitError("\(path) is not an agent kit (.claude-plugin/plugin.json and skills/*/SKILL.md)")
        }
        settings.agentKitFolder = url
    }

    func registerAgentKitCommands() {
        handle("agent.status") { document, _, _ in await document.agentStatus() }
        handle("agent.kit-check") { document, _, _ in try await document.agentKitUpdateStatus() }
        handleAuthored("agent.kit-update") { document, _, author in
            // Downloads code that Claude Code and Codex run, so it asks first like agent setup.
            let request = try document.queuePrivilegedApproval(method: "agent.kit-update", author: author, arguments: [:]) {
                Task { @MainActor in
                    do { document.message = try await document.updateAgentKit() } catch {
                        document.message = error.localizedDescription
                    }
                }
            }
            return .object([
                "approval": .string(request.autoApproved ? "approved" : "pending"),
                "requestId": .string(request.id.uuidString),
                "next": .string("Run agent kit-check or agent status to see the result once it is approved"),
            ])
        }
        handleAuthored("agent.setup") { document, arguments, author in
            let target = try arguments.string("target")
            let remove = arguments.bool("remove")
            let kit = arguments.optionalString("kit")
            let folders = [
                (AgentConfigFolders.claudeVariable, arguments.optionalString("claudeConfigDir")),
                (AgentConfigFolders.codexVariable, arguments.optionalString("codexHome")),
            ]
            // Keywords stay words, so paths are not made absolute by the CLI: require them absolute here.
            for case let value? in [kit, folders[0].1, folders[1].1]
            where !["built-in", "default"].contains(value) && !value.hasPrefix("/") {
                throw RPCFailure(-32602, "\(value): use an absolute path")
            }
            if let kit, kit != "built-in", AgentKit(root: URL(fileURLWithPath: kit), source: .folder) == nil {
                throw RPCFailure(-32602, "\(kit) is not an agent kit (.claude-plugin/plugin.json and skills/*/SKILL.md)")
            }
            var shown = ["target": target, "remove": remove ? "yes" : "no"]
            if let kit { shown["kit"] = kit }
            for case let (name, value?) in folders { shown[name] = value }
            // It changes the user's own agent configuration, so it asks first like an export.
            let request = try document.queuePrivilegedApproval(method: "agent.setup", author: author, arguments: shown) {
                Task { @MainActor in
                    do {
                        if let kit { try document.chooseAgentKit(kit) }
                        for case let (name, value?) in folders {
                            let url = value == "default" ? nil : URL(fileURLWithPath: value).standardizedFileURL
                            if name == AgentConfigFolders.claudeVariable {
                                document.settings.claudeConfigFolder = url
                            } else {
                                document.settings.codexHomeFolder = url
                            }
                        }
                        document.message = try await document.setUpAgent(target, remove: remove)
                    } catch {
                        document.message = error.localizedDescription
                    }
                }
            }
            return .object([
                "approval": .string(request.autoApproved ? "approved" : "pending"),
                "requestId": .string(request.id.uuidString),
                "next": .string("Run agent status to see the result once it is approved"),
            ])
        }
    }
}
