import Foundation

/// Whether Claude Code and Codex trust the folder they start in, read from and written to their own configuration, so
/// BashCut can ask in its own sheet instead of the CLIs' trust menu. Neither CLI has a flag for it: Claude Code keeps
/// `projects[<folder>].hasTrustDialogAccepted` in `.claude.json`, Codex `[projects."<folder>"] trust_level` in
/// `config.toml`. Both key a folder by its git repository's root, else by the folder, with symlinks resolved.
public struct AgentFolderTrust: Sendable {
    public let folders: AgentConfigFolders

    public init(folders: AgentConfigFolders) { self.folders = folders }

    /// The agents that ask before working in a folder.
    public static func asks(_ provider: AgentProviderID) -> Bool { provider == .claude || provider == .codex }

    /// `.claude.json`: in `CLAUDE_CONFIG_DIR` when it is set, else next to the standard `~/.claude` folder.
    public var claudeConfig: URL {
        let folder = folders.claude
        return (folder.exported == nil ? folder.url.deletingLastPathComponent() : folder.url)
            .appendingPathComponent(".claude.json")
    }

    public var codexConfig: URL { folders.codex.url.appendingPathComponent("config.toml") }

    public func isTrusted(_ provider: AgentProviderID, folder: URL) -> Bool {
        switch provider {
        case .claude:
            // Claude Code also trusts a folder below a trusted one, up to its repository's root.
            guard let projects = (try? Self.readJSON(claudeConfig))?["projects"] as? [String: Any] else { return false }
            return Self.claudeCandidates(folder).contains {
                ((projects[$0] as? [String: Any])?["hasTrustDialogAccepted"] as? Bool) == true
            }
        case .codex:
            let text = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
            return CodexProjects.trustLevel(in: text, project: Self.key(Self.resolved(folder))) == "trusted"
        default:
            return true
        }
    }

    /// Records that `provider` may work in `folder` (its repository's root when it is in one), under the path as
    /// given and with symlinks resolved, leaving everything else in the file as it was. The file is replaced in one
    /// step, so a CLI reading it never sees half of it.
    public func trust(_ provider: AgentProviderID, folder: URL) throws {
        let keys = Self.keys(folder)
        switch provider {
        case .claude:
            var config = try Self.readJSON(claudeConfig) ?? [:]
            var projects = config["projects"] as? [String: Any] ?? [:]
            for key in keys {
                var project = projects[key] as? [String: Any] ?? [:]
                project["hasTrustDialogAccepted"] = true
                projects[key] = project
            }
            config["projects"] = projects
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .withoutEscapingSlashes])
            try Self.replace(claudeConfig, with: data)
        case .codex:
            var text = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
            for key in keys { text = try CodexProjects.trusting(key, in: text) }
            try Self.replace(codexConfig, with: Data(text.utf8))
        default:
            return
        }
    }

    // MARK: - Bypass Permissions mode

    /// Claude Code's user settings, in its config folder (`$CLAUDE_CONFIG_DIR` or `~/.claude`).
    public var claudeSettings: URL { folders.claude.url.appendingPathComponent("settings.json") }

    /// Whether Claude Code skips its one-time "Bypass Permissions mode" warning, which BashCut's
    /// `--dangerously-skip-permissions` launch otherwise shows on a config that never accepted it. Claude Code 2.1
    /// reads `skipDangerousModePermissionPrompt` from the user settings (`--settings` does not count) and still honours
    /// the older `bypassPermissionsModeAccepted` in `.claude.json`, which it moves to the settings.
    public var acceptsClaudeBypass: Bool {
        ((try? Self.readJSON(claudeSettings))?["skipDangerousModePermissionPrompt"] as? Bool) == true
            || ((try? Self.readJSON(claudeConfig))?["bypassPermissionsModeAccepted"] as? Bool) == true
    }

    /// Records the user's acceptance as Claude Code's own "Yes, I accept" does, keeping the rest of `settings.json`
    /// and replacing it in one step.
    public func acceptClaudeBypass() throws {
        var settings = try Self.readJSON(claudeSettings) ?? [:]
        settings["skipDangerousModePermissionPrompt"] = true
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .withoutEscapingSlashes])
        try Self.replace(claudeSettings, with: data)
    }

    // MARK: - Folders

    /// The folder's repository root, or the folder: what the CLIs key trust by.
    public static func key(_ folder: URL) -> String { (repositoryRoot(folder) ?? folder).path }

    /// The key as given and with symlinks resolved (`/tmp` is `/private/tmp`); the CLIs read the resolved one.
    static func keys(_ folder: URL) -> [String] {
        var keys = [key(folder)]
        let real = key(resolved(folder))
        if !keys.contains(real) { keys.append(real) }
        return keys
    }

    /// The real path, as the CLIs see their working folder. Not `resolvingSymlinksInPath()`: Foundation drops the
    /// `/private` of `/private/tmp` and `/private/var` again.
    static func resolved(_ folder: URL) -> URL {
        guard let real = realpath(folder.path, nil) else { return folder }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real), isDirectory: true)
    }

    /// The folders whose trust covers `folder` for Claude Code: it and each parent, up to its repository's root.
    static func claudeCandidates(_ folder: URL) -> [String] {
        let start = resolved(folder)
        let root = repositoryRoot(start)?.path
        var candidates: [String] = []
        var current = start
        while true {
            candidates.append(current.path)
            if current.path == root || current.path == "/" { break }
            current = current.deletingLastPathComponent()
        }
        return candidates
    }

    /// The nearest folder at or above `folder` with a `.git` folder or file (a worktree).
    static func repositoryRoot(_ folder: URL) -> URL? {
        var current = folder
        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) { return current }
            if current.path == "/" { return nil }
            current = current.deletingLastPathComponent()
        }
    }

    // MARK: - Files

    static func readJSON(_ url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return nil }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentFolderTrustError.unreadable(url.path)
        }
        return object
    }

    /// Writes a temporary file beside `url` with the same permissions (0600 for a new file), then renames it over.
    static func replace(_ url: URL, with data: Data) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let permissions = (try? manager.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int ?? 0o600
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).bashcut-\(UUID().uuidString)")
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: permissions])
        else { throw AgentFolderTrustError.unwritable(url.path) }
        guard rename(temporary.path, url.path) == 0 else {
            try? manager.removeItem(at: temporary)
            throw AgentFolderTrustError.unwritable(url.path)
        }
    }
}

