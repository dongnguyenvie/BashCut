import BashCutDocument
import SwiftUI

/// The frame every tool in the Tools panel shares (P1-4): title and provider badge, the main fields, "Advanced (n)",
/// then **Run on** (the targets the tool supports) and Run, and the result under them. The tool supplies the parts;
/// the card draws them the same way for a built-in tool and a plugin's.
struct ToolCard<Main: View, Advanced: View, Result: View>: View {
    let title: String
    let icon: String
    /// The provider or plugin that does the work, as a badge next to the title.
    var provider: String?
    /// Long help, shown as the ⓘ tooltip instead of a paragraph.
    var info: LocalizedStringKey?
    let targets: [ToolTarget]
    @Binding var target: ToolTarget
    /// How many fields are under "Advanced"; the group is hidden at 0.
    var advancedCount = 0
    let runTitle: String
    var canRun = true
    var running = false
    /// 0…1 when the running job reports it.
    var progress: Double?
    var message = ""
    /// False in the batch window, where the card is a step's settings and the batch runs it.
    var showsRunRow = true
    /// "Many projects / files…" under Run on: opens the batch window with this tool and its settings as the first step.
    var runOnMany: (() -> Void)?
    let run: () -> Void
    @ViewBuilder let main: Main
    @ViewBuilder let advanced: Advanced
    @ViewBuilder let result: Result
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label(title, systemImage: icon).font(.headline).lineLimit(1)
                if let info {
                    Image(systemName: "info.circle").foregroundStyle(.secondary).help(info)
                }
                Spacer(minLength: 4)
                if let provider, !provider.isEmpty {
                    Text(verbatim: provider).font(.caption2).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }
            main
            if advancedCount > 0 {
                DisclosureGroup(isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 8) { advanced }.padding(.top, 4)
                } label: {
                    Text("Advanced (\(advancedCount))").font(.callout)
                }
            }
            if showsRunRow {
                Divider()
                runRow
            }
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            result
        }
    }

    private static var manyTarget: String { "many" }

    /// The target picker's choice: a target, or "many", which opens the batch window and keeps the target.
    private var targetChoice: Binding<String> {
        Binding(get: { target.rawValue }, set: { choice in
            if let picked = ToolTarget(rawValue: choice) { target = picked } else { runOnMany?() }
        })
    }

    private var runRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if targets.count > 1 || runOnMany != nil {
                Picker("Run on", selection: targetChoice) {
                    ForEach(targets) { Text(verbatim: $0.title).tag($0.rawValue) }
                    if runOnMany != nil {
                        Divider()
                        Text("Many projects / files…").tag(Self.manyTarget)
                    }
                }
            } else if let only = targets.first {
                LabeledContent("Run on") { Text(verbatim: only.title).foregroundStyle(.secondary) }
            }
            if running, let progress {
                ProgressView(value: progress)
            }
            Button(action: run) {
                Text(verbatim: running ? String(localized: "Working…") : runTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).disabled(!canRun || running)
        }
    }
}

extension ToolCard where Advanced == EmptyView, Result == EmptyView {
    /// A card with only main fields.
    init(
        title: String, icon: String, provider: String? = nil, info: LocalizedStringKey? = nil, targets: [ToolTarget],
        target: Binding<ToolTarget>, runTitle: String, canRun: Bool = true, running: Bool = false, progress: Double? = nil,
        message: String = "", runOnMany: (() -> Void)? = nil, run: @escaping () -> Void, @ViewBuilder main: () -> Main
    ) {
        self.init(
            title: title, icon: icon, provider: provider, info: info, targets: targets, target: target,
            advancedCount: 0, runTitle: runTitle, canRun: canRun, running: running, progress: progress,
            message: message, runOnMany: runOnMany, run: run, main: main, advanced: { EmptyView() },
            result: { EmptyView() })
    }
}

/// The provider a capability's picker shows: the chosen one's name, else the one used automatically.
@MainActor func providerBadge(_ manager: PluginManagerModel, capability: String, chosen: String) -> String? {
    let choices = manager.providers(for: capability)
    let pick = choices.first { $0.provider.id == chosen } ?? choices.first
    return pick?.provider.name
}

/// Picks the provider of a capability and remembers it in the project, like the pickers of the old panel forms.
struct ToolProviderPicker: View {
    @Bindable var document: ProjectDocument
    @Bindable var manager: PluginManagerModel
    let capability: String
    @Binding var provider: String
    let label: String

    var body: some View {
        Picker("Provider", selection: $provider) {
            Text("Automatic").tag("")
            ForEach(manager.providers(for: capability)) { choice in
                Text("\(choice.provider.name) · \(choice.pluginName)").tag(choice.provider.id)
            }
        }
        .onChange(of: provider) { _, value in
            let stored = document.project.preferredProvider(for: capability) ?? ""
            guard value != stored else { return }
            document.apply(
                .setProviderPreference(capability: capability, provider: value.isEmpty ? nil : value), label: label)
        }
        FindPluginButton(document: document, capability: capability)
    }
}
