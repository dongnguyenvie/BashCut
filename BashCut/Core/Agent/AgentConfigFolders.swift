import Foundation

/// Where Claude Code (`CLAUDE_CONFIG_DIR`) and Codex (`CODEX_HOME`) keep their login, settings, plugins and MCP
/// servers. People often move them in their shell profile, which BashCut does not see when it starts from Finder,
/// so each folder comes from, in order: Settings, BashCut's own environment, the user's login shell, the default.
public struct AgentConfigFolders: Sendable, Equatable {
    public enum Origin: String, Sendable { case settings, environment, shell, standard }

    public struct Folder: Sendable, Equatable {
        public let variable: String
        public let url: URL
        public let origin: Origin
        /// The value to export, nil for the standard folder (the CLI finds it by itself).
        public var exported: String? { origin == .standard ? nil : url.path }
    }

    public let claude: Folder
    public let codex: Folder

    public static let claudeVariable = "CLAUDE_CONFIG_DIR"
    public static let codexVariable = "CODEX_HOME"

    public static func resolve(
        claudeSetting: URL?, codexSetting: URL?, environment: [String: String], shell: [String: String],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> AgentConfigFolders {
        func folder(_ variable: String, _ setting: URL?, _ standard: String) -> Folder {
            if let setting { return Folder(variable: variable, url: setting, origin: .settings) }
            if let value = environment[variable], !value.isEmpty {
                return Folder(variable: variable, url: URL(fileURLWithPath: value), origin: .environment)
            }
            if let value = shell[variable], !value.isEmpty {
                return Folder(variable: variable, url: URL(fileURLWithPath: value), origin: .shell)
            }
            return Folder(variable: variable, url: home.appendingPathComponent(standard), origin: .standard)
        }
        return AgentConfigFolders(
            claude: folder(claudeVariable, claudeSetting, ".claude"),
            codex: folder(codexVariable, codexSetting, ".codex"))
    }

    /// Configuration folders found in the home folder, for choosing one: `.claude*` folders with `projects` or
    /// `settings.json` (several accounts are often kept side by side and picked with a shell alias that sets
    /// `CLAUDE_CONFIG_DIR` for one command, which no environment shows), and `.codex*` folders with `config.toml` or
    /// `sessions`. Sorted by name.
    public static func candidates(
        claude: Bool, home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let manager = FileManager.default
        let prefix = claude ? ".claude" : ".codex"
        let markers = claude ? ["projects", "settings.json"] : ["config.toml", "sessions"]
        let names = (try? manager.contentsOfDirectory(atPath: home.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.sorted().compactMap { name in
            let url = home.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
                markers.contains(where: { manager.fileExists(atPath: url.appendingPathComponent($0).path) })
            else { return nil }
            return url
        }
    }

    /// `environment` with both variables set where they are not standard.
    public func applied(to environment: [String: String]) -> [String: String] {
        var environment = environment
        for folder in [claude, codex] {
            if let value = folder.exported { environment[folder.variable] = value }
        }
        return environment
    }

    /// The two variables as the user's login shell sets them (`$SHELL -ilc`), read once per launch. Empty when the
    /// shell does not answer within five seconds.
    public static func loginShellValues(
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    ) async -> [String: String] {
        await Task.detached {
            let marker = "__BASHCUT_AGENT_CONFIG__"
            let script = "printf '\(marker)%s\\n%s\\n' \"$\(claudeVariable)\" \"$\(codexVariable)\""
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-ilc", script]
            process.standardInput = FileHandle.nullDevice
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return [:] }
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            return parse(String(bytes: data, encoding: .utf8) ?? "", marker: marker)
        }.value
    }

    /// Profiles may print their own lines; only what follows the marker counts.
    static func parse(_ output: String, marker: String) -> [String: String] {
        guard let range = output.range(of: marker, options: .backwards) else { return [:] }
        let lines = output[range.upperBound...].split(separator: "\n", omittingEmptySubsequences: false)
        var values: [String: String] = [:]
        if lines.count > 0, !lines[0].isEmpty { values[claudeVariable] = String(lines[0]) }
        if lines.count > 1, !lines[1].isEmpty { values[codexVariable] = String(lines[1]) }
        return values
    }
}