public enum AgentFolderTrustError: Error, LocalizedError, Equatable {
    case unreadable(String)
    case unwritable(String)
    /// `config.toml` sets `projects` in a way BashCut does not edit (an inline table).
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path): "Cannot read \(path)"
        case .unwritable(let path): "Cannot write \(path)"
        case .unsupported(let path): "BashCut does not edit the projects table in \(path)"
        }
    }
}

/// The `[projects."<path>"]` tables of a Codex `config.toml`, edited line by line so comments, order and every other
/// table stay as they are.
enum CodexProjects {
    /// `trust_level` of the project's table, nil when it has none.
    static func trustLevel(in text: String, project: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let header = headerIndex(lines, project) else { return nil }
        for line in lines[(header + 1)...] {
            if isHeader(line) { break }
            if let value = trustValue(line) { return value }
        }
        return nil
    }

    /// The text with `trust_level = "trusted"` in the project's table, added at the end when there is none.
    static func trusting(_ project: String, in text: String) throws -> String {
        let trusted = "trust_level = \"trusted\""
        var lines = text.components(separatedBy: "\n")
        // `projects = { ... }` cannot take a `[projects."…"]` table after it; leave such a file alone.
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).range(of: #"^projects\s*="#, options: .regularExpression) != nil }) {
            throw AgentFolderTrustError.unsupported("config.toml")
        }
        if let header = headerIndex(lines, project) {
            var index = header + 1
            while index < lines.count, !isHeader(lines[index]) {
                if trustValue(lines[index]) != nil {
                    lines[index] = trusted
                    return lines.joined(separator: "\n")
                }
                index += 1
            }
            lines.insert(trusted, at: header + 1)
            return lines.joined(separator: "\n")
        }
        var result = text
        if !result.isEmpty, !result.hasSuffix("\n") { result += "\n" }
        if !result.isEmpty { result += "\n" }
        return result + "[projects.\(basicString(project))]\n\(trusted)\n"
    }

    private static func headerIndex(_ lines: [String], _ project: String) -> Int? {
        let headers = ["[projects.\(basicString(project))]", "[projects.'\(project)']"]
        return lines.firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return headers.contains { trimmed.hasPrefix($0) }
        }
    }

    private static func isHeader(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).hasPrefix("[") }

    private static func trustValue(_ line: String) -> String? {
        let pattern = #"^\s*trust_level\s*=\s*["']([^"']*)["']"#
        guard let match = line.range(of: pattern, options: .regularExpression) else { return nil }
        let assignment = line[match]
        guard let equals = assignment.firstIndex(of: "=") else { return nil }
        return assignment[assignment.index(after: equals)...]
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
    }

    /// A TOML basic string: JSON's escapes are valid TOML ones.
    static func basicString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value), let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded.replacingOccurrences(of: "\\/", with: "/")
    }
}

extension AgentFolderTrust {
    /// Whether trusting `parent` makes Claude Code trust `folder` too: `parent` is above it and no repository root
    /// is in between (Claude Code stops looking at the root).
    public static func parent(_ parent: URL, covers folder: URL) -> Bool {
        let parentPath = resolved(parent).path
        return resolved(folder).path != parentPath && claudeCandidates(folder).contains(parentPath)
    }
}
