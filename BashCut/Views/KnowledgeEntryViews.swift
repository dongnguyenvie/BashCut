import BashCutAgent
import SwiftUI

// MARK: Preferences and facts

/// Preferences or project facts in the Knowledge window (#68): search, edit in place, add and remove.
struct KnowledgeValuesSection: View {
    @Bindable var model: AgentKnowledgeModel
    let kind: KnowledgeValueKind
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var newScope: KnowledgeScope = .user

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField(kind == .prefs ? "Search preferences" : "Search facts", text: $model.valueQuery)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                if kind == .prefs {
                    Picker("Scope", selection: $model.filter.scope) {
                        Text("All scopes").tag(KnowledgeScope?.none)
                        Text("This project").tag(KnowledgeScope?.some(.project))
                        Text("Every project").tag(KnowledgeScope?.some(.user))
                    }.labelsHidden().fixedSize()
                }
                Spacer()
                Text(kind == .prefs
                     ? "The user's taste. A value for this project wins over the one for every project."
                     : "People, places, footage notes and what was approved in this project.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12)
            Divider()
            if kind == .facts, !model.hasProject {
                ContentUnavailableView(
                    "No saved project", systemImage: "folder.badge.questionmark",
                    description: Text("Save the project to keep facts about it."))
            } else {
                rows
                Divider()
                addRow.padding(12)
            }
        }
    }

    private var rows: some View {
        let values = model.filteredValues(kind)
        return Group {
            if values.isEmpty {
                ContentUnavailableView(
                    model.values(kind).isEmpty ? (kind == .prefs ? "No preferences yet" : "No facts yet") : "Nothing matches",
                    systemImage: kind == .prefs ? "slider.horizontal.3" : "list.bullet.rectangle")
            } else {
                List(values, id: \.self) { value in
                    KnowledgeValueRow(model: model, kind: kind, value: value)
                }.scrollContentBackground(.hidden)
            }
        }.frame(maxHeight: .infinity)
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("key", text: $newKey).textFieldStyle(.roundedBorder).frame(width: 180)
            TextField("Value", text: $newValue).textFieldStyle(.roundedBorder).onSubmit(add)
            if kind == .prefs {
                Picker("Scope", selection: $newScope) {
                    Text("Every project").tag(KnowledgeScope.user)
                    Text("This project").tag(KnowledgeScope.project)
                }.labelsHidden().fixedSize().disabled(!model.hasProject)
            }
            Button("Add", action: add)
                .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty || newValue.isEmpty)
        }
    }

    private func add() {
        guard !newKey.trimmingCharacters(in: .whitespaces).isEmpty, !newValue.isEmpty else { return }
        let scope: KnowledgeScope = kind == .facts ? .project : model.hasProject ? newScope : .user
        model.setValue(kind, key: newKey, value: newValue, scope: scope)
        newKey = ""
        newValue = ""
    }
}

struct KnowledgeValueRow: View {
    let model: AgentKnowledgeModel
    let kind: KnowledgeValueKind
    let value: KnowledgeValue
    @State private var text = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(value.key).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1)
                    // On the key's line, so the narrow column never truncates it.
                    if kind == .prefs {
                        KnowledgeChip(text: KnowledgeSourceLine.scopeTitle(value.scope), color: .gray).fixedSize()
                    }
                    if model.isNew(value) { KnowledgeNewBadge(text: String(localized: "New")) }
                }
                KnowledgeSourceLine(source: value.source, scope: nil, updated: nil)
            }.frame(width: 240, alignment: .leading)
            TextField("Value", text: $text, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Button("Save", action: save).disabled(text == value.value)
            Button("Remove", systemImage: "trash") {
                model.setValue(kind, key: value.key, value: nil, scope: value.scope)
            }.labelStyle(.iconOnly).buttonStyle(.borderless).help("Remove")
        }
        .padding(.vertical, 4)
        .onAppear { text = value.value }
        .onChange(of: value) { text = value.value }
    }

    private func save() {
        guard text != value.value else { return }
        model.setValue(kind, key: value.key, value: text, scope: value.scope)
    }
}

// MARK: Parts the Knowledge sections share

/// Who added an entry and when: "claude · session 1a2b… · 3 hours ago".
struct KnowledgeSourceLine: View {
    let source: KnowledgeSource
    let scope: KnowledgeScope?
    let updated: Date?

    var body: some View {
        HStack(spacing: 4) {
            if let scope { KnowledgeChip(text: Self.scopeTitle(scope), color: .gray).fixedSize() }
            Text(source.agent).bold()
            if let session = source.session, !session.isEmpty {
                Text("· \(String(session.prefix(12)))").help(session)
            }
            Text("·")
            KnowledgeRelativeDate(date: source.date)
            if let updated, updated != source.date {
                Text("· edited")
                KnowledgeRelativeDate(date: updated)
            }
        }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }

    static func scopeTitle(_ scope: KnowledgeScope) -> String {
        scope == .project ? String(localized: "This project") : String(localized: "Every project")
    }
}

struct KnowledgeChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(LocalizedStringKey(text)).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.2))).foregroundStyle(color)
    }
}

struct KnowledgeNewBadge: View {
    let text: String

    var body: some View {
        Text(text).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.cyan)).foregroundStyle(.black)
    }
}

/// "3 minutes ago", kept current while the window stays open; the exact date on hover.
struct KnowledgeRelativeDate: View {
    let date: Date

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 15)) { context in
            Text(date.formatted(.relative(presentation: .named))).help(date.formatted()).id(context.date)
        }
    }
}
