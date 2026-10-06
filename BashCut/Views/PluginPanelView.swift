import AppKit
import BashCutDocument
import BashCutPlugin
import BashCutProject
import SwiftUI

/// A plugin's panel in the library column (plugin API 8): the same frame for every plugin, drawn from its manifest
/// (header, view picker, Tools, Skills, Requires, Uses, Settings), around the plugin's declarative view.
struct PluginPanelView: View {
    @Bindable var document: ProjectDocument
    let plugin: InstalledPlugin

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                // One lazy column for the whole panel: only the components on screen are built, so a view with
                // thousands of components costs what its visible part costs.
                LazyVStack(alignment: .leading, spacing: 8) {
                    let views = plugin.manifest.views
                    if views.count > 1 {
                        Picker("View", selection: Binding(
                            get: { document.pluginPanelView(plugin)?.id ?? "" },
                            set: { document.showPluginPanel(plugin.id, view: $0) }
                        )) {
                            ForEach(views) { view in Text(verbatim: view.title.text).tag(view.id) }
                        }.labelsHidden().pickerStyle(.segmented)
                    }
                    if let model = selectedModel {
                        PluginViewRows(model: model)
                    }
                    PluginPanelManager(document: document, plugin: plugin).padding(.top, 4)
                }.padding(10)
            }
            .task(id: selectedModel.map { $0.pluginID + "/" + $0.viewID }) {
                // The view is visible while this task lives: it ends when the panel closes or shows another view.
                guard let model = selectedModel else { return }
                model.visible = true
                while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
                model.visible = false
            }
        }.background(Color.white.opacity(0.025))
    }

    private var selectedModel: PluginViewModel? {
        document.pluginPanelView(plugin).map { document.pluginViews.model(plugin: plugin.id, view: $0.id) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: plugin.manifest.container?.icon ?? "puzzlepiece.extension").foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: plugin.manifest.containerTitle).font(.headline).lineLimit(1)
                Text(verbatim: plugin.manifest.displayName + " " + plugin.manifest.version)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button {
                document.ui.settingsSection = "plugins"
                document.ui.showSettings = true
            } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Plugin settings")
        }.padding(10)
    }
}

/// The parts every plugin panel has: its actions as Tools, its skills, what it requires and the capabilities it uses.
private struct PluginPanelManager: View {
    @Bindable var document: ProjectDocument
    let plugin: InstalledPlugin
    @State private var expanded = true

