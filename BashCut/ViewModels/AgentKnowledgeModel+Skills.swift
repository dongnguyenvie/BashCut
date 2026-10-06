import BashCutAgent
import BashCutDocument
import BashCutPlugin
import Foundation

/// A skill in the Knowledge window: one of this project, one for every project, one a plugin ships (named
/// `<plugin-id>:<name>`) or one of the agent kit. `allCases` is the lookup order of `skills get`.
struct KnowledgeSkillRef: Hashable, Sendable {
    enum Origin: String, CaseIterable, Sendable { case project, user, plugin, kit }
    let origin: Origin
    let name: String

    /// The knowledge scope of a project or user skill; nil for a plugin or kit skill, which are read-only.
    var scope: KnowledgeScope? { KnowledgeScope(rawValue: origin.rawValue) }
    var isReadOnly: Bool { scope == nil }
}

/// A change to a kit skill the user is writing: the kit is read-only, so it becomes a proposal in the inbox.
struct KitProposalDraft: Equatable {
    var summary = ""
    var reason = ""
}

/// The Skills section of the Knowledge window (#71): the kit's skills read-only with "Propose change…", and the
/// user's and the project's skills to edit, preview, turn on or off, share and delete.
extension AgentKnowledgeModel {
    func skills(_ scope: KnowledgeScope) -> [AgentKnowledgeSkill] { scope == .project ? skills : userSkills }

    var selectedSkillEntry: AgentKnowledgeSkill? {
        guard let selectedSkill, let scope = selectedSkill.scope else { return nil }
        return skills(scope).first { $0.name == selectedSkill.name }
    }

    var skillChanged: Bool { skillText != savedSkillText }

    /// The text on disk of a skill, or nil when it is gone.
    func text(of ref: KnowledgeSkillRef) -> String? {
        switch ref.origin {
        case .kit: return kit?.skillText(ref.name)
        case .plugin: return pluginSkill(ref.name).flatMap { try? String(contentsOf: $0.file, encoding: .utf8) }
        case .project, .user: return ref.scope.flatMap { store?.skillText(ref.name, scope: $0) }
        }
    }

    /// A ready plugin's skill by `<plugin-id>:<name>`.
    func pluginSkill(_ id: String) -> PluginSkill? { pluginSkills.first { $0.id == id } }

    /// Every listed skill: this project's, then every project's, then the plugins', then the kit's.
    var skillRefs: [KnowledgeSkillRef] {
        skills.map { KnowledgeSkillRef(origin: .project, name: $0.name) }
            + userSkills.map { KnowledgeSkillRef(origin: .user, name: $0.name) }
            + pluginSkills.map { KnowledgeSkillRef(origin: .plugin, name: $0.id) }
            + (kit?.skills ?? []).map { KnowledgeSkillRef(origin: .kit, name: $0) }
    }

    func loadSkills() {
        guard let store else { return }
        skills = store.skills()
        userSkills = store.skills(.user)
        loadSkillSummaries()
        let first = skills.first.map { KnowledgeSkillRef(origin: .project, name: $0.name) }
            ?? userSkills.first.map { KnowledgeSkillRef(origin: .user, name: $0.name) }
            ?? pluginSkills.first.map { KnowledgeSkillRef(origin: .plugin, name: $0.id) }
            ?? kit?.skills.first.map { KnowledgeSkillRef(origin: .kit, name: $0) }
        selectSkill(selectedSkill.flatMap { text(of: $0) == nil ? nil : $0 } ?? first)
    }

    /// Picks up skills agents added, changed or removed on disk, keeping the user's unsaved edits.
    func refreshSkills() {
        guard let store else { return }
        skills = store.skills()
        userSkills = store.skills(.user)
        loadSkillSummaries()
        guard let selectedSkill else { return }
        guard let text = text(of: selectedSkill) else { return selectSkill(nil) }
        if text != savedSkillText, !skillChanged, kitProposal == nil {
            skillText = text
            savedSkillText = text
        }
    }

    /// The plugins' skills changed: keeps the list current and drops the selection when its skill is gone.
    func refreshPluginSkills() {
        loadSkillSummaries()
        if let selectedSkill, selectedSkill.origin == .plugin, text(of: selectedSkill) == nil { selectSkill(nil) }
    }

    private func loadSkillSummaries() {
        skillSummaries = Dictionary(uniqueKeysWithValues: skillRefs.map { ref in
            (ref, SkillFrontMatter(text(of: ref) ?? "").summary)
        })
    }

