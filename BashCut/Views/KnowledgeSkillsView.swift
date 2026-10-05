import BashCutAgent
import SwiftUI

/// The Skills section of the Knowledge window (#71): this project's skills, the ones for every project and the agent
/// kit's. Project and user skills are edited with a Markdown preview, turned on or off and deleted; kit skills are
/// read-only with "Propose change…". Every action here is also a `skills` command.
struct KnowledgeSkillsSection: View {
    @Bindable var model: AgentKnowledgeModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                list
                Divider()
                addRow.padding(10)
            }.frame(width: 300)
            Divider()
            Group {
                if let ref = model.selectedSkill {
                    KnowledgeSkillDetail(model: model, ref: ref)
                } else {
                    ContentUnavailableView(
                        "No skill selected", systemImage: "wand.and.stars",
                        description: Text("Add a skill for this project or every project, or read the agent kit's."))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var list: some View {
        List(selection: Binding(get: { model.selectedSkill }, set: { model.selectSkill($0) })) {
            if model.hasProject {
                Section("This project") { rows(model.skills, origin: .project) }
            }
            Section("Every project") { rows(model.userSkills, origin: .user) }
            if let kit = model.kit {
                Section(String(format: String(localized: "Agent kit %@"), kit.version)) {
                    ForEach(kit.skills, id: \.self) { name in
                        KnowledgeSkillRow(name: name, summary: model.skillSummaries[KnowledgeSkillRef(origin: .kit, name: name)])
                            .tag(KnowledgeSkillRef(origin: .kit, name: name))
                    }
                }
            }
        }.listStyle(.sidebar).scrollContentBackground(.hidden)
    }

    @ViewBuilder private func rows(_ skills: [AgentKnowledgeSkill], origin: KnowledgeSkillRef.Origin) -> some View {
        if skills.isEmpty {
            Text("None yet").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(skills, id: \.name) { skill in
            let ref = KnowledgeSkillRef(origin: origin, name: skill.name)
            KnowledgeSkillRow(name: skill.name, summary: model.skillSummaries[ref], skill: skill).tag(ref)
                .contextMenu {
                    Button(skill.enabled ? "Turn off" : "Turn on") { model.setSkillEnabled(ref, !skill.enabled) }
                    Divider()
                    Button("Delete…", role: .destructive) { model.deleteSkill(ref) }
                }
        }
    }

    private var addRow: some View {
        HStack(spacing: 6) {
            TextField("new-skill-name", text: $model.newSkillName).textFieldStyle(.roundedBorder)
                .onSubmit(model.createSkill)
            Picker("Scope", selection: $model.newSkillScope) {
                Text("This project").tag(KnowledgeScope.project)
                Text("Every project").tag(KnowledgeScope.user)
            }.labelsHidden().fixedSize().disabled(!model.hasProject)
            Button("Add", action: model.createSkill)
                .disabled(model.newSkillName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

private struct KnowledgeSkillRow: View {
    let name: String
    let summary: String?
    var skill: AgentKnowledgeSkill?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(name).foregroundStyle(skill?.enabled == false ? .secondary : .primary)
                Spacer(minLength: 4)
                if let skill {
                    if !skill.enabled { KnowledgeChip(text: "Off", color: .gray) }
                    if skill.claude { KnowledgeChip(text: "Claude", color: .purple) }
                    if skill.codex { KnowledgeChip(text: "Codex", color: .cyan) }
                }
            }
            if let summary, !summary.isEmpty {
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 2)
    }
}

private struct KnowledgeSkillDetail: View {
    @Bindable var model: AgentKnowledgeModel
    let ref: KnowledgeSkillRef

    private var isKit: Bool { ref.origin == .kit }
    private var editable: Bool { !isKit || model.kitProposal != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Picker("View", selection: $model.skillPreview) {
                Text("Edit").tag(false)
                Text("Preview").tag(true)
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
            if model.skillPreview {
                ScrollView { SkillMarkdownPreview(text: model.skillText).padding(12) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
            } else {
                TextEditor(text: $model.skillText).font(.system(size: 12, design: .monospaced))
                    .border(.gray.opacity(0.3)).disabled(!editable)
            }
            footer
        }.padding(16)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(ref.name).font(.headline)
                    KnowledgeChip(text: scopeTitle, color: isKit ? .indigo : .gray)
                    if let skill = model.selectedSkillEntry, !skill.enabled { KnowledgeChip(text: "Off", color: .gray) }
                }
                if let path {
                    Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if isKit {
                if model.kitProposal == nil {
                    Button("Propose change…", systemImage: "square.and.pencil", action: model.beginKitProposal)
                }
            } else if let skill = model.selectedSkillEntry {
                Toggle("On for agents", isOn: Binding(
                    get: { skill.enabled }, set: { model.setSkillEnabled(ref, $0) }))
                    .toggleStyle(.switch).controlSize(.small)
                if ref.origin == .project, !(skill.claude && skill.codex) {
                    Button("Share with Claude + Codex") { model.shareWithBoth(ref) }
                }
                Button("Delete…", systemImage: "trash", role: .destructive) { model.deleteSkill(ref) }
                    .labelStyle(.iconOnly).help("Delete skill")
            }
        }
    }

    private var scopeTitle: String {
        switch ref.origin {
        case .project: "This project"
        case .user: "Every project"
        case .kit: "Agent kit"
        }
    }

    private var path: String? {
        switch ref.origin {
        case .kit: model.kit?.skillsFolder.appendingPathComponent("\(ref.name)/SKILL.md").path
        default: model.selectedSkillEntry?.file.path
        }
    }

    @ViewBuilder private var footer: some View {
        if isKit {
            if let draft = model.kitProposal {
                let binding = Binding(get: { model.kitProposal ?? draft }, set: { model.kitProposal = $0 })
                VStack(alignment: .leading, spacing: 6) {
                    Text("The kit is read-only. Your change goes to the Inbox as a proposal with its diff.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("What the change does", text: binding.summary).textFieldStyle(.roundedBorder)
                    TextField("Why (what happened)", text: binding.reason).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Send proposal", action: model.submitKitProposal)
                            .disabled(!model.skillChanged
                                || draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Cancel", action: model.discardSkillEdits)
                    }
                }
            } else {
                Text("Kit skills are read-only. Propose a change to send it to the Inbox for review.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Button("Save skill", action: model.saveSkill).keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.skillChanged)
                Button("Revert", action: model.discardSkillEdits).disabled(!model.skillChanged)
            }
        }
    }
}

/// A light Markdown rendering of a SKILL.md: front matter as fields, headings, lists, code blocks and paragraphs
/// with inline styling.
struct SkillMarkdownPreview: View {
    let text: String

    private enum Block: Hashable {
        case heading(Int, String), bullet(String), code(String), paragraph(String)
    }

    var body: some View {
        let front = SkillFrontMatter(text)
        VStack(alignment: .leading, spacing: 8) {
            if !front.fields.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(front.keys, id: \.self) { key in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(key).font(.caption.bold()).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                            Text(front.fields[key] ?? "").font(.caption).textSelection(.enabled)
                        }
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
            }
            ForEach(Array(Self.blocks(front.body).enumerated()), id: \.offset) { _, block in
                view(block)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }

    @ViewBuilder private func view(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text)).font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, 4)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(Self.inline(text))
            }
        case .code(let text):
            Text(text).font(.system(size: 11, design: .monospaced)).padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
        case .paragraph(let text):
            Text(Self.inline(text))
        }
    }

    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private static func blocks(_ body: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) } else { flush() }
                code = code == nil ? [] : nil
            } else if code != nil {
                code?.append(line)
            } else if trimmed.isEmpty {
                flush()
            } else if line.first?.isWhitespace == true, paragraph.isEmpty, case .bullet(let item)? = blocks.last {
                // An indented line continues the list item above it.
                blocks[blocks.count - 1] = .bullet(item + " " + trimmed)
            } else if let block = lineBlock(trimmed, after: blocks.last) {
                flush()
                if case .code = block, case .code(let table)? = blocks.last, table.hasPrefix("|") { blocks.removeLast() }
                blocks.append(block)
            } else {
                paragraph.append(trimmed)
            }
        }
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// A heading, list item or table row; nil for paragraph text. Table rows join the table above them.
    private static func lineBlock(_ line: String, after previous: Block?) -> Block? {
        if line.hasPrefix("#"), let hashes = line.firstIndex(where: { $0 != "#" }), line[hashes] == " " {
            return .heading(line.distance(from: line.startIndex, to: hashes),
                            String(line[hashes...]).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return .bullet(String(line.dropFirst(2))) }
        guard line.hasPrefix("|") else { return nil }
        if case .code(let table)? = previous, table.hasPrefix("|") { return .code(table + "\n" + line) }
        return .code(line)
    }
}
