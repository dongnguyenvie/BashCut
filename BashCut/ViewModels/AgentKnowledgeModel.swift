import BashCutAgent
import Foundation
import Observation

/// The Knowledge window: lessons, preferences and project facts (#68), the project memo and skills, and the user's
/// notes for every project (#100).
@MainActor @Observable final class AgentKnowledgeModel {
    var memo = ""
    var userMemo = ""
    var skills: [AgentKnowledgeSkill] = []
    var selectedSkill: String?
    var skillText = ""
    var newSkillName = ""
    var message = ""
    /// A memo an older build left in the agent workspace or home folder, offered for migration.
    var legacy: LegacyKnowledgeMemo?
    private(set) var store: AgentKnowledgeStore?

    // Structured entries (#68); see AgentKnowledgeModel+Entries.swift.
    var lessons: [KnowledgeLesson] = []
    var prefs: [KnowledgeValue] = []
    var facts: [KnowledgeValue] = []
    /// Files that could not be read.
    var entryErrors: [String] = []
    var filter = KnowledgeFilter()
    /// Text to find in preference and fact keys and values.
    var valueQuery = ""
    var selectedLessonID: String?
    /// The selected lesson's fields while they are edited, or a new lesson before it is saved.
    var draft: LessonDraft?
    /// When the user opened the window before this visit; entries changed after it are marked new.
    var lastVisit: Date?
    /// Entries the user changed in the window during this visit; their own changes are not new to them.
    var changedHere: Set<String> = []
    @ObservationIgnored var signature = ""

    var hasProject: Bool { store?.project != nil }

    var context: String {
        let user = userMemo.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        // Agents may run in a workspace outside the project, so skills are listed with their paths.
        let names = skills.map { "\($0.name) (\($0.url.appendingPathComponent("SKILL.md").path))" }
        var lines = ["[Notes for every project]", user.isEmpty ? "None." : user, "[/Notes for every project]"]
        if hasProject {
            lines += ["[Project memory]", project.isEmpty ? "No memo." : project,
                      "Skills: \(names.isEmpty ? "none" : names.joined(separator: ", "))", "[/Project memory]"]
        } else {
            lines.append("[Project memory] No saved project is open. [/Project memory]")
        }
        if let store { lines.append(store.summary().text) }
        return lines.joined(separator: "\n")
    }

    func load(_ store: AgentKnowledgeStore) {
        self.store = store
        memo = store.memo(.project)
        userMemo = store.memo(.user)
        skills = store.skills()
        legacy = store.legacyMemo()
        loadEntries()
        if let selectedSkill, skills.contains(where: { $0.name == selectedSkill }) {
            select(selectedSkill)
        } else if let first = skills.first {
            select(first.name)
        } else {
            selectedSkill = nil
            skillText = ""
        }
    }

    private func reload() { if let store { load(store) } }

    private func requireStore() throws -> AgentKnowledgeStore {
        guard let store else { throw KnowledgeError("Open the Knowledge window first") }
        return store
    }

    func saveMemo() {
        do {
            try writeMemo(memo, scope: .project)
            message = String(localized: "Project memo saved")
        } catch { message = error.localizedDescription }
    }

    func saveUserMemo() {
        do {
            try writeMemo(userMemo, scope: .user)
            message = String(localized: "Notes for every project saved")
        } catch { message = error.localizedDescription }
    }

    func writeMemo(_ text: String, scope: KnowledgeScope) throws {
        try requireStore().writeMemo(text, scope: scope)
        switch scope {
        case .project: memo = text
        case .user: userMemo = text
        }
    }

    func migrateLegacy(to scope: KnowledgeScope) throws {
        guard let legacy else { throw KnowledgeError("No older memo to move") }
        try requireStore().migrate(legacy, to: scope)
        reload()
    }

    func migrate(to scope: KnowledgeScope) {
        do {
            try migrateLegacy(to: scope)
            message = String(localized: "Older memo moved")
        } catch { message = error.localizedDescription }
    }

    func select(_ name: String) {
        guard let skill = skills.first(where: { $0.name == name }) else { return }
        selectedSkill = name
        skillText = (try? String(contentsOf: skill.url.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
    }

    func createSkill() {
        do {
            try writeSkill(named: newSkillName, text: nil)
            newSkillName = ""
            message = String(localized: "Skill shared with Claude and Codex")
        } catch { message = error.localizedDescription }
    }

    /// Replaces a skill's SKILL.md, or creates the skill and shares it with Claude and Codex.
    func writeSkill(named name: String, text: String?) throws {
        try requireStore().writeSkill(named: name, text: text)
        reload()
        select(name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func saveSkill() {
        guard let selectedSkill else { return }
        do {
            try writeSkill(named: selectedSkill, text: skillText)
            message = String(localized: "Skill saved")
        } catch { message = error.localizedDescription }
    }

    func shareSelectedWithBoth() {
        guard let selectedSkill else { return }
        do {
            try requireStore().share(selectedSkill)
            reload()
            message = String(localized: "Skill available to both agents")
        } catch { message = error.localizedDescription }
    }
}
