import BashCutAgent
import BashCutAutomation
import BashCutDocument
import SwiftUI

/// The Knowledge window (#68): lessons, preferences and project facts the agents recorded, the memos and the project
/// skills. The section is `ui.knowledgeSection`, so agents can show one with `ui view --knowledge-section`; every
/// change here also has a `knowledge` command.
struct KnowledgeManagerView: View {
    @Bindable var model: AgentKnowledgeModel
    let ui: EditorUIState

    private var section: String { ui.knowledgeSection }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if !model.message.isEmpty || !model.entryErrors.isEmpty {
                    Divider()
                    statusBar
                }
            }
        }
        .frame(minWidth: 860, minHeight: 540)
        .task {
            // Agents change knowledge with commands or by editing the files; show their changes while open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                model.refreshIfChanged()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("KNOWLEDGE").font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 10)
                .padding(.bottom, 6)
            ForEach(UIAction.knowledgeSections, id: \.self) { name in
                Button {
                    ui.knowledgeSection = name
                } label: {
                    HStack(spacing: 6) {
                        Label(LocalizedStringKey(Self.title(name)), systemImage: Self.icon(name))
                        Spacer()
                        let new = model.newCount(name)
                        if new > 0 { KnowledgeNewBadge(text: "\(new)") }
                        if let count = model.count(name) {
                            Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(section == name ? Color.accentColor.opacity(0.25) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(section == name ? Color.primary : Color.secondary)
            }
            Spacer()
            if model.proposalCount > 0 {
                Button {
                    ui.knowledgeSection = "lessons"
                    model.filter.status = .proposed
                } label: {
                    Label(String(format: String(localized: "%d waiting for review"), model.proposalCount),
                          systemImage: "tray.full")
                        .font(.caption)
                }.buttonStyle(.plain).foregroundStyle(.orange).padding(.horizontal, 10)
            }
            Text(model.hasProject ? "This project and every project" : "No saved project: every project only")
                .font(.caption2).foregroundStyle(.secondary).padding(10)
        }.padding(.vertical, 12).padding(.horizontal, 8).frame(width: 210)
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case "prefs": KnowledgeValuesSection(model: model, kind: .prefs)
        case "facts": KnowledgeValuesSection(model: model, kind: .facts)
        case "notes": KnowledgeNotesSection(model: model)
        case "skills": KnowledgeSkillsSection(model: model)
        default: KnowledgeLessonsSection(model: model)
        }
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.entryErrors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if !model.message.isEmpty { Text(model.message).foregroundStyle(.secondary) }
        }.font(.caption).padding(.horizontal, 16).padding(.vertical, 6)
    }

    static func title(_ section: String) -> String {
        switch section {
        case "prefs": "Preferences"
        case "facts": "Project facts"
        case "notes": "Notes"
        case "skills": "Skills"
        default: "Lessons"
        }
    }

    static func icon(_ section: String) -> String {
        switch section {
        case "prefs": "slider.horizontal.3"
        case "facts": "list.bullet.rectangle"
        case "notes": "note.text"
        case "skills": "wand.and.stars"
        default: "lightbulb"
        }
    }
}

// MARK: Lessons

