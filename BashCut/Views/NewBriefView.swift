import BashCutAgent
import SwiftUI

/// New brief (⌘K): pick a recent brief, a saved one or a template, fill in its fields, check the request, pick the
/// agent and send; an agent that is not open starts first. Templates that suit the project are marked and listed
/// first; the others are dimmed.
struct NewBriefView: View {
    @Bindable var document: ProjectDocument
    @Bindable var ask: AgentAskModel
    /// The field whose "other…" chip is being typed in.
    @State private var typingOther: String?
    /// Files are dragged over the sheet.
    @State private var dropping = false
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case search, request, other }

    init(document: ProjectDocument) {
        self.document = document
        ask = document.agents.askModel
    }

    private var agents: AgentDockModel { document.agents }
    private var state: BriefFit { document.briefState }
    private var target: BriefTarget { agents.briefTarget }
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
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cyan, lineWidth: 2)
                    .overlay(alignment: .bottom) {
                        Label("Drop to add as footage", systemImage: "plus.circle.fill")
                            .padding(8).background(.regularMaterial, in: Capsule()).padding(.bottom, 70)
                    }
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            ask.addFootage(urls.filter(\.isFileURL))
            return true
        } isTargeted: { dropping = $0 }
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
        let about = count > 1
            ? String(format: String(localized: "%d selected clips"), count)
            : document.selectedID ?? String(localized: "Whole project")
        return String(format: String(localized: "About %@ · ⌘↩ sends"), about)
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
                    if showsFootage {
                        GridRow {
                            Text("Footage").foregroundStyle(.secondary)
                            footageControl
                        }
                    }
                }
            } else if showsFootage {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Footage").foregroundStyle(.secondary)
                    footageControl
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
            if !ask.footage.isEmpty {
                Text(verbatim: "+ " + BriefFootage.line(ask.footage))
                    .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
            if ask.draft.contains("‹") {
                Text("Replace the parts in ‹…› before sending.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footage

    private var footageNeed: BriefFootage.Need { BriefFootage.need(ask.templateID) }
    private var showsFootage: Bool { footageNeed != .none || !ask.footage.isEmpty }
    private var projectMedia: Int { document.project.media.count }

    /// The project's media, the files and folders added, and Add files or folder…; a nudge when a video made from
    /// footage has none.
    private var footageControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 6) {
                if projectMedia > 0 {
                    Label(String(format: String(localized: "Project media · %d"), projectMedia), systemImage: "film.stack")
                        .font(.callout).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
                        .help("The agent works with the media already in the project")
                }
                ForEach(ask.footage) { footageChip($0) }
                BriefChip(
                    title: footageNeed == .optional && ask.footage.isEmpty
                        ? String(localized: "Add files or folder (optional)…") : String(localized: "Add files or folder…"),
                    on: false, dashed: true
                ) { agents.chooseBriefFootage() }
                .help("Or drop files and folders on this sheet")
            }
            if footageNeed == .main, ask.footage.isEmpty, projectMedia == 0 {
                Text("No footage yet: add what you shot, or drop it here.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func footageChip(_ item: BriefFootage.Item) -> some View {
        HStack(spacing: 5) {
            Image(systemName: item.isFolder ? "folder" : "film").foregroundStyle(.cyan)
            Text(verbatim: item.name).lineLimit(1).truncationMode(.middle)
            if item.isFolder {
                Text(verbatim: "· \(item.mediaFiles)").foregroundStyle(.secondary)
            }
            Button {
                ask.removeFootage(item)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .font(.callout)
        .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 3)
        .background(Capsule().fill(Color.cyan.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.5)))
        .frame(maxWidth: 260)
        .help(item.isFolder
            ? String(format: String(localized: "%@ · %d media files"), item.path, item.mediaFiles) : item.path)
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
            if !ask.status.isEmpty {
                ProgressView().controlSize(.small)
                Text(ask.status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            } else if !ask.error.isEmpty {
                Label(ask.error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).lineLimit(2)
            } else {
                Toggle("Attach current frame", isOn: $ask.attachFrame)
            }
            Spacer()
            Button("Save as template", systemImage: "star") { agents.saveBriefAsTemplate() }
                .disabled(isEmpty)
                .help("Keep this request in Saved, for every project")
            Button("Cancel") {
                ask.sendTask?.cancel()
                document.ui.showAsk = false
            }.keyboardShortcut(.cancelAction)
            targetMenu
            Button(isStart ? String(localized: "Start & send") : String(localized: "Send")) { agents.startSendAsk() }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(isEmpty || ask.sending)
        }
    }

    private var isStart: Bool { if case .start = target { true } else { false } }

    /// "To: Claude Code ▾": the open agent tabs and chat agents, then agents to start in a new tab.
    private var targetMenu: some View {
        let shown = agents.choice(for: target)
        return Menu {
            let open = agents.briefOpenChoices
            if !open.isEmpty {
                Section("Open") { ForEach(open) { targetButton($0) } }
            }
            Section("Start new") { ForEach(agents.briefStartChoices) { targetButton($0) } }
        } label: {
            Label {
                Text(verbatim: shown?.title ?? "")
                    + Text(verbatim: isStart ? " " + String(localized: "· new tab") : "").foregroundStyle(.secondary)
            } icon: {
                Image(systemName: shown?.icon ?? "terminal")
            }
        }
        .fixedSize()
        .disabled(ask.sending)
        .help("Where the brief goes. A new tab starts the agent and sends once it is ready.")
    }

    private func targetButton(_ choice: BriefTargetChoice) -> some View {
        Button {
            ask.target = choice.target
            ask.error = ""
        } label: {
            if choice.target == target {
                Label(choice.title, systemImage: "checkmark")
            } else {
                Label(choice.title, systemImage: choice.icon)
            }
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
