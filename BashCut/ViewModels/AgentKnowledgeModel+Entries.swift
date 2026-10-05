import BashCutAgent
import BashCutDocument
import Foundation

/// A lesson's fields as the Knowledge window edits them; `id` is nil for a lesson not saved yet.
struct LessonDraft: Equatable {
    var id: String?
    var title = ""
    var symptom = ""
    var cause = ""
    var fix = ""
    var evidence = ""
    /// Comma-separated.
    var tags = ""
    var status: LessonStatus = .active
    var scope: KnowledgeScope = .project

    init(scope: KnowledgeScope) { self.scope = scope }

    init(_ lesson: KnowledgeLesson) {
        id = lesson.id
        title = lesson.title
        symptom = lesson.symptom
        cause = lesson.cause
        fix = lesson.fix
        evidence = lesson.evidence
        tags = lesson.tags.joined(separator: ", ")
        status = lesson.status
        scope = lesson.scope
    }

    var tagList: [String] { tags.split(separator: ",").map(String.init) }

    /// The fields that differ from `lesson`; tags compare after trimming and lowercasing, like the store keeps them.
    func patch(from lesson: KnowledgeLesson) -> LessonPatch {
        let tags = tagList.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        return LessonPatch(
            title: title == lesson.title ? nil : title, symptom: symptom == lesson.symptom ? nil : symptom,
            cause: cause == lesson.cause ? nil : cause, fix: fix == lesson.fix ? nil : fix,
            evidence: evidence == lesson.evidence ? nil : evidence, tags: tags == lesson.tags ? nil : tagList,
            status: status == lesson.status ? nil : status)
    }
}

/// Lessons, preferences and project facts in the Knowledge window (#68). Changes made here are recorded as the
/// user's; the window reloads when agents or people change the files on disk.
extension AgentKnowledgeModel {
    static let userSource = "user"

    var filteredLessons: [KnowledgeLesson] { filter.apply(lessons) }
    var lessonTags: [String] { KnowledgeFilter.tags(lessons) }
    var selectedLesson: KnowledgeLesson? { lessons.first { $0.id == selectedLessonID } }
    var lessonProposals: [KnowledgeLesson] {
        KnowledgeFilter(status: .proposed, sort: .oldest).apply(lessons)
    }
    /// Everything in the inbox: proposed lessons and preference changes.
    var proposalCount: Int { lessons.filter { $0.status == .proposed }.count + valueProposals.count }
    /// Lessons, preferences and facts changed since the last visit, for the dock badge.
    var newTotal: Int { ["lessons", "prefs", "facts"].map(newCount).reduce(0, +) }

    func filteredValues(_ kind: KnowledgeValueKind) -> [KnowledgeValue] {
        KnowledgeFilter(query: valueQuery, scope: kind == .facts ? nil : filter.scope).apply(values(kind))
    }

    func values(_ kind: KnowledgeValueKind) -> [KnowledgeValue] { kind == .prefs ? prefs : facts }

    func isNew(_ lesson: KnowledgeLesson) -> Bool {
        !changedHere.contains(lesson.id) && KnowledgeFilter.isNew(lesson.updated, since: lastVisit)
    }

    func isNew(_ value: KnowledgeValue) -> Bool {
        value.source.agent != Self.userSource && !changedHere.contains(Self.valueID(value.scope, value.key))
            && KnowledgeFilter.isNew(value.source.date, since: lastVisit)
    }

