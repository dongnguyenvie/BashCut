import BashCutPlugin
import Foundation

/// Agents name a skill by its front matter `name`, and a plugin skill's is its bare folder name (`product-ad`). So
/// that `/` shows which plugin a skill comes from, agents get a wrapper per skill in one folder BashCut owns:
/// `<root>/<plugin>-<skill>/SKILL.md` is the plugin's text with the front matter `name` set to the link name, and every
/// other entry of the skill's folder is a link to the plugin's, so relative paths (`references/…`) still resolve.
/// Agent folders then link to the wrapper. Wrappers are rebuilt on every sync and only ever removed inside `root`.
public enum PluginSkillWrappers {
    /// Writes a wrapper for each skill under `root` and removes the wrappers of skills no longer given. Returns the
    /// skills with `folder` pointing at their wrapper; a skill whose wrapper cannot be written keeps its own folder.
    public static func prepare(_ skills: [PluginSkill], root: URL) -> [PluginSkill] {
        let manager = FileManager.default
        let wanted = Set(skills.map(\.linkName))
        for name in (try? manager.contentsOfDirectory(atPath: root.path)) ?? [] where !wanted.contains(name) {
            try? manager.removeItem(at: root.appendingPathComponent(name))
        }
        return skills.map { skill in
            let wrapper = root.appendingPathComponent(skill.linkName, isDirectory: true)
            do {
                try write(skill, to: wrapper)
                return PluginSkill(
                    pluginID: skill.pluginID, pluginName: skill.pluginName, name: skill.name,
                    description: skill.description, folder: wrapper)
            } catch {
                return skill
            }
        }
    }

    private static func write(_ skill: PluginSkill, to wrapper: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: wrapper.path) { try manager.removeItem(at: wrapper) }
        try manager.createDirectory(at: wrapper, withIntermediateDirectories: true)
        let text = try String(contentsOf: skill.file, encoding: .utf8)
        try renamed(text, to: skill.linkName).write(
            to: wrapper.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        for entry in try manager.contentsOfDirectory(atPath: skill.folder.path) where entry != "SKILL.md" {
            try manager.createSymbolicLink(
                at: wrapper.appendingPathComponent(entry), withDestinationURL: skill.folder.appendingPathComponent(entry))
        }
    }

    /// `text` with the front matter's `name:` line set to `name` (added when missing).
    static func renamed(_ text: String, to name: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
            let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return "---\nname: \(name)\n---\n" + text }
        if let line = lines[1..<end].firstIndex(where: { $0.hasPrefix("name:") }) {
            lines[line] = "name: \(name)"
        } else {
            lines.insert("name: \(name)", at: 1)
        }
        return lines.joined(separator: "\n")
    }
}
