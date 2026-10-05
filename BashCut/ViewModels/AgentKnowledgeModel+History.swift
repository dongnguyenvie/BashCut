import BashCutAgent
import BashCutDocument
import Foundation

/// The History section of the Knowledge window (#70): every recorded change, its diff, and revert.
extension AgentKnowledgeModel {
    static let historyLimit = 500

    var filteredHistory: [KnowledgeChange] {
        history.filter { change in
            (historyKind == nil || change.kind == historyKind) && (filter.scope == nil || change.scope == filter.scope)
        }
    }

    var selectedChange: KnowledgeChange? { history.first { $0.id == selectedChangeID } }

    func loadHistory() {
        history = store?.history(limit: Self.historyLimit) ?? []
        if let selectedChangeID, !history.contains(where: { $0.id == selectedChangeID }) {
            self.selectedChangeID = nil
        }
    }

    /// What a change is about: a lesson's title, a key, a skill's name, or the memo of its scope.
    static func subject(_ change: KnowledgeChange) -> String {
        switch change.kind {
        case .lesson:
            for entry in [change.after, change.before] {
                if case .lesson(let lesson)? = entry { return lesson.title }
            }
            return change.target
        case .memo:
            return change.scope == .project ? String(localized: "Project memory") : String(localized: "Notes for every project")
        default:
            return change.target
        }
    }

    /// Asks first, then puts the entry back to how it was before the change.
    func revertChange(_ id: String) {
        guard let change = history.first(where: { $0.id == id }) else { return }
        let choice = ModalCenter.shared.alert(
            "revert-knowledge-change",
            title: String(format: String(localized: "Revert “%@” to how it was before this change?"), Self.subject(change)),
            message: String(localized: "Later changes to it are undone too. History records the revert, so you can undo it."),
            buttons: [ModalOption("revert", String(localized: "Revert")), ModalOption("cancel", String(localized: "Cancel"))])
        guard choice == "revert" else { return }
        if change.kind == .lesson { changedHere.insert(change.target) }
        var reverted: KnowledgeChange?
        perform(String(localized: "Change reverted")) { store in
            reverted = try store.revert(id, source: KnowledgeSource(agent: Self.userSource))
        }
        // Memos and skills are shown from their files too.
        if let store, change.kind == .memo || change.kind == .skill { load(store) }
        if let reverted { selectedChangeID = reverted.id }
        if let draft, draft.id == change.target, let lesson = selectedLesson { self.draft = LessonDraft(lesson) }
    }
}
