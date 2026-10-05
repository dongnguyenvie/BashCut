import Foundation

/// Where a memo lives: one project, or the user's notes that every project reads.
public enum KnowledgeScope: String, Sendable, CaseIterable {
    case project, user
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