private struct KnowledgeLessonsSection: View {
    @Bindable var model: AgentKnowledgeModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar.padding(12)
            Divider()
            HStack(spacing: 0) {
                list.frame(width: 340)
                Divider()
                Group {
                    if model.draft != nil {
                        KnowledgeLessonEditor(model: model)
                    } else {
                        ContentUnavailableView(
                            "No lesson selected", systemImage: "lightbulb",
                            description: Text("Agents record lessons with knowledge add-lesson. Select one to edit it."))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            TextField("Search lessons", text: $model.filter.query).textFieldStyle(.roundedBorder).frame(minWidth: 160)
            Picker("Scope", selection: $model.filter.scope) {
                Text("All scopes").tag(KnowledgeScope?.none)
                Text("This project").tag(KnowledgeScope?.some(.project))
                Text("Every project").tag(KnowledgeScope?.some(.user))
            }.labelsHidden().fixedSize()
            Picker("Status", selection: $model.filter.status) {
                Text("Any status").tag(LessonStatus?.none)
                ForEach(LessonStatus.allCases, id: \.self) { status in
                    Text(LocalizedStringKey(KnowledgeLessonRow.statusTitle(status))).tag(LessonStatus?.some(status))
                }
            }.labelsHidden().fixedSize()
            Picker("Tag", selection: $model.filter.tag) {
                Text("Any tag").tag(String?.none)
                ForEach(model.lessonTags, id: \.self) { tag in Text(tag).tag(String?.some(tag)) }
            }.labelsHidden().fixedSize()
            Picker("Sort", selection: $model.filter.sort) {
                Text("Newest first").tag(KnowledgeFilter.Sort.newest)
                Text("Oldest first").tag(KnowledgeFilter.Sort.oldest)
            }.labelsHidden().fixedSize()
            Spacer()
            Button("New lesson", systemImage: "plus", action: model.newLesson)
        }
    }

    private var list: some View {
        let lessons = model.filteredLessons
        return Group {
            if lessons.isEmpty {
                ContentUnavailableView(
                    model.lessons.isEmpty ? "No lessons yet" : "No matching lessons", systemImage: "lightbulb.slash")
            } else {
                List(lessons, selection: Binding(get: { model.selectedLessonID }, set: { model.selectLesson($0) })) { lesson in
                    KnowledgeLessonRow(lesson: lesson, new: model.isNew(lesson)).tag(lesson.id)
                        .contextMenu { menu(lesson) }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder private func menu(_ lesson: KnowledgeLesson) -> some View {
        if lesson.status == .proposed {
            Button("Approve") { model.approve(lesson.id) }
            Button("Reject") { model.reject(lesson.id) }
        } else if lesson.status == .active {
            Button("Disable") { model.setStatus(lesson.id, .disabled) }
        } else {
            Button("Enable") { model.setStatus(lesson.id, .active) }
        }
        Divider()
        Button("Delete…", role: .destructive) { model.deleteLesson(lesson.id) }
    }
}

private struct KnowledgeLessonRow: View {
    let lesson: KnowledgeLesson
    let new: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(lesson.title).lineLimit(2).foregroundStyle(lesson.status == .disabled ? .secondary : .primary)
                Spacer(minLength: 4)
                if new { KnowledgeNewBadge(text: String(localized: "New")) }
            }
            HStack(spacing: 6) {
                KnowledgeChip(text: Self.statusTitle(lesson.status), color: Self.statusColor(lesson.status))
                KnowledgeChip(text: KnowledgeSourceLine.scopeTitle(lesson.scope), color: .gray)
                KnowledgeRelativeDate(date: lesson.updated).font(.caption2).foregroundStyle(.secondary)
            }
            if !lesson.fix.isEmpty {
                Text(lesson.fix).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 3)
    }

    static func statusTitle(_ status: LessonStatus) -> String {
        switch status {
        case .proposed: "Proposed"
        case .active: "Active"
        case .disabled: "Disabled"
        }
    }

    static func statusColor(_ status: LessonStatus) -> Color {
        switch status {
        case .proposed: .orange
        case .active: .green
        case .disabled: .gray
        }
    }
}

private struct KnowledgeLessonEditor: View {
    @Bindable var model: AgentKnowledgeModel

    var body: some View {
        if let draft = Binding($model.draft) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header(draft.wrappedValue)
                    TextField("Title", text: draft.title).textFieldStyle(.roundedBorder).font(.title3)
                    field("Symptom", "What went wrong or what was noticed", draft.symptom)
                    field("Cause", "Why it happened", draft.cause)
                    field("What to do next time", "The rule agents follow", draft.fix)
                    field("Evidence", "Frames, files, the user's words", draft.evidence)
                    LabeledContent("Tags") {
                        TextField("captions, audio, pacing", text: draft.tags).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Picker("Status", selection: draft.status) {
                            ForEach(LessonStatus.allCases, id: \.self) { status in
                                Text(LocalizedStringKey(KnowledgeLessonRow.statusTitle(status))).tag(status)
                            }
                        }.fixedSize()
                        if draft.wrappedValue.id == nil {
                            Picker("Scope", selection: draft.scope) {
                                Text("This project").tag(KnowledgeScope.project)
                                Text("Every project").tag(KnowledgeScope.user)
                            }.fixedSize().disabled(!model.hasProject)
                        }
                    }
                    HStack {
                        Button(draft.wrappedValue.id == nil ? "Add lesson" : "Save", action: model.saveDraft)
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(!model.draftChanged || draft.wrappedValue.title
                                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button(draft.wrappedValue.id == nil ? "Cancel" : "Revert", action: model.revertDraft)
                            .disabled(draft.wrappedValue.id != nil && !model.draftChanged)
                    }
                }.padding(16)
            }
        }
    }

    @ViewBuilder private func header(_ draft: LessonDraft) -> some View {
        if let lesson = model.selectedLesson, draft.id != nil {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(lesson.id).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        if model.isNew(lesson) { KnowledgeNewBadge(text: String(localized: "New")) }
                    }
                    KnowledgeSourceLine(source: lesson.source, scope: lesson.scope, updated: lesson.updated)
                }
                Spacer()
                if lesson.status == .proposed {
                    Button("Approve") { model.approve(lesson.id) }.tint(.green)
                    Button("Reject") { model.reject(lesson.id) }
                } else if lesson.status == .active {
                    Button("Disable") { model.setStatus(lesson.id, .disabled) }
                } else {
                    Button("Enable") { model.setStatus(lesson.id, .active) }
                }
                Button("Delete…", systemImage: "trash", role: .destructive) { model.deleteLesson(lesson.id) }
                    .labelStyle(.iconOnly).help("Delete lesson")
            }
        } else {
            Text("New lesson").font(.headline)
        }
    }

    private func field(_ title: LocalizedStringKey, _ prompt: LocalizedStringKey, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            TextField(prompt, text: text, axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: Notes and skills

private struct KnowledgeNotesSection: View {
    @Bindable var model: AgentKnowledgeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let legacy = model.legacy {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Older memo found at \(legacy.url.path). BashCut now keeps knowledge in the project.")
                        .font(.caption)
                    HStack {
                        Button("Move to notes for every project") { model.migrate(to: .user) }
                        Button("Move to this project") { model.migrate(to: .project) }.disabled(!model.hasProject)
                    }
                }.padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.yellow.opacity(0.12)))
            }
            Text("Free text for long notes, such as a style study's measurements. Lessons, preferences and facts belong in their own sections.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project memory").font(.headline)
                    if model.hasProject {
                        TextEditor(text: $model.memo).font(.body).border(.gray.opacity(0.3))
                        Button("Save memo", action: model.saveMemo)
                    } else {
                        Text("Save the project to keep a memo and skills in its folder.")
                            .font(.caption).foregroundStyle(.secondary).frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes for every project").font(.headline)
                    TextEditor(text: $model.userMemo).font(.body).border(.gray.opacity(0.3))
                    Button("Save notes", action: model.saveUserMemo)
                }
            }
        }.padding(16)
    }
}

