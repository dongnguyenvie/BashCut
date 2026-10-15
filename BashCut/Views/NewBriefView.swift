import BashCutAgent
import SwiftUI

/// New brief (⌘K): pick a recent brief, a saved one or a template, fill in its fields, check the request, send it to
/// the open agent. Templates that suit the project are marked and listed first; the others are dimmed.
struct NewBriefView: View {
    @Bindable var document: ProjectDocument
    @Bindable var ask: AgentAskModel
    /// The field whose "other…" chip is being typed in.
    @State private var typingOther: String?
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case search, request, other }

    init(document: ProjectDocument) {
        self.document = document
        ask = document.agents.askModel
    }

    private var agents: AgentDockModel { document.agents }
    private var state: BriefFit { document.briefState }
    private var agentTitle: String? {
        if let id = agents.chatPluginID { return document.chatAgents.model(for: id).title }
        return agents.current?.title
    }
    private var isEmpty: Bool { ask.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            HStack(spacing: 0) {
                BriefListView(ask: ask, state: state).frame(width: 250)
                Divider()
                detail.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            footer.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 860, height: 580)
        .onAppear { focus = .request }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New brief").font(.title2.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Search templates…", text: $ask.search)
                .textFieldStyle(.roundedBorder).frame(width: 220).focused($focus, equals: .search)
        }
    }

    private var subtitle: String {
        let count = document.selectedIDs.count
        let target = count > 1
            ? String(format: String(localized: "%d selected clips"), count)
            : document.selectedID ?? String(localized: "Whole project")
        guard let agentTitle else { return String(localized: "Open an agent in the dock first, then send the brief") }
        return String(format: String(localized: "To %@ · about %@ · ⌘↩ sends"), agentTitle, target)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let template = ask.template {
                HStack(spacing: 10) {
                    Image(systemName: template.systemImage).font(.title2).foregroundStyle(.cyan).frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(template.title).font(.headline)
                        Text(verbatim: "recipe: \(template.recipe)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    ForEach(template.fields) { field in
                        GridRow {
                            Text(field.label).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                            fieldControl(field)
                        }
                    }
                }
            }
            HStack {
                Text(ask.template == nil ? "REQUEST TO SEND" : "REQUEST TO SEND · EDITABLE")
                    .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                Spacer()
                if ask.edited, ask.template != nil {
                    Button("Reset to template", systemImage: "arrow.counterclockwise") { ask.resetToTemplate() }
                        .buttonStyle(.link).font(.caption)
                }
            }.padding(.top, 4)
            TextEditor(text: Binding(get: { ask.draft }, set: { ask.editDraft($0) }))
                .font(.body).focused($focus, equals: .request)
                .scrollContentBackground(.hidden).padding(6)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(dash: [4, 3])))
                .overlay(alignment: .topLeading) {
                    if ask.draft.isEmpty {
                        Text("What should the agent do? Pick a template or write your own.")
                            .foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 90)
            if ask.draft.contains("‹") {
                Text("Replace the parts in ‹…› before sending.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func fieldControl(_ field: BriefField) -> some View {
        if field.isText {
            TextField(field.label.lowercased() + "…", text: Binding(
                get: { ask.values[field.id] ?? "" }, set: { ask.set(field, $0) }))
                .textFieldStyle(.roundedBorder)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(field.options, id: \.self) { option in
                    BriefChip(title: option, on: ask.values[field.id] == option) {
                        ask.set(field, option)
                    }
                }
                otherChip(field)
            }
        }
    }

    /// "other…": a value of the user's own, typed in place of the chip.
    @ViewBuilder private func otherChip(_ field: BriefField) -> some View {
        let own = ask.custom[field.id] ?? ""
        if typingOther == field.id {
            TextField("type your own…", text: Binding(
                get: { own },
                set: { value in
                    ask.custom[field.id] = value
                    ask.set(field, value.isEmpty ? field.defaultValue : value)
                }))
                .textFieldStyle(.roundedBorder).frame(width: 140).focused($focus, equals: .other)
                .onSubmit { typingOther = nil }
                .onExitCommand { typingOther = nil }
        } else {
            BriefChip(title: own.isEmpty ? String(localized: "other…") : own, on: !own.isEmpty && ask.values[field.id] == own,
                      dashed: true) {
                typingOther = field.id
                focus = .other
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle("Attach current frame", isOn: $ask.attachFrame)
            Spacer()
            Button("Save as template", systemImage: "star") { agents.saveBriefAsTemplate() }
                .disabled(isEmpty)
                .help("Keep this request in Saved, for every project")
            Button("Cancel") { document.ui.showAsk = false }.keyboardShortcut(.cancelAction)
            Button(ask.sending ? String(localized: "Preparing frame…") : String(localized: "Send")) {
                Task { await agents.sendAsk() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(isEmpty || ask.sending || !agents.hasOpenAgent)
        }
    }
}

/// A choice in a template field.
struct BriefChip: View {
    let title: String
    let on: Bool
    var dashed = false
    let action: () -> Void

    var body: some View {
        let tint: Color = on ? .cyan : Color.primary.opacity(dashed ? 0.6 : 0.85)
        let fill: Color = on ? Color.cyan.opacity(0.16) : .clear
        let stroke: Color = on ? Color.cyan.opacity(0.7) : Color.white.opacity(0.18)
        let style = StrokeStyle(lineWidth: 1, dash: dashed && !on ? [3, 2] : [])
        return Button(action: action) {
            Text(title).font(.callout).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .foregroundStyle(tint)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(stroke, style: style))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
