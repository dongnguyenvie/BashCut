import BashCutAgent
import SwiftUI

/// The History section of the Knowledge window (#70): changes to lessons, preferences, facts, memos and skills,
/// newest first, each with who made it, a diff and Revert. `knowledge history` / `knowledge revert` do the same from
/// the CLI.
struct KnowledgeHistorySection: View {
    @Bindable var model: AgentKnowledgeModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar.padding(12)
            Divider()
            HStack(spacing: 0) {
                list.frame(width: 340)
                Divider()
                Group {
                    if let change = model.selectedChange {
                        KnowledgeChangeDetail(model: model, change: change)
                    } else {
                        ContentUnavailableView(
                            "No change selected", systemImage: "clock.arrow.circlepath",
                            description: Text("Select a change to see what it did and revert it."))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Picker("Kind", selection: $model.historyKind) {
                Text("Everything").tag(KnowledgeChange.Kind?.none)
                ForEach(KnowledgeChangeRow.kinds, id: \.self) { kind in
                    Text(LocalizedStringKey(KnowledgeChangeRow.kindTitle(kind))).tag(KnowledgeChange.Kind?.some(kind))
                }
            }.labelsHidden().fixedSize()
            Picker("Scope", selection: $model.filter.scope) {
                Text("All scopes").tag(KnowledgeScope?.none)
                Text("This project").tag(KnowledgeScope?.some(.project))
                Text("Every project").tag(KnowledgeScope?.some(.user))
            }.labelsHidden().fixedSize()
            Spacer()
        }
    }

    private var list: some View {
        let changes = model.filteredHistory
        return Group {
            if changes.isEmpty {
                ContentUnavailableView(
                    model.history.isEmpty ? "No changes yet" : "No matching changes", systemImage: "clock")
            } else {
                List(changes, selection: $model.selectedChangeID) { change in
                    KnowledgeChangeRow(change: change).tag(change.id)
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
            }
        }
    }
}

private struct KnowledgeChangeRow: View {
    let change: KnowledgeChange

    static let kinds: [KnowledgeChange.Kind] = [.lesson, .prefs, .facts, .memo, .skill]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AgentKnowledgeModel.subject(change)).lineLimit(2)
            HStack(spacing: 6) {
                KnowledgeChip(text: Self.actionTitle(change.action), color: Self.actionColor(change.action))
                KnowledgeChip(text: Self.kindTitle(change.kind), color: .gray)
                Text(change.source.agent).font(.caption2.bold()).foregroundStyle(.secondary)
                KnowledgeRelativeDate(date: change.source.date).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }

    static func kindTitle(_ kind: KnowledgeChange.Kind) -> String {
        switch kind {
        case .lesson: "Lesson"
        case .prefs: "Preference"
        case .facts: "Project fact"
        case .memo: "Memo"
        case .skill: "Skill"
        }
    }

    static func actionTitle(_ action: KnowledgeChange.Action) -> String {
        switch action {
        case .add: "Added"
        case .update: "Edited"
        case .remove, .unset: "Removed"
        case .approve: "Approved"
        case .reject: "Rejected"
        case .set: "Set"
        case .revert: "Reverted"
        }
    }

    static func actionColor(_ action: KnowledgeChange.Action) -> Color {
        switch action {
        case .add, .approve, .set: .green
        case .remove, .unset, .reject: .red
        case .update: .blue
        case .revert: .purple
        }
    }
}

private struct KnowledgeChangeDetail: View {
    let model: AgentKnowledgeModel
    let change: KnowledgeChange

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            KnowledgeChip(text: KnowledgeChangeRow.actionTitle(change.action),
                                          color: KnowledgeChangeRow.actionColor(change.action))
                            KnowledgeChip(text: KnowledgeChangeRow.kindTitle(change.kind), color: .gray)
                            Text(AgentKnowledgeModel.subject(change)).font(.headline).lineLimit(2)
                        }
                        KnowledgeSourceLine(source: change.source, scope: change.scope, updated: nil)
                        Text(change.id).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button("Revert…", systemImage: "arrow.uturn.backward") { model.revertChange(change.id) }
                        .disabled(!change.isRevertible)
                        .help(change.isRevertible
                            ? String(localized: "Put it back to how it was before this change")
                            : String(localized: "Rejecting a proposal changed nothing to put back"))
                }
                let diff = change.diff
                if diff.isEmpty {
                    Text("Nothing changed in the text.").font(.caption).foregroundStyle(.secondary)
                } else {
                    KnowledgeDiffText(text: diff)
                }
            }.padding(16)
        }
    }
}