    func selectSkill(_ ref: KnowledgeSkillRef?) {
        selectedSkill = ref
        kitProposal = nil
        let text = ref.flatMap(text(of:)) ?? ""
        skillText = text
        savedSkillText = text
        if ref?.isReadOnly == true { skillPreview = true }
    }

    // MARK: Editing

    func createSkill() {
        let scope = hasProject ? newSkillScope : .user
        do {
            try writeSkill(named: newSkillName, text: nil, scope: scope)
            newSkillName = ""
            skillPreview = false
            message = scope == .project
                ? String(localized: "Skill shared with Claude and Codex")
                : String(localized: "Skill added for every project")
        } catch { message = error.localizedDescription }
    }

    /// Replaces a skill's SKILL.md, or creates the skill (a project skill is shared with Claude and Codex).
    func writeSkill(
        named name: String, text: String?, scope: KnowledgeScope = .project,
        source: KnowledgeSource = KnowledgeSource(agent: "user")
    ) throws {
        try requireStore().writeSkill(named: name, text: text, scope: scope, source: source)
        loadSkills()
        selectSkill(KnowledgeSkillRef(
            origin: scope == .project ? .project : .user, name: try AgentKnowledgeStore.skillName(name)))
        loadHistory()
    }

    func saveSkill() {
        guard let selectedSkill, let scope = selectedSkill.scope else { return }
        do {
            try writeSkill(named: selectedSkill.name, text: skillText, scope: scope)
            message = String(localized: "Skill saved")
        } catch { message = error.localizedDescription }
    }

    func discardSkillEdits() {
        skillText = savedSkillText
        kitProposal = nil
    }

    func setSkillEnabled(_ ref: KnowledgeSkillRef, _ enabled: Bool) {
        guard let scope = ref.scope else { return }
        do {
            try requireStore().setSkillEnabled(ref.name, enabled, scope: scope)
            refreshSkills()
            message = enabled ? String(localized: "Skill turned on") : String(localized: "Skill turned off")
        } catch { message = error.localizedDescription }
    }

    func shareWithBoth(_ ref: KnowledgeSkillRef) {
        do {
            try requireStore().share(ref.name)
            refreshSkills()
            message = String(localized: "Skill available to both agents")
        } catch { message = error.localizedDescription }
    }

    /// Asks first, then deletes a project or user skill; history keeps its text.
    func deleteSkill(_ ref: KnowledgeSkillRef) {
        guard let scope = ref.scope else { return }
        let choice = ModalCenter.shared.alert(
            "delete-skill", title: String(format: String(localized: "Delete the skill “%@”?"), ref.name),
            message: String(localized: "Agents stop using it. History keeps a copy, so you can bring it back."),
            buttons: [ModalOption("delete", String(localized: "Delete")), ModalOption("cancel", String(localized: "Cancel"))])
        guard choice == "delete" else { return }
        do {
            try requireStore().removeSkill(named: ref.name, scope: scope)
            if selectedSkill == ref { selectedSkill = nil }
            loadSkills()
            loadHistory()
            message = String(localized: "Skill deleted")
        } catch { message = error.localizedDescription }
    }

    /// Copies a plugin's read-only skill to this project or every project under its own name, where it can be
    /// changed (`skills get` then `skills save` do the same).
    func copyPluginSkill(_ ref: KnowledgeSkillRef, to scope: KnowledgeScope) {
        guard ref.origin == .plugin, let skill = pluginSkill(ref.name), let text = text(of: ref) else { return }
        guard store?.skill(skill.name, scope: scope) == nil else {
            message = String(format: String(localized: "A skill named %@ already exists there"), skill.name)
            return
        }
        do {
            try writeSkill(named: skill.name, text: text, scope: scope)
            skillPreview = false
            message = scope == .project
                ? String(localized: "Skill copied to this project") : String(localized: "Skill copied for every project")
        } catch { message = error.localizedDescription }
    }

    // MARK: Kit proposals

    func beginKitProposal() {
        guard selectedSkill?.origin == .kit else { return }
        kitProposal = KitProposalDraft()
        skillPreview = false
    }

    /// Sends the edited kit skill as a proposal to the inbox and puts the kit's text back.
    func submitKitProposal() {
        guard let selectedSkill, selectedSkill.origin == .kit, let draft = kitProposal else { return }
        let sent = perform(String(localized: "Proposal sent to the Inbox")) { store in
            try store.proposeKitChange(
                skill: selectedSkill.name, before: savedSkillText, after: skillText, summary: draft.summary,
                reason: draft.reason, source: KnowledgeSource(agent: Self.userSource))
        }
        if sent { discardSkillEdits() }
    }
}