    private static func valueID(_ scope: KnowledgeScope, _ key: String) -> String {
        "\(scope.rawValue):\(key.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// Entries changed since the last visit, per section.
    func newCount(_ section: String) -> Int {
        switch section {
        case "lessons": lessons.filter(isNew).count
        case "prefs": prefs.filter(isNew).count
        case "facts": facts.filter(isNew).count
        default: 0
        }
    }

    func count(_ section: String) -> Int? {
        switch section {
        case "inbox": proposalCount
        case "lessons": lessons.count
        case "prefs": prefs.count
        case "facts": facts.count
        case "skills": skills.count + userSkills.count + (kit?.skills.count ?? 0)
        default: nil
        }
    }

    // MARK: Loading

    func loadEntries() {
        guard let store else { return }
        signature = store.signature()
        var errors: [String] = []
        func read<T>(_ load: () throws -> [T]) -> [T] {
            do { return try load() } catch {
                errors.append(error.localizedDescription)
                return []
            }
        }
        lessons = read { try store.lessons() }
        prefs = read { try store.values(.prefs) }
        facts = read { try store.values(.facts) }
        valueProposals = read { try store.valueProposals() }
        loadHistory()
        entryErrors = errors
        if let selectedLessonID, !lessons.contains(where: { $0.id == selectedLessonID }) {
            self.selectedLessonID = nil
        }
        // Keep unsaved edits; otherwise show the stored fields.
        if let draft, let id = draft.id {
            if let lesson = lessons.first(where: { $0.id == id }) {
                if draft.patch(from: lesson).isEmpty { self.draft = LessonDraft(lesson) }
            } else {
                self.draft = nil
            }
        }
    }

    /// Reloads when a knowledge file changed on disk (an agent's command, or an edit by hand), and the skill list
    /// when skills were added or removed. Memo text is not reloaded here, so an unsaved edit is kept.
    func refreshIfChanged() {
        guard let store else { return }
        if store.skills() != skills || store.skills(.user) != userSkills { refreshSkills() }
        guard store.signature() != signature else { return }
        loadEntries()
    }

    /// Starts a visit: entries changed since the previous one closed are marked new.
    func beginVisit() {
        lastVisit = UserDefaults.standard.object(forKey: visitKey) as? Date
        changedHere = []
        visiting = true
    }

    /// Ends a visit when the window closes: what changed while it was open, the user's own changes included, is not
    /// new next time.
    func endVisit() {
        let now = Date()
        UserDefaults.standard.set(now, forKey: visitKey)
        lastVisit = now
        visiting = false
    }

    var visitKey: String { "knowledgeVisit." + (store?.project?.path ?? "-") }

    // MARK: Lessons

    func selectLesson(_ id: String?) {
        selectedLessonID = id
        draft = selectedLesson.map(LessonDraft.init)
    }

    func newLesson() {
        selectedLessonID = nil
        draft = LessonDraft(scope: hasProject ? .project : .user)
    }

    var draftChanged: Bool {
        guard let draft else { return false }
        guard let id = draft.id else { return true }
        guard let lesson = lessons.first(where: { $0.id == id }) else { return false }
        return !draft.patch(from: lesson).isEmpty
    }

    func revertDraft() {
        if let id = draft?.id { selectLesson(id) } else { draft = nil }
    }

    func saveDraft() {
        guard let draft else { return }
        let saved = perform(String(localized: "Lesson saved")) { store in
            if let id = draft.id {
                guard let lesson = lessons.first(where: { $0.id == id }) else { return }
                let patch = draft.patch(from: lesson)
                guard !patch.isEmpty else { return }
                try store.updateLesson(id, patch, source: source)
                changedHere.insert(id)
                selectedLessonID = id
            } else {
                let lesson = try store.addLesson(
                    title: draft.title, symptom: draft.symptom, cause: draft.cause, fix: draft.fix,
                    evidence: draft.evidence, tags: draft.tagList, status: draft.status, scope: draft.scope,
                    source: source)
                changedHere.insert(lesson.id)
                selectedLessonID = lesson.id
            }
        }
        if saved, let lesson = selectedLesson { self.draft = LessonDraft(lesson) }
    }

    func setStatus(_ id: String, _ status: LessonStatus) {
        changedHere.insert(id)
        perform(status == .disabled ? String(localized: "Lesson disabled") : String(localized: "Lesson enabled")) {
            try $0.updateLesson(id, LessonPatch(status: status), source: source)
        }
        if selectedLessonID == id { draft = selectedLesson.map(LessonDraft.init) }
    }

    func approve(_ id: String) {
        changedHere.insert(id)
        perform(String(localized: "Lesson approved")) { try $0.approve(id, source: source) }
        if selectedLessonID == id { draft = selectedLesson.map(LessonDraft.init) }
    }

    func reject(_ id: String) {
        if selectedLessonID == id { selectLesson(nil) }
        perform(String(localized: "Lesson rejected")) { try $0.reject(id, source: source) }
    }

    /// Asks first; history keeps the removed lesson.
    func deleteLesson(_ id: String) {
        guard let lesson = lessons.first(where: { $0.id == id }) else { return }
        let choice = ModalCenter.shared.alert(
            "delete-lesson", title: String(format: String(localized: "Delete the lesson “%@”?"), lesson.title),
            message: String(localized: "Agents stop following it. History keeps a copy."),
            buttons: [ModalOption("delete", String(localized: "Delete")), ModalOption("cancel", String(localized: "Cancel"))])
        guard choice == "delete" else { return }
        if selectedLessonID == id { selectLesson(nil) }
        perform(String(localized: "Lesson deleted")) { try $0.removeLesson(id, source: source) }
    }

    // MARK: Proposals

    /// Applies an agent's preference change, with the user's edit when `value` is given.
    func approveValue(_ id: String, value: String? = nil) {
        if let proposal = valueProposals.first(where: { $0.id == id }) {
            changedHere.insert(Self.valueID(proposal.scope, proposal.key))
        }
        perform(String(localized: "Preference applied")) { try $0.approveValue(id, value: value, source: source) }
    }

    func rejectValue(_ id: String) {
        perform(String(localized: "Proposal rejected")) { try $0.rejectValue(id, source: source) }
    }

    /// The value a preference proposal would replace, if any.
    func currentValue(_ proposal: KnowledgeValueProposal) -> KnowledgeValue? {
        values(proposal.kind).first { $0.scope == proposal.scope && $0.key == proposal.key }
    }

    // MARK: Values

    /// Sets a preference or fact, or removes it when `value` is nil.
    func setValue(_ kind: KnowledgeValueKind, key: String, value: String?, scope: KnowledgeScope) {
        changedHere.insert(Self.valueID(scope, key))
        perform(value == nil ? String(localized: "Removed") : String(localized: "Saved")) {
            try $0.setValue(kind, key: key, value: value, scope: scope, source: source)
        }
    }

    // MARK: Helpers

    private var source: KnowledgeSource { KnowledgeSource(agent: Self.userSource) }

    /// Runs a change, shows the outcome and reloads; false when it failed.
    @discardableResult
    func perform<T>(_ success: String, _ change: (AgentKnowledgeStore) throws -> T) -> Bool {
        guard let store else { return false }
        defer { loadEntries() }
        do {
            _ = try change(store)
            message = success
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}
