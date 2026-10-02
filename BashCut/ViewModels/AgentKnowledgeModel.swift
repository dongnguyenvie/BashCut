import Foundation
import Observation

struct ProjectSkill: Identifiable, Hashable {
    let name: String
    let url: URL
    let claude: Bool
    let codex: Bool
    var id: String { name }
}

@MainActor @Observable final class AgentKnowledgeModel {
    var memo = ""
    var skills: [ProjectSkill] = []
    var selectedSkill: String?
    var skillText = ""
    var newSkillName = ""
    var message = ""
    private var root: URL?

    var context: String {
        let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = skills.map(\.name).joined(separator: ", ")
        return "[Project memory]\n\(trimmed.isEmpty ? "No memo." : trimmed)\nSkills: \(names.isEmpty ? "none" : names)\n[/Project memory]"
    }

    func load(from root: URL) {
        self.root = root
        let manager = FileManager.default
        let memoURL = root.appendingPathComponent(".bashcut/agent-memory.md")
        memo = (try? String(contentsOf: memoURL, encoding: .utf8)) ?? ""
        let canonical = root.appendingPathComponent(".bashcut/skills", isDirectory: true)
        let claude = root.appendingPathComponent(".claude/skills", isDirectory: true)
        let codex = root.appendingPathComponent(".agents/skills", isDirectory: true)
        let names = Set([canonical, claude, codex].flatMap { directory in
            ((try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { manager.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) }
                .map(\.lastPathComponent)
        })
        skills = names.sorted().compactMap { name in
            let candidates = [canonical, codex, claude].map { $0.appendingPathComponent(name) }
            guard let url = candidates.first(where: {
                manager.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path)
            }) else { return nil }
            return ProjectSkill(
                name: name, url: url,
                claude: manager.fileExists(atPath: claude.appendingPathComponent(name).path),
                codex: manager.fileExists(atPath: codex.appendingPathComponent(name).path))
        }
        if let selectedSkill, skills.contains(where: { $0.name == selectedSkill }) {
            select(selectedSkill)
        } else if let first = skills.first {
            select(first.name)
        } else {
            selectedSkill = nil
            skillText = ""
        }
    }

    func saveMemo() {
        guard let root else { return }
        do {
            let url = root.appendingPathComponent(".bashcut/agent-memory.md")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try memo.write(to: url, atomically: true, encoding: .utf8)
            message = "Project memo saved"
        } catch { message = error.localizedDescription }
    }

    func select(_ name: String) {
        guard let skill = skills.first(where: { $0.name == name }) else { return }
        selectedSkill = name
        skillText = (try? String(contentsOf: skill.url.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
    }

    func createSkill() {
        guard let root else { return }
        let slug = newSkillName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
        guard valid else { return message = "Use a lowercase hyphenated skill name" }
        let directory = root.appendingPathComponent(".bashcut/skills/\(slug)", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            return message = "Skill already exists"
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let title = slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
            let source = "# \(title)\n\nDescribe when and how the agent should use this project skill.\n"
            try source.write(
                to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            try link(directory: directory, into: root.appendingPathComponent(".claude/skills"))
            try link(directory: directory, into: root.appendingPathComponent(".agents/skills"))
            newSkillName = ""
            load(from: root)
            select(slug)
            message = "Skill shared with Claude and Codex"
        } catch { message = error.localizedDescription }
    }

    func saveSkill() {
        guard let skill = skills.first(where: { $0.name == selectedSkill }) else { return }
        do {
            try skillText.write(
                to: skill.url.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            message = "Skill saved"
        } catch { message = error.localizedDescription }
    }

    func shareSelectedWithBoth() {
        guard let root, let skill = skills.first(where: { $0.name == selectedSkill }) else { return }
        do {
            let canonical = root.appendingPathComponent(".bashcut/skills/\(skill.name)", isDirectory: true)
            if !FileManager.default.fileExists(atPath: canonical.path) {
                try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
                try skillText.write(
                    to: canonical.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            }
            try link(directory: canonical, into: root.appendingPathComponent(".claude/skills"))
            try link(directory: canonical, into: root.appendingPathComponent(".agents/skills"))
            load(from: root)
            message = "Skill available to both agents"
        } catch { message = error.localizedDescription }
    }

    private func link(directory: URL, into parent: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let link = parent.appendingPathComponent(directory.lastPathComponent)
        guard !manager.fileExists(atPath: link.path) else { return }
        try manager.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: "../../.bashcut/skills/\(directory.lastPathComponent)")
    }
}
