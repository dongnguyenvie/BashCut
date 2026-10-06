import Foundation

/// A skill the user or an agent wrote (#71). A project skill is `<project>/.bashcut/skills/<name>/SKILL.md`, linked
/// for Claude and Codex inside the project; a skill for every project is `<user>/skills/<name>/SKILL.md`, which
/// BashCut's agents read from the path listed in their knowledge.
public struct AgentKnowledgeSkill: Hashable, Sendable {
    public let name: String
    public let scope: KnowledgeScope
    /// The skill's folder.
    public let url: URL
    /// Whether the project's `.claude/skills` or `.agents/skills` has it (project skills only).
    public let claude: Bool
    public let codex: Bool
    /// Whether agents get it: a project skill is linked for at least one agent, a skill for every project has no
    /// `.disabled` marker.
    public let enabled: Bool

    public var file: URL { url.appendingPathComponent("SKILL.md") }
}

/// The front matter of a SKILL.md (`---` lines of `key: value` at the top) and the text after it.
public struct SkillFrontMatter: Sendable, Equatable {
    public var fields: [String: String] = [:]
    /// The field names in the order they are written.
    public var keys: [String] = []
    public var body: String

    public init(_ text: String) {
        body = text
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return }
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            if fields[key] == nil { keys.append(key) }
            fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        body = lines[(end + 1)...].joined(separator: "\n")
    }

    public var description: String { fields["description"] ?? "" }

    /// The quoted phrases after `Triggers:` in the description.
    public var triggers: [String] {
        guard let range = description.range(of: "Triggers:") else { return [] }
        return description[range.upperBound...].split(separator: "\"", omittingEmptySubsequences: true).enumerated()
            .filter { $0.offset % 2 == 1 }.map { String($0.element) }
    }

    /// The description without its trigger list.
    public var summary: String {
        guard let range = description.range(of: "Triggers:") else { return description }
        return description[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
    }
}

extension AgentKnowledgeStore {
    static let disabledMarker = ".disabled"

    private var projectSkillFolders: (canonical: URL, claude: URL, codex: URL)? {
        project.map {
            ($0.appendingPathComponent(".bashcut/skills", isDirectory: true),
             $0.appendingPathComponent(".claude/skills", isDirectory: true),
             $0.appendingPathComponent(".agents/skills", isDirectory: true))
        }
    }

    var userSkillsFolder: URL { user.appendingPathComponent("skills", isDirectory: true) }