    var body: some View {
        let tools = document.plugins.actions.filter { $0.plugin.id == plugin.id }
        let skills = document.plugins.skills(of: plugin)
        let requirements = document.plugins.requirementsJSON(plugin).array
        let unprovided = document.unprovidedCapabilities(plugin)
        if !tools.isEmpty || !skills.isEmpty || !requirements.isEmpty || !plugin.manifest.usedCapabilities.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if !tools.isEmpty {
                        label("Tools", "hammer")
                        ForEach(tools) { action in
                            Button {
                                document.triggerPluginAction(action)
                            } label: {
                                Label(action.title, systemImage: action.spec.icon ?? "play")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.disabled(!document.canRunPluginAction(action))
                        }
                    }
                    if !skills.isEmpty {
                        label("Skills", "book")
                        ForEach(skills) { skill in
                            Text(verbatim: skill.name).font(.caption).help(skill.description)
                        }
                    }
                    if !requirements.isEmpty {
                        label("Requires", "link")
                        ForEach(Array(requirements.enumerated()), id: \.offset) { _, entry in
                            let fields = entry.object
                            let ready = fields["state"]?.string == "ready"
                            HStack(spacing: 4) {
                                Image(systemName: ready ? "checkmark.circle" : "exclamationmark.triangle")
                                    .foregroundStyle(ready ? .green : .orange)
                                Text(verbatim: (fields["id"]?.string ?? "") + " " + (fields["version"]?.string ?? ""))
                            }.font(.caption)
                        }
                    }
                    if !plugin.manifest.usedCapabilities.isEmpty {
                        label("Uses", "arrow.triangle.branch")
                        ForEach(plugin.manifest.usedCapabilities, id: \.self) { capability in
                            HStack(spacing: 4) {
                                Image(systemName: unprovided.contains(capability) ? "exclamationmark.triangle" : "checkmark.circle")
                                    .foregroundStyle(unprovided.contains(capability) ? .orange : .green)
                                Text(verbatim: capability).font(.caption)
                                Spacer()
                                if unprovided.contains(capability) {
                                    Button("Find…") { document.showPluginBrowser(capability: capability) }
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }.padding(.top, 4)
            } label: {
                Text("Plugin").font(.caption.bold()).foregroundStyle(.secondary)
            }
        }
    }

    private func label(_ title: LocalizedStringKey, _ icon: String) -> some View {
        Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(.secondary)
    }
}

/// A plugin view as rows of the panel's lazy column: its title, an error, then its top-level components.
struct PluginViewRows: View {
    @Bindable var model: PluginViewModel

    var body: some View {
        if let title = model.tree?.title {
            HStack {
                Text(verbatim: title).font(.subheadline.bold())
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
        } else if model.busy {
            ProgressView().controlSize(.small)
        }
        if let error = model.error {
            VStack(alignment: .leading, spacing: 4) {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    .textSelection(.enabled)
                Button("Try Again") { model.load() }.controlSize(.small)
            }
        }
        if let tree = model.tree {
            ForEach(tree.body) { node in PluginNodeView(node: node, model: model) }
        }
    }
}

/// Components in a column.
struct PluginNodesView: View {
    let nodes: [PluginViewNode]
    let model: PluginViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(nodes) { node in PluginNodeView(node: node, model: model) }
        }
    }
}

/// One component, drawn natively. Plugin text is shown verbatim (it is the plugin's content, not app UI).
struct PluginNodeView: View {
    let node: PluginViewNode
    @Bindable var model: PluginViewModel

    var body: some View {
        switch node.kind {
        case .section: PluginSectionView(node: node, model: model)
        case .row:
            HStack(spacing: node.double("spacing").map { CGFloat($0) } ?? 6) {
                ForEach(node.children) { child in PluginNodeView(node: child, model: model) }
            }
        case .divider: Divider()
        case .spacer: Spacer(minLength: node.double("size").map { CGFloat($0) } ?? 4)
        case .text: text
        case .badge:
            Text(verbatim: node.string("text") ?? "").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Self.color(node.string("color")).opacity(0.2), in: Capsule())
                .foregroundStyle(Self.color(node.string("color")))
        case .keyValue:
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                ForEach(Array(node.array("items").prefix(100).enumerated()), id: \.offset) { _, item in
                    GridRow {
                        Text(verbatim: item.object["key"]?.string ?? "").foregroundStyle(.secondary)
                        Text(verbatim: item.object["value"]?.string ?? "").textSelection(.enabled)
                    }
                }
            }.font(.caption)
        case .progress:
            if let value = node.double("value") {
                ProgressView(value: min(max(value, 0), 1)) { label }
            } else {
                ProgressView { label }.controlSize(.small)
            }
        case .image: PluginImageView(path: node.string("path"), height: node.double("height"), caption: node.string("caption"))
        case .imageCompare: PluginImageCompare(node: node)
        case .audio: PluginAudioButton(path: node.string("path"), title: node.string("title"))
        case .list: PluginListView(node: node, model: model)
        case .button: button
        case .textField: PluginTextField(node: node, model: model)
        case .textArea: textArea
        case .toggle:
            Toggle(isOn: Binding(
                get: { model.values[node.id]?.bool ?? false },
                set: { model.send(PluginViewEvent(node: node.id, kind: .change, value: .bool($0))) }
            )) { Text(verbatim: node.string("label") ?? "") }
                .disabled(node.bool("disabled"))
        case .picker: picker
        case .slider: PluginSliderView(node: node, model: model)
        case nil:
            Label(String(format: String(localized: "Needs a newer BashCut: %@"), node.type), systemImage: "puzzlepiece")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var label: some View {
        Text(verbatim: node.string("label") ?? "").font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var text: some View {
        let value = node.string("text") ?? ""
        let styled: Text = if node.bool("markdown"),
            let attributed = try? AttributedString(
                markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
        } else {
            Text(verbatim: value)
        }
        switch node.string("style") {
        case "title": styled.font(.title3.bold())
        case "heading": styled.font(.headline)
        case "caption": styled.font(.caption).foregroundStyle(Self.color(node.string("color"), fallback: .secondary))
        case "mono": styled.font(.caption.monospaced()).textSelection(.enabled)
        case "secondary": styled.font(.callout).foregroundStyle(.secondary)
        default: styled.font(.callout).foregroundStyle(Self.color(node.string("color"), fallback: .primary))
        }
    }

    @ViewBuilder private var button: some View {
        let control = Button {
            if let confirm = node.string("confirm") {
                let choice = ModalCenter.shared.alert(
                    "plugin-view-confirm", title: confirm,
                    buttons: [ModalOption("continue", String(localized: "Continue")),
                              ModalOption("cancel", String(localized: "Cancel"))])
                guard choice == "continue" else { return }
            }
            model.send(PluginViewEvent(node: node.id, kind: .click))
        } label: {
            if let icon = node.string("icon") {
                Label(node.string("title") ?? "", systemImage: icon).frame(maxWidth: node.bool("wide") ? .infinity : nil)
            } else {
                Text(verbatim: node.string("title") ?? "").frame(maxWidth: node.bool("wide") ? .infinity : nil)
            }
        }.disabled(node.bool("disabled"))
        switch node.string("style") {
        case "primary": control.buttonStyle(.borderedProminent)
        case "destructive": control.buttonStyle(.bordered).tint(.red)
        case "link": control.buttonStyle(.link)
        default: control
        }
    }

    private var textArea: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label = node.string("label") { Text(verbatim: label).font(.caption).foregroundStyle(.secondary) }
            PluginTextEditor(node: node, model: model)
        }
    }

