import BashCutAgent
import SwiftUI

/// The Knowledge inbox (#69): what agents proposed and the user has not decided yet. Proposed lessons (kit change
/// proposals among them, tagged `kit`) and agents' preference changes for every project, each with Approve, Edit
/// and Reject. `knowledge proposals` / `approve` / `reject` do the same from the CLI.
struct KnowledgeInboxSection: View {
    @Bindable var model: AgentKnowledgeModel
    /// Opens a proposed lesson in the Lessons editor.
    let editLesson: (String) -> Void

    var body: some View {
        if model.proposalCount == 0 {
            ContentUnavailableView(
                "Nothing waiting for review", systemImage: "tray",
                description: Text("Lessons agents are unsure about, lessons and preferences for every project, and kit changes wait here."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Agents follow these only after you approve them.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(model.lessonProposals) { lesson in
                        KnowledgeLessonProposalCard(model: model, lesson: lesson) { editLesson(lesson.id) }
                    }
                    ForEach(model.valueProposals) { proposal in
                        KnowledgeValueProposalCard(model: model, proposal: proposal)
                    }
                }.padding(16)
            }
        }
    }
}

private struct KnowledgeLessonProposalCard: View {
    let model: AgentKnowledgeModel
    let lesson: KnowledgeLesson
    let edit: () -> Void

    private var isKitChange: Bool { lesson.tags.contains("kit") }

    var body: some View {
        KnowledgeProposalCard {
            HStack(spacing: 6) {
                KnowledgeChip(text: isKitChange ? "Kit change" : "Lesson", color: isKitChange ? .purple : .orange)
                Text(lesson.title).font(.headline).lineLimit(2)
                Spacer(minLength: 4)
                if model.isNew(lesson) { KnowledgeNewBadge(text: String(localized: "New")) }
            }
            KnowledgeSourceLine(source: lesson.source, scope: lesson.scope, updated: lesson.updated)
            field("Symptom", lesson.symptom)
            field("Cause", lesson.cause)
            if isKitChange, !lesson.fix.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Proposed change").font(.caption.bold()).foregroundStyle(.secondary)
                    KnowledgeDiffText(text: lesson.fix)
                }
            } else {
                field("What to do next time", lesson.fix)
            }
            field("Evidence", lesson.evidence)
            if !lesson.tags.isEmpty {
                Text(lesson.tags.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
            }
        } actions: {
            Button("Approve") { model.approve(lesson.id) }.tint(.green)
            Button("Edit…", action: edit)
            Button("Reject") { model.reject(lesson.id) }
        }
    }

    @ViewBuilder private func field(_ title: LocalizedStringKey, _ text: String) -> some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold()).foregroundStyle(.secondary)
                Text(text).textSelection(.enabled)
            }
        }
    }
}

private struct KnowledgeValueProposalCard: View {
    let model: AgentKnowledgeModel
    let proposal: KnowledgeValueProposal
    @State private var editing = false
    @State private var text = ""

    var body: some View {
        KnowledgeProposalCard {
            HStack(spacing: 6) {
                KnowledgeChip(text: proposal.kind == .prefs ? "Preference" : "Project facts", color: .cyan)
                Text(proposal.key).font(.headline.monospaced()).textSelection(.enabled)
                Spacer(minLength: 4)
            }
            KnowledgeSourceLine(source: proposal.source, scope: proposal.scope, updated: nil)
            if let current = model.currentValue(proposal) {
                LabeledContent("Now") { Text(current.value).strikethrough(proposal.value != nil).textSelection(.enabled) }
            }
            if let value = proposal.value {
                LabeledContent("Proposed") {
                    if editing {
                        TextField("Value", text: $text, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                    } else {
                        Text(value).bold().textSelection(.enabled)
                    }
                }
            } else {
                Text("Remove this preference").foregroundStyle(.orange)
            }
        } actions: {
            Button(editing ? "Apply edited value" : "Approve") {
                model.approveValue(proposal.id, value: editing ? text : nil)
            }.tint(.green).disabled(editing && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if proposal.value != nil {
                Button(editing ? "Cancel edit" : "Edit…") {
                    text = proposal.value ?? ""
                    editing.toggle()
                }
            }
            Button("Reject") { model.rejectValue(proposal.id) }
        }
    }
}

/// A proposal's content above its buttons, on a rounded panel.
private struct KnowledgeProposalCard<Content: View, Actions: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            HStack { actions }.padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
    }
}

/// A unified diff (or any text) with added lines green, removed lines red and hunk headers blue.
struct KnowledgeDiffText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .foregroundStyle(Self.color(line))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Self.color(line).opacity(line.hasPrefix("+") || line.hasPrefix("-") ? 0.1 : 0))
            }
        }
        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
        .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3)))
    }

    static func color(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .secondary }
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        if line.hasPrefix("@@") { return .cyan }
        return .primary
    }
}