    /// The skills of one scope, sorted by name. Project skills include ones only in an agent's folder, but not the
    /// plugin skills BashCut linked there.
    public func skills(_ scope: KnowledgeScope = .project) -> [AgentKnowledgeSkill] {
        let manager = FileManager.default
        let hasSkill = { (url: URL) in manager.fileExists(atPath: url.appendingPathComponent("SKILL.md").path) }
        let children = { (directory: URL) in
            ((try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []).filter(hasSkill)
        }
        guard scope == .project else {
            return children(userSkillsFolder).map(\.lastPathComponent).sorted().map { name in
                let url = userSkillsFolder.appendingPathComponent(name, isDirectory: true)
                return AgentKnowledgeSkill(
                    name: name, scope: .user, url: url, claude: false, codex: false,
                    enabled: !manager.fileExists(atPath: url.appendingPathComponent(Self.disabledMarker).path))
            }
        }
        guard let (canonical, claude, codex) = projectSkillFolders else { return [] }
        // Plugin skills linked here are the plugin's, listed in the plugin scope.
        let names = Set([canonical, claude, codex].flatMap(children).map(\.lastPathComponent))
            .subtracting(linkedPluginSkills())
        return names.sorted().compactMap { name in
            guard let url = [canonical, codex, claude].map({ $0.appendingPathComponent(name) }).first(where: hasSkill)
            else { return nil }
            let inClaude = manager.fileExists(atPath: claude.appendingPathComponent(name).path)
            let inCodex = manager.fileExists(atPath: codex.appendingPathComponent(name).path)
            return AgentKnowledgeSkill(
                name: name, scope: .project, url: url, claude: inClaude, codex: inCodex, enabled: inClaude || inCodex)
        }
    }

    public func skill(_ name: String, scope: KnowledgeScope = .project) -> AgentKnowledgeSkill? {
        skills(scope).first { $0.name == name }
    }

    /// The text of a skill's SKILL.md; nil when there is no such skill.
    public func skillText(_ name: String, scope: KnowledgeScope = .project) -> String? {
        skill(name, scope: scope).flatMap { try? String(contentsOf: $0.file, encoding: .utf8) }
    }

    /// A lowercase hyphenated skill name, or an error.
    public static func skillName(_ name: String) throws -> String {
        let slug = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil else {
            throw KnowledgeError("Use a lowercase hyphenated skill name")
        }
        return slug
    }

    /// Replaces a skill's SKILL.md, or creates the skill (with a starter text unless `text` is given): a project
    /// skill in `.bashcut/skills`, linked for Claude and Codex; a skill for every project in the user folder.
    /// History records the text before and after (#70).
    public func writeSkill(
        named name: String, text: String? = nil, scope: KnowledgeScope = .project,
        source: KnowledgeSource = KnowledgeSource(agent: "user"), action: KnowledgeChange.Action? = nil
    ) throws {
        if scope == .project, projectSkillFolders == nil { throw Self.noProject }
        let slug = try Self.skillName(name)
        if let existing = skill(slug, scope: scope) {
            guard let text else { throw KnowledgeError("Skill already exists") }
            let before = skillText(slug, scope: scope)
            try text.write(to: existing.file, atomically: true, encoding: .utf8)
            guard text != before else { return }
            try record(KnowledgeChange(
                action: action ?? .update, kind: .skill, target: slug, source: source, before: before.map { .text($0) },
                after: .text(text)), scope: scope)
            return
        }
        let title = slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        let text = text ?? "# \(title)\n\nDescribe when and how the agent should use this skill.\n"
        switch scope {
        case .project:
            try createCanonical(slug, text: text)
            try share(slug)
        case .user:
            let folder = userSkillsFolder.appendingPathComponent(slug, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try text.write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        try record(KnowledgeChange(
            action: action ?? .add, kind: .skill, target: slug, source: source, before: nil, after: .text(text)),
            scope: scope)
    }

    /// Removes a skill. A project skill's `.bashcut/skills` folder goes with the links to it; a copy only in one
    /// agent's folder is not BashCut's to remove and stays. History keeps the text.
    public func removeSkill(
        named name: String, scope: KnowledgeScope = .project, source: KnowledgeSource = KnowledgeSource(agent: "user"),
        action: KnowledgeChange.Action = .remove
    ) throws {
        let manager = FileManager.default
        let folder: URL
        switch scope {
        case .project:
            guard let (canonical, _, _) = projectSkillFolders else { throw Self.noProject }
            folder = canonical.appendingPathComponent(name, isDirectory: true)
        case .user:
            folder = userSkillsFolder.appendingPathComponent(name, isDirectory: true)
        }
        guard let text = skillText(name, scope: scope), manager.fileExists(atPath: folder.path) else {
            throw KnowledgeError(scope == .project
                ? "No skill named \(name) in .bashcut/skills" : "No skill named \(name) for every project")
        }
        if scope == .project { try unlink(name) }
        try manager.removeItem(at: folder)
        try record(KnowledgeChange(
            action: action, kind: .skill, target: name, source: source, before: .text(text), after: nil),
            scope: scope)
    }

    /// Turns a skill on or off for agents. A project skill is linked into, or unlinked from, the project's
    /// `.claude/skills` and `.agents/skills`; a skill for every project gets or loses its `.disabled` marker.
    public func setSkillEnabled(_ name: String, _ enabled: Bool, scope: KnowledgeScope = .project) throws {
        guard let skill = skill(name, scope: scope) else {
            throw KnowledgeError("No skill named \(name)\(scope == .user ? " for every project" : "")")
        }
        switch scope {
        case .project:
            guard enabled else { return try unlink(name, requireAll: true) }
            try share(name)
        case .user:
            let marker = skill.url.appendingPathComponent(Self.disabledMarker)
            if enabled {
                if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
            } else {
                try Data().write(to: marker)
            }
        }
    }

    /// Links a project skill for both agents, first copying it into `.bashcut/skills` when it only exists in one
    /// agent's folder.
    public func share(_ name: String) throws {
        guard let (canonical, claude, codex) = projectSkillFolders else { throw Self.noProject }
        let source = canonical.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: source.path) {
            guard let skill = skill(name) else { throw KnowledgeError("No skill named \(name)") }
            try createCanonical(name, text: String(contentsOf: skill.file, encoding: .utf8))
        }
        try link(name, into: claude)
        try link(name, into: codex)
    }

    /// A proposed change to a kit skill (#71): a lesson for every project tagged `kit` and the skill's name, with the
    /// line diff as its fix, waiting in the Knowledge inbox. The kit itself is never written.
    public func proposeKitChange(
        skill: String, before: String, after: String, summary: String, reason: String = "", source: KnowledgeSource
    ) throws -> KnowledgeLesson {
        guard before != after else { throw KnowledgeError("The proposed text is the same as the kit's") }
        let summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return try addLesson(
            title: "Kit: \(skill) — \(summary.isEmpty ? "proposed change" : summary)",
            fix: KnowledgeDiff.unified(before, after), evidence: reason, tags: ["kit", skill], status: .proposed,
            scope: .user, source: source)
    }

    /// Removes the links BashCut made to `.bashcut/skills/<name>`. With `requireAll`, refuses first when an agent's
    /// folder holds a copy that is not such a link, since the skill would stay on for that agent.
    private func unlink(_ name: String, requireAll: Bool = false) throws {
        guard let (_, claude, codex) = projectSkillFolders else { throw Self.noProject }
        let manager = FileManager.default
        let isOurs = { (link: URL) in
            (try? manager.destinationOfSymbolicLink(atPath: link.path))?.hasSuffix(".bashcut/skills/\(name)") == true
        }
        let links = [claude, codex].map { $0.appendingPathComponent(name) }
        if requireAll, let foreign = links.first(where: { manager.fileExists(atPath: $0.path) && !isOurs($0) }) {
            throw KnowledgeError("\(foreign.path) is not a link BashCut made; remove it there to turn the skill off")
        }
        for link in links where isOurs(link) { try manager.removeItem(at: link) }
    }

    private func createCanonical(_ name: String, text: String) throws {
        guard let (canonical, _, _) = projectSkillFolders else { throw Self.noProject }
        let directory = canonical.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    private func link(_ name: String, into parent: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let link = parent.appendingPathComponent(name)
        guard (try? manager.destinationOfSymbolicLink(atPath: link.path)) == nil,
              !manager.fileExists(atPath: link.path) else { return }
        // Relative, so the link keeps working when the project folder moves.
        try manager.createSymbolicLink(atPath: link.path, withDestinationPath: "../../.bashcut/skills/\(name)")
    }
}