    private var picker: some View {
        let options = node.array("options").prefix(PluginViewTree.maximumOptions)
        return Picker(selection: Binding(
            get: { model.values[node.id]?.string ?? "" },
            set: { model.send(PluginViewEvent(node: node.id, kind: .change, value: .string($0))) }
        )) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let value = option.object["value"]?.string ?? option.string ?? ""
                Text(verbatim: option.object["label"]?.string ?? value).tag(value)
            }
        } label: { Text(verbatim: node.string("label") ?? "") }
            .disabled(node.bool("disabled"))
    }

    static func color(_ name: String?, fallback: Color = .cyan) -> Color {
        switch name {
        case "green": .green
        case "orange": .orange
        case "red": .red
        case "secondary": .secondary
        case "accent": .cyan
        case "purple": .purple
        default: fallback
        }
    }
}

private struct PluginSectionView: View {
    let node: PluginViewNode
    let model: PluginViewModel
    @State private var expanded: Bool

    init(node: PluginViewNode, model: PluginViewModel) {
        self.node = node
        self.model = model
        _expanded = State(initialValue: !node.bool("collapsed"))
    }

    var body: some View {
        if let title = node.string("title") {
            DisclosureGroup(isExpanded: $expanded) {
                PluginNodesView(nodes: node.children, model: model).padding(.top, 4)
            } label: {
                Text(verbatim: title).font(.caption.bold()).foregroundStyle(.secondary)
            }
        } else {
            PluginNodesView(nodes: node.children, model: model)
        }
    }
}

/// A text field. With `search`, changes go out 300 ms after typing stops; otherwise when Return is pressed or the
/// field loses focus.
private struct PluginTextField: View {
    let node: PluginViewNode
    @Bindable var model: PluginViewModel
    @State private var text = ""
    @State private var debounce: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label = node.string("label") { Text(verbatim: label).font(.caption).foregroundStyle(.secondary) }
            TextField(node.string("placeholder") ?? "", text: $text)
                .textFieldStyle(.roundedBorder)
                .disabled(node.bool("disabled"))
                .onSubmit {
                    debounce?.cancel()
                    model.send(PluginViewEvent(node: node.id, kind: .change, value: .string(text)))
                    if node.bool("submit") { model.send(PluginViewEvent(node: node.id, kind: .submit, value: .string(text))) }
                }
                .onChange(of: text) { _, value in
                    guard value != (model.values[node.id]?.string ?? "") else { return }
                    debounce?.cancel()
                    if node.bool("search") {
                        debounce = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            model.send(PluginViewEvent(node: node.id, kind: .change, value: .string(value)))
                        }
                    } else {
                        model.values[node.id] = .string(value)
                    }
                }
        }
        .onAppear { text = model.values[node.id]?.string ?? "" }
        .onChange(of: model.values[node.id]) { _, value in
            if let value = value?.string, value != text { text = value }
        }
    }
}