private struct KnowledgeSkillsSection: View {
    @Bindable var model: AgentKnowledgeModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Project skills").font(.headline)
                List(model.skills, id: \.name, selection: $model.selectedSkill) { skill in
                    Button {
                        model.select(skill.name)
                    } label: {
                        HStack {
                            Text(skill.name)
                            Spacer()
                            if skill.claude { Text("Claude").font(.caption2).foregroundStyle(.purple) }
                            if skill.codex { Text("Codex").font(.caption2).foregroundStyle(.cyan) }
                        }
                    }.buttonStyle(.plain)
                }.frame(width: 250).scrollContentBackground(.hidden)
                HStack {
                    TextField("new-skill-name", text: $model.newSkillName)
                    Button("Add", action: model.createSkill)
                }.disabled(!model.hasProject)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(model.selectedSkill ?? "Select a skill").font(.headline)
                TextEditor(text: $model.skillText).font(.system(size: 12, design: .monospaced))
                    .border(.gray.opacity(0.3))
                HStack {
                    Button("Save skill", action: model.saveSkill).disabled(model.selectedSkill == nil)
                    Button("Share with Claude + Codex", action: model.shareSelectedWithBoth)
                        .disabled(model.selectedSkill == nil)
                }
            }
        }.padding(16)
    }
}
