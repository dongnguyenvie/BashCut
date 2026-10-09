import BashCutPlugin
import Foundation

/// Plugin skills in the open project (#377): each ready plugin's skills are linked into the project's `.claude/skills`
/// and `.agents/skills` as `<plugin-id>--<name>`, like project skills, so Claude Code and Codex find them. The links
/// BashCut made are listed in `.bashcut/plugin-skills.json`; only those are ever removed, when the plugin stops
/// providing the skill (disabled, untrusted, removed) or the skill is gone.
extension AgentKnowledgeStore {
    private var pluginSkillLedger: URL? {
        project?.appendingPathComponent(".bashcut/plugin-skills.json")
    }

    /// The link names BashCut made for plugin skills in this project.
    public func linkedPluginSkills() -> [String] {
        pluginSkillLedger.map(Self.linkedNames) ?? []
    }

    /// Links `skills` into the project's agent folders and removes the links BashCut made for skills no longer in
    /// the list. A file or folder already there under the same name that is not BashCut's link is left alone.
    /// Returns the link names now in place. Without a project it does nothing.
    @discardableResult
    public func syncPluginSkills(_ skills: [PluginSkill]) throws -> [String] {
        guard let project, let ledger = pluginSkillLedger else { return [] }
        let folders = [".claude/skills", ".agents/skills"].map { project.appendingPathComponent($0, isDirectory: true) }
        return try Self.syncPluginSkillLinks(skills, folders: folders, ledger: ledger)
    }

    /// The user's own agent folders that get plugin skills, so `/` offers a recipe before any project exists: each
    /// Claude Code configuration folder where the kit's marketplace is registered (`~/.claude`, `$CLAUDE_CONFIG_DIR`
    /// and other `~/.claude-*` folders) and Codex's `~/.agents/skills` once the kit's `bc-*` skills are linked there.
    /// Folders of agents the user never set up with the kit are left alone.
    public static func userPluginSkillFolders(home: URL, variables: [String: String]) -> [URL] {
        let manager = FileManager.default
        var configs = [home.appendingPathComponent(".claude", isDirectory: true)]
        if let custom = variables["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            configs.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true))
        }
        let others = (try? manager.contentsOfDirectory(atPath: home.path)) ?? []
        configs += others.filter { $0.hasPrefix(".claude-") }.sorted().map { home.appendingPathComponent($0, isDirectory: true) }
        var folders: [URL] = []
        for config in configs where !folders.contains(config.appendingPathComponent("skills", isDirectory: true)) {
            let marketplaces = config.appendingPathComponent("plugins/known_marketplaces.json")
            guard let text = try? String(contentsOf: marketplaces, encoding: .utf8),
                text.contains("\"\(AgentKitSetup.marketplace)\"")
            else { continue }
            folders.append(config.appendingPathComponent("skills", isDirectory: true))
        }
        let codex = home.appendingPathComponent(".agents/skills", isDirectory: true)
        let codexEntries = (try? manager.contentsOfDirectory(atPath: codex.path)) ?? []
        if codexEntries.contains(where: { $0.hasPrefix("bc-") }) { folders.append(codex) }
        return folders
    }

    /// Links `skills` into the user's agent folders (`userPluginSkillFolders`) with its own ledger, the same way as a
    /// project's. Returns the link names now in place.
    @discardableResult
    public static func syncUserPluginSkills(_ skills: [PluginSkill], folders: [URL], ledger: URL) throws -> [String] {
        try syncPluginSkillLinks(skills, folders: folders, ledger: ledger)
    }

    private static func syncPluginSkillLinks(_ skills: [PluginSkill], folders: [URL], ledger: URL) throws -> [String] {
        let manager = FileManager.default
        let previous = Set(linkedNames(ledger))
        let wanted = Dictionary(skills.map { ($0.linkName, $0.folder) }, uniquingKeysWith: { first, _ in first })
        var linked = Set<String>()
        for folder in folders {
            for name in previous where wanted[name] == nil {
                let link = folder.appendingPathComponent(name)
                if AgentKitInstall.isLink(link) { try? manager.removeItem(at: link) }
            }
            for (name, destination) in wanted
            where try Self.linkPluginSkill(folder.appendingPathComponent(name), to: destination, ours: previous.contains(name)) {
                linked.insert(name)
            }
        }
        let names = linked.sorted()
        if names.isEmpty {
            if manager.fileExists(atPath: ledger.path) { try manager.removeItem(at: ledger) }
        } else if names != previous.sorted() || !manager.fileExists(atPath: ledger.path) {
            try manager.createDirectory(at: ledger.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(names).write(to: ledger, options: .atomic)
        }
        return names
    }

    private static func linkedNames(_ ledger: URL) -> [String] {
        guard let data = try? Data(contentsOf: ledger), let names = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return names
    }

    /// Points `link` at `destination`; false when something that is not BashCut's link (`ours`) holds the name.
    private static func linkPluginSkill(_ link: URL, to destination: URL, ours: Bool) throws -> Bool {
        let manager = FileManager.default
        let current = try? manager.destinationOfSymbolicLink(atPath: link.path)
        if current == destination.path { return true }
        guard current != nil ? ours : !manager.fileExists(atPath: link.path) else { return false }
        try manager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        if current != nil { try manager.removeItem(at: link) }
        try manager.createSymbolicLink(atPath: link.path, withDestinationPath: destination.path)
        return true
    }
}