/// Multi-line text; the value goes with the next event (no event per keystroke).
private struct PluginTextEditor: View {
    let node: PluginViewNode
    @Bindable var model: PluginViewModel

    var body: some View {
        TextEditor(text: Binding(
            get: { model.values[node.id]?.string ?? "" }, set: { model.values[node.id] = .string($0) }
        ))
        .font(.callout)
        .frame(height: min(max(node.double("height") ?? 80, 40), 400))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
        .disabled(node.bool("disabled"))
    }
}

/// A slider that sends its value when the drag ends.
private struct PluginSliderView: View {
    let node: PluginViewNode
    @Bindable var model: PluginViewModel
    @State private var value = 0.0

    var body: some View {
        let low = node.double("min") ?? 0
        let high = max(node.double("max") ?? 1, low + 0.000_001)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: node.string("label") ?? "").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(0...2))).font(.caption.monospacedDigit())
            }
            Group {
                if let step = node.double("step"), step > 0 {
                    Slider(value: $value, in: low...high, step: step) { editing in send(editing) }
                } else {
                    Slider(value: $value, in: low...high) { editing in send(editing) }
                }
            }.disabled(node.bool("disabled"))
        }
        .onAppear { value = model.values[node.id]?.double ?? low }
        .onChange(of: model.values[node.id]) { _, next in if let next = next?.double { value = next } }
    }

    private func send(_ editing: Bool) {
        guard !editing else { return }
        model.send(PluginViewEvent(node: node.id, kind: .change, value: .number(value)))
    }
}

/// A list of rows (lazy, so long lists cost only the rows on screen). A row may have a subtitle, an SF Symbol icon,
/// a badge, a thumbnail and buttons.
private struct PluginListView: View {
    let node: PluginViewNode
    @Bindable var model: PluginViewModel

    var body: some View {
        let items = Array(node.array("items").prefix(PluginViewTree.maximumListItems))
        let selected = node.string("selected")
        if items.isEmpty, let empty = node.string("empty") {
            Text(verbatim: empty).font(.caption).foregroundStyle(.secondary)
        }
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                row(item.object, selected: selected)
            }
        }
    }

    private func row(_ item: [String: JSONValue], selected: String?) -> some View {
        let id = item["id"]?.string ?? ""
        return HStack(spacing: 6) {
            if let thumbnail = item["image"]?.string {
                PluginImageView(path: thumbnail, height: 28, caption: nil).frame(width: 40)
            } else if let icon = item["icon"]?.string {
                Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: item["title"]?.string ?? id).font(.callout).lineLimit(1)
                if let subtitle = item["subtitle"]?.string {
                    Text(verbatim: subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let badge = item["badge"]?.string {
                Text(verbatim: badge).font(.caption2).foregroundStyle(.secondary)
            }
            if let audio = item["audio"]?.string { PluginAudioButton(path: audio, title: nil, compact: true) }
            ForEach(Array((item["actions"]?.array ?? []).prefix(3).enumerated()), id: \.offset) { _, action in
                let fields = action.object
                Button {
                    model.send(PluginViewEvent(node: node.id, kind: .action, value: .object([
                        "item": .string(id), "action": fields["id"] ?? .null,
                    ])))
                } label: {
                    if let icon = fields["icon"]?.string { Image(systemName: icon) } else {
                        Text(verbatim: fields["title"]?.string ?? "")
                    }
                }.buttonStyle(.borderless).help(fields["title"]?.string ?? "")
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
        .background(selected == id ? Color.cyan.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { model.send(PluginViewEvent(node: node.id, kind: .select, value: .string(id))) }
    }
}
