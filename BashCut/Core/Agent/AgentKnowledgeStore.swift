import Foundation

/// Where a memo lives: one project, or the user's notes that every project reads.
public enum KnowledgeScope: String, Sendable, CaseIterable {
    case project, user
}

/// A project skill: `<project>/.bashcut/skills/<name>/SKILL.md`, linked for Claude and Codex inside the project.
public struct AgentKnowledgeSkill: Hashable, Sendable {
    public let name: String
    public let url: URL
    public let claude: Bool
    public let codex: Bool
}

/// A memo that older builds wrote to the agent workspace or the home folder instead of the project.
public struct LegacyKnowledgeMemo: Hashable, Sendable {
    public let url: URL
    public let text: String
}

public struct KnowledgeError: LocalizedError, Equatable {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

/// Agent knowledge on disk (#100). The project memo and skills live in the open project's folder, never in the
/// agent workspace or the home folder; notes for every project live in the user folder. Project skills are linked
/// into `<project>/.claude/skills` and `<project>/.agents/skills` only.
public struct AgentKnowledgeStore: Sendable {
    /// The open project's folder; nil when no saved project is open.
    public let project: URL?
    /// `…/Application Support/BashCut/Knowledge`.
    public let user: URL
    /// Folders older builds used for the "project" memo (the agent workspace, the home folder).
    public let legacyFolders: [URL]

    static let memoPath = ".bashcut/agent-memory.md"

    public init(project: URL?, user: URL, legacyFolders: [URL] = []) {
        let project = project?.standardizedFileURL
        self.project = project
        self.user = user.standardizedFileURL
        self.legacyFolders = legacyFolders.map(\.standardizedFileURL).filter { $0 != project }
    }

    public static func userFolder(applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent("BashCut/Knowledge", isDirectory: true)
    }

    // MARK: Memos

    public func memoURL(_ scope: KnowledgeScope) -> URL? {
        switch scope {
        case .project: project?.appendingPathComponent(Self.memoPath)
        case .user: user.appendingPathComponent("agent-memory.md")
        }
    }

