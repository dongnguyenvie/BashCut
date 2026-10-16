import BashCutDocument
import BashCutPlugin
import BashCutProject
import SwiftUI

/// A plugin action placed in `tools` (plugin API 10), drawn as a tool card: its parameters as fields (the `advanced`
/// ones under "Advanced"), then Run on and Run, which starts the same background job as the menu does.
struct PluginToolCard: View {
    @Bindable var document: ProjectDocument
    let action: ContributedAction
    @State private var values: [String: JSONValue]
    @State private var target: ToolTarget
    @State private var jobID: String?
    @State private var message = ""

    init(document: ProjectDocument, action: ContributedAction) {
        self.document = document
        self.action = action
        _values = State(initialValue: (try? action.params.resolve([:])) ?? [:])
        _target = State(initialValue: Self.targets(action).first ?? .project)
    }

    static func targets(_ action: ContributedAction) -> [ToolTarget] {
        ToolTarget.supported(
            whenCondition: action.spec.when, readsTimeline: action.spec.context?.contains(.timeline) == true)
    }

    private var job: Job? { jobID.flatMap { document.jobs.job($0) } }
    private var advanced: [PluginOption] { action.params.filter(\.isAdvanced) }

    var body: some View {
        ToolCard(
            title: action.title, icon: action.spec.icon ?? "puzzlepiece.extension",
            provider: action.plugin.manifest.displayName, info: nil,
            targets: Self.targets(action), target: $target, advancedCount: advanced.count,
            runTitle: String(localized: "Run"), canRun: document.canRunPluginAction(action),
            running: job?.isActive == true, progress: job?.progress, message: message,
            runOnMany: { document.openBatch(BatchStep(action.id, params: values, label: action.title)) }, run: run,
            main: {
                if let confirm = action.spec.confirm { Text(confirm.text).font(.caption).foregroundStyle(.orange) }
                ForEach(action.params.filter { !$0.isAdvanced }) { field($0) }
            },
            advanced: { ForEach(advanced) { field($0) } },
            result: {})
        .onChange(of: job?.state) { _, state in
            switch state {
            case .completed: message = String(localized: "Done")
            case .failed: message = job?.error ?? ""
            case .cancelled: message = String(localized: "Cancelled")
            default: break
            }
        }
    }

    private func field(_ option: PluginOption) -> some View {
        PluginOptionField(option: option, value: Binding(
            get: { values[option.id] ?? option.fallback }, set: { values[option.id] = $0 }))
    }

    private func run() {
        message = ""
        // The card shows the `confirm` text above Run, like the parameter sheet does.
        jobID = document.startPluginActionJob(action.id, params: values, author: .user, confirmed: true)
    }
}

/// A plugin's `kind: tool` view in the Tools panel, under a header with its title and plugin; the view is marked
/// visible while it is on screen, like a view in the plugin's own panel.
struct PluginToolViewCard: View {
    @Bindable var model: PluginViewModel
    let entry: ToolListEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(entry.title, systemImage: entry.icon).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                if let provider = entry.provider {
                    Text(verbatim: provider).font(.caption2).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }
            LazyVStack(alignment: .leading, spacing: 8) { PluginViewRows(model: model) }
        }
        .task(id: model.pluginID + "/" + model.viewID) {
            model.visible = true
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
            model.visible = false
        }
    }
}
