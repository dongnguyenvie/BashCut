import BashCutAgent
import Foundation
import Observation

/// The Knowledge window: lessons, preferences and project facts (#68), the project memo and skills, and the user's
/// notes for every project (#100).
@MainActor @Observable final class AgentKnowledgeModel {
    var memo = ""
    var userMemo = ""
    // Skills (#71); see AgentKnowledgeModel+Skills.swift.
    var skills: [AgentKnowledgeSkill] = []
    var userSkills: [AgentKnowledgeSkill] = []
    /// The agent kit BashCut's agents load, shown read-only; nil when none is found.
    var kit: AgentKit?
    /// Each listed skill's description without its trigger list.
    var skillSummaries: [KnowledgeSkillRef: String] = [:]
    var selectedSkill: KnowledgeSkillRef?
    /// The selected skill's text while it is edited, and as it is on disk.
    var skillText = ""
    var savedSkillText = ""
    var skillPreview = false
    /// A change to the selected kit skill being written; the kit's text is editable only while this is set.
    var kitProposal: KitProposalDraft?
    var newSkillName = ""
    var newSkillScope: KnowledgeScope = .project
    var message = ""
    /// A memo an older build left in the agent workspace or home folder, offered for migration.
    var legacy: LegacyKnowledgeMemo?
    /// Memos with text that were neither split into entries nor kept as notes (#72); see AgentKnowledgeModel+MemoSplit.
    var memoSplitOffers: Set<KnowledgeScope> = []
    /// Puts a request in the agent's input (a terminal or chat agent in the dock); false when none is open.
    @ObservationIgnored var askAgent: ((String) -> Bool)?
    private(set) var store: AgentKnowledgeStore?

    // Structured entries (#68); see AgentKnowledgeModel+Entries.swift.
    var lessons: [KnowledgeLesson] = []
    var prefs: [KnowledgeValue] = []
    var facts: [KnowledgeValue] = []
    /// Agents' preference changes waiting for review (#69).
    var valueProposals: [KnowledgeValueProposal] = []
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
    /// Whether the Knowledge window is open; otherwise `lastVisit` follows the stored visit date for the dock badge.
    var visiting = false
    // History (#70); see AgentKnowledgeModel+History.swift.
    var history: [KnowledgeChange] = []
    var historyKind: KnowledgeChange.Kind?
    var selectedChangeID: String?
    @ObservationIgnored var signature = ""

    var hasProject: Bool { store?.project != nil }

    var context: String {
        let user = userMemo.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        // Agents may run in a workspace outside the project, so skills are listed with their paths; turned-off ones
        // are left out.
        let names = { (skills: [AgentKnowledgeSkill]) -> String in
            let on = skills.filter(\.enabled).map { "\($0.name) (\($0.file.path))" }
            return on.isEmpty ? "none" : on.joined(separator: ", ")
        }
        var lines = ["[Notes for every project]", user.isEmpty ? "None." : user]
        if !userSkills.isEmpty { lines.append("Skills: \(names(userSkills))") }
        lines.append("[/Notes for every project]")
        if memoSplitOffers.contains(.user) { lines.append(Self.splitHint(.user)) }
        if hasProject {
            lines += ["[Project memory]", project.isEmpty ? "No memo." : project]
            if memoSplitOffers.contains(.project) { lines.append(Self.splitHint(.project)) }
            lines += ["Skills: \(names(skills))", "[/Project memory]"]
        } else {
            lines.append("[Project memory] No saved project is open. [/Project memory]")
        }
        if let store { lines.append(store.summary().text) }
        return lines.joined(separator: "\n")
    }

    func load(_ store: AgentKnowledgeStore, kit: AgentKit? = nil) {
        self.store = store
        if let kit { self.kit = kit }
        memo = store.memo(.project)
        userMemo = store.memo(.user)
        legacy = store.legacyMemo()
        if !visiting { lastVisit = UserDefaults.standard.object(forKey: visitKey) as? Date }
        loadEntries()
        loadSkills()
    }

    func reload() { if let store { load(store) } }

    func requireStore() throws -> AgentKnowledgeStore {
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

    func writeMemo(_ text: String, scope: KnowledgeScope, source: KnowledgeSource = KnowledgeSource(agent: "user")) throws {
        try requireStore().writeMemo(text, scope: scope, source: source)
        switch scope {
        case .project: memo = text
        case .user: userMemo = text
        }
        loadMemoSplitOffers()
    }

    func migrateLegacy(to scope: KnowledgeScope, source: KnowledgeSource = KnowledgeSource(agent: "user")) throws {
        guard let legacy else { throw KnowledgeError("No older memo to move") }
        try requireStore().migrate(legacy, to: scope, source: source)
        reload()
    }

    func migrate(to scope: KnowledgeScope) {
        do {
            try migrateLegacy(to: scope)
            message = String(localized: "Older memo moved")
        } catch { message = error.localizedDescription }
    }
}