    public func memo(_ scope: KnowledgeScope) -> String {
        memoURL(scope).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    /// Replaces a memo; history records the text before and after (#70).
    public func writeMemo(
        _ text: String, scope: KnowledgeScope, source: KnowledgeSource = KnowledgeSource(agent: "user"),
        action: KnowledgeChange.Action = .update
    ) throws {
        let url = try writableMemoURL(scope)
        let before = memo(scope)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        guard text != before else { return }
        try record(KnowledgeChange(
            action: action, kind: .memo, target: "memo", source: source, before: .text(before), after: .text(text)),
            scope: scope)
    }

    private func writableMemoURL(_ scope: KnowledgeScope) throws -> URL {
        guard let url = memoURL(scope) else { throw Self.noProject }
        return url
    }

    static let noProject = KnowledgeError(
        "Save the project first: project knowledge is stored in the project's folder")

    // MARK: Skills

    private var skillFolders: (canonical: URL, claude: URL, codex: URL)? {
        project.map {
            ($0.appendingPathComponent(".bashcut/skills", isDirectory: true),
             $0.appendingPathComponent(".claude/skills", isDirectory: true),
             $0.appendingPathComponent(".agents/skills", isDirectory: true))
        }
    }

    public func skills() -> [AgentKnowledgeSkill] {
        guard let (canonical, claude, codex) = skillFolders else { return [] }
        let manager = FileManager.default
        let hasSkill = { (url: URL) in manager.fileExists(atPath: url.appendingPathComponent("SKILL.md").path) }
        let names = Set([canonical, claude, codex].flatMap { directory in
            ((try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter(hasSkill).map(\.lastPathComponent)
        })
        return names.sorted().compactMap { name in
            guard let url = [canonical, codex, claude].map({ $0.appendingPathComponent(name) }).first(where: hasSkill)
            else { return nil }
            return AgentKnowledgeSkill(
                name: name, url: url,
                claude: manager.fileExists(atPath: claude.appendingPathComponent(name).path),
                codex: manager.fileExists(atPath: codex.appendingPathComponent(name).path))
        }
    }

    /// The text of a skill's SKILL.md; nil when there is no such skill.
    public func skillText(_ name: String) -> String? {
        skills().first { $0.name == name }
            .flatMap { try? String(contentsOf: $0.url.appendingPathComponent("SKILL.md"), encoding: .utf8) }
    }

    /// Replaces a skill's SKILL.md, or creates `.bashcut/skills/<name>/SKILL.md` (with a starter text unless
    /// `text` is given) and links it for Claude and Codex. History records the text before and after (#70).
    public func writeSkill(
        named name: String, text: String? = nil, source: KnowledgeSource = KnowledgeSource(agent: "user"),
        action: KnowledgeChange.Action? = nil
    ) throws {
        guard skillFolders != nil else { throw Self.noProject }
        let slug = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil else {
            throw KnowledgeError("Use a lowercase hyphenated skill name")
        }
        if let existing = skills().first(where: { $0.name == slug }) {
            guard let text else { throw KnowledgeError("Skill already exists") }
            let before = skillText(slug)
            try text.write(to: existing.url.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            guard text != before else { return }
            try record(KnowledgeChange(
                action: action ?? .update, kind: .skill, target: slug, source: source, before: before.map { .text($0) },
                after: .text(text)), scope: .project)
            return
        }
        let title = slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        let text = text ?? "# \(title)\n\nDescribe when and how the agent should use this project skill.\n"
        try createCanonical(slug, text: text)
        try share(slug)
        try record(KnowledgeChange(
            action: action ?? .add, kind: .skill, target: slug, source: source, before: nil, after: .text(text)),
            scope: .project)
    }

    /// Removes a skill: its `.bashcut/skills` folder and the links to it. A copy only in one agent's folder is not
    /// BashCut's to remove and stays. History keeps the text.
    public func removeSkill(
        named name: String, source: KnowledgeSource = KnowledgeSource(agent: "user"),
        action: KnowledgeChange.Action = .remove
    ) throws {
        guard let (canonical, claude, codex) = skillFolders else { throw Self.noProject }
        let folder = canonical.appendingPathComponent(name, isDirectory: true)
        guard let text = skillText(name), FileManager.default.fileExists(atPath: folder.path) else {
            throw KnowledgeError("No skill named \(name) in .bashcut/skills")
        }
        let manager = FileManager.default
        for parent in [claude, codex] {
            let link = parent.appendingPathComponent(name)
            if let target = try? manager.destinationOfSymbolicLink(atPath: link.path),
               target.hasSuffix(".bashcut/skills/\(name)") {
                try manager.removeItem(at: link)
            }
        }
        try manager.removeItem(at: folder)
        try record(KnowledgeChange(
            action: action, kind: .skill, target: name, source: source, before: .text(text), after: nil),
            scope: .project)
    }

    /// Links a skill for both agents, first copying it into `.bashcut/skills` when it only exists in one agent's
    /// folder.
    public func share(_ name: String) throws {
        guard let (canonical, claude, codex) = skillFolders else { throw Self.noProject }
        let source = canonical.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: source.path) {
            guard let skill = skills().first(where: { $0.name == name }) else {
                throw KnowledgeError("No skill named \(name)")
            }
            try createCanonical(name, text: String(contentsOf: skill.url.appendingPathComponent("SKILL.md"), encoding: .utf8))
        }
        try link(name, into: claude)
        try link(name, into: codex)
    }

    private func createCanonical(_ name: String, text: String) throws {
        guard let (canonical, _, _) = skillFolders else { throw Self.noProject }
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

    // MARK: Migration

    /// The first non-empty memo an older build left in the workspace or home folder.
    public func legacyMemo() -> LegacyKnowledgeMemo? {
        for folder in legacyFolders {
            let url = folder.appendingPathComponent(Self.memoPath)
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            return LegacyKnowledgeMemo(url: url, text: text)
        }
        return nil
    }

    /// Adds the legacy memo to the end of the chosen memo, then renames it to `agent-memory.migrated.md` so it is
    /// not offered again. Returns the new memo text.
    @discardableResult
    public func migrate(
        _ legacy: LegacyKnowledgeMemo, to scope: KnowledgeScope, source: KnowledgeSource = KnowledgeSource(agent: "user")
    ) throws -> String {
        let current = memo(scope).trimmingCharacters(in: .whitespacesAndNewlines)
        let moved = legacy.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = current.isEmpty ? moved + "\n" : current + "\n\n" + moved + "\n"
        try writeMemo(text, scope: scope, source: source)
        let manager = FileManager.default
        let target = legacy.url.deletingLastPathComponent().appendingPathComponent("agent-memory.migrated.md")
        try? manager.removeItem(at: target)
        try manager.moveItem(at: legacy.url, to: target)
        return text
    }
}
