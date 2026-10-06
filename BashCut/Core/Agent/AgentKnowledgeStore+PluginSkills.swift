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
        guard let ledger = pluginSkillLedger, let data = try? Data(contentsOf: ledger),
            let names = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return names
    }

    /// Links `skills` into the project's agent folders and removes the links BashCut made for skills no longer in
    /// the list. A file or folder already there under the same name that is not BashCut's link is left alone.
    /// Returns the link names now in place. Without a project it does nothing.
    @discardableResult
    public func syncPluginSkills(_ skills: [PluginSkill]) throws -> [String] {
        guard let project, let ledger = pluginSkillLedger else { return [] }
        let manager = FileManager.default
        let folders = [".claude/skills", ".agents/skills"].map { project.appendingPathComponent($0, isDirectory: true) }
        let previous = Set(linkedPluginSkills())
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
