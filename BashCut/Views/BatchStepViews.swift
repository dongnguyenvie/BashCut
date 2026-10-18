import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutProject
import SwiftUI

/// The selected step's settings, in the same `ToolCard` frame as the Tools panel so a setting looks the same
/// everywhere: a plugin action's fields from its manifest, a command's from its parameters, the export step's presets.
/// The card runs on many projects here, so it has no Run on row of its own.
struct BatchStepCard: View {
    @Bindable var model: BatchWindowModel
    let index: Int

    /// SwiftUI can draw the card once more after its step is removed (Remove, `ui respond remove-step-N`), before the
    /// window drops it: an empty step then, never an index past the end.
    private var step: BatchStep { model.pipeline.steps.indices.contains(index) ? model.pipeline.steps[index] : BatchStep("") }
    private var spec: CommandSpec? { CommandCatalog.spec(named: step.action) }
    private var action: ContributedAction? { model.document.plugins.action(step.action) }
    private var parameters: [CommandParameter] {
        (spec?.parameters ?? []).filter { !BatchRunner.hiddenStepParameters.contains($0.name) }
    }
    /// The main fields: the required ones, then the first optional ones, four at most unless more are required.
    private var mainCount: Int { max(4, parameters.filter(\.required).count) }
    private var advancedCount: Int {
        if let action { return action.params.filter(\.isAdvanced).count }
        return max(0, parameters.count - mainCount)
    }

    var body: some View {
        ToolCard(
            title: String(format: String(localized: "Step %lld · %@"), index + 1, model.title(step)),
            icon: action?.spec.icon ?? (step.action == BatchRunner.exportAction ? "square.and.arrow.up" : "terminal"),
            provider: action?.plugin.manifest.displayName ?? String(localized: "built-in"),
            info: spec.map { LocalizedStringKey($0.summary) }, targets: [], target: .constant(.project),
            advancedCount: advancedCount, runTitle: "", showsRunRow: false, run: {},
            main: {
                LabeledContent("Label") {
                    TextField(model.title(step), text: Binding(
                        get: { step.label ?? "" },
                        set: { model.setLabel(index, $0.isEmpty ? nil : $0) }))
                    .textFieldStyle(.roundedBorder)
                }
                if step.action == BatchRunner.exportAction {
                    exportFields
                } else if let action {
                    ForEach(action.params.filter { !$0.isAdvanced }) { pluginField($0) }
                } else if spec == nil {
                    Text("No command or installed plugin action has this ID.").font(.caption).foregroundStyle(.orange)
                } else {
                    ForEach(parameters.prefix(mainCount), id: \.name) { BatchParameterField(model: model, parameter: $0) }
                }
                Text("Text fields may use {input}, {name}, {project} and {media}.").font(.caption2).foregroundStyle(.secondary)
            },
            advanced: {
                if let action {
                    ForEach(action.params.filter(\.isAdvanced)) { pluginField($0) }
                } else {
                    ForEach(parameters.dropFirst(mainCount), id: \.name) { BatchParameterField(model: model, parameter: $0) }
                }
            },
            result: {})
    }

    private func pluginField(_ option: PluginOption) -> some View {
        PluginOptionField(option: option, value: Binding(
            get: { model.parameter(option.id) ?? option.fallback }, set: { model.setParameter(option.id, $0) }))
    }

    @ViewBuilder private var exportFields: some View {
        let chosen = BatchRunner.presets(step, model.pipeline)
        Text("Export presets").font(.caption).foregroundStyle(.secondary)
        FlowLayout(spacing: 6) {
            ForEach(OutputPresetName.all, id: \.self) { preset in
                Toggle(preset, isOn: Binding(
                    get: { chosen.contains(preset) },
                    set: { on in
                        let list = on ? chosen + [preset] : chosen.filter { $0 != preset }
                        model.setParameter("presets", .array(list.map(JSONValue.string)))
                    }))
                .toggleStyle(.button).controlSize(.small)
            }
        }
        Toggle("Subtitles file (.srt)", isOn: boolBinding("includeSRT"))
        Toggle("Normalize loudness", isOn: boolBinding("normalizeAudio"))
    }

    private func boolBinding(_ name: String) -> Binding<Bool> {
        Binding(get: { model.parameter(name)?.bool ?? false }, set: { model.setParameter(name, $0 ? .bool(true) : nil) })
    }
}

/// One command parameter as a field: a toggle, a picker of its choices, or text (numbers parsed, lists and objects
/// as JSON). Its summary is the tooltip.
private struct BatchParameterField: View {
    @Bindable var model: BatchWindowModel
    let parameter: CommandParameter
    @State private var text = ""
    @State private var invalid = false

    private var title: String { parameter.name + (parameter.required ? " *" : "") }

    var body: some View {
        Group {
            switch parameter.kind {
            case .boolean:
                Toggle(isOn: Binding(
                    get: { (model.parameter(parameter.name) ?? parameter.defaultValue)?.bool ?? false },
                    set: { model.setParameter(parameter.name, .bool($0)) })
                ) { Text(verbatim: title) }
            case .string where parameter.choices != nil:
                Picker(selection: Binding(
                    get: { model.parameter(parameter.name)?.string ?? "" },
                    set: { model.setParameter(parameter.name, $0.isEmpty ? nil : .string($0)) })
                ) {
                    Text("Default").tag("")
                    ForEach(parameter.choices ?? [], id: \.self) { Text(verbatim: $0).tag($0) }
                } label: { Text(verbatim: title) }
            default:
                LabeledContent {
                    TextField(Self.text(parameter.defaultValue), text: $text)
                        .textFieldStyle(.roundedBorder)
                        .foregroundStyle(invalid ? Color.orange : Color.primary)
                        .onAppear { text = Self.text(model.parameter(parameter.name)) }
                        .onChange(of: text) { commit() }
                } label: { Text(verbatim: title) }
            }
        }
        .help(parameter.summary)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            invalid = false
            model.setParameter(parameter.name, nil)
            return
        }
        let value: JSONValue?
        switch parameter.kind {
        case .integer: value = Int(trimmed).map(JSONValue.integer)
        case .number: value = Double(trimmed).map(JSONValue.number)
        case .array, .object: value = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8))
        default: value = .string(text)
        }
        invalid = value == nil
        if let value { model.setParameter(parameter.name, value) }
    }

    static func text(_ value: JSONValue?) -> String {
        switch value {
        case .string(let text)?: return text
        case .integer(let number)?: return String(number)
        case .number(let number)?: return String(number)
        case .bool(let flag)?: return flag ? "true" : "false"
        case nil, .null?: return ""
        case let value?:
            return (try? JSONEncoder().encode(value)).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        }
    }
}

/// The queue: the run's overall progress, time and Retry, then each item with its step, progress and result, and
/// Open to fix, Reveal, Retry or Cancel.
struct BatchQueueView: View {
    @Bindable var model: BatchWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Queue").font(.headline)
                if let run = model.run {
                    // Ticks so the elapsed and remaining time move between item changes.
                    SwiftUI.TimelineView(.periodic(from: .now, by: 5)) { context in
                        Text(verbatim: BatchQueueStatus.summary(run, now: context.date))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if !run.state.isFinished {
                        ProgressView(value: run.fractionDone).frame(maxWidth: 180)
                    }
                }
                Spacer()
                if let run = model.run, !model.running, !run.retryableItems.isEmpty {
                    let count = run.retryableItems.count
                    Button(run.state == .interrupted
                           ? String(format: String(localized: "Resume (%lld left)"), count)
                           : String(format: String(localized: "Retry Failed (%lld)"), count)) { model.retry() }
                        .disabled(model.checking)
                        .help("Runs these items again from the step that did not complete, in the projects they made")
                        .accessibilityIdentifier("batch-retry")
                }
            }
            header
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let run = model.run {
                        ForEach(Array(run.items.enumerated()), id: \.offset) { index, item in
                            row(index, item, run: run)
                            Divider()
                        }
                    } else {
                        Text("Run the pipeline to fill the queue.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Item").frame(width: 220, alignment: .leading)
            Text("Step").frame(width: 200, alignment: .leading)
            Text("Progress").frame(width: 150, alignment: .leading)
            Text("Result").frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: 250)
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func row(_ index: Int, _ item: BatchItemStatus, run: BatchRunStatus) -> some View {
        let status = BatchQueueStatus(item: item, jobs: model.document.jobs)
        return HStack(spacing: 10) {
            Label(item.source.name, systemImage: item.source.kind == .project ? "film.stack" : "film")
                .lineLimit(1).truncationMode(.middle).frame(width: 220, alignment: .leading)
            Text(verbatim: status.step.map { "\($0 + 1) · \(model.title(run.pipeline.steps[$0]))" } ?? "—")
                .lineLimit(1).frame(width: 200, alignment: .leading)
            Group {
                if item.state == .running {
                    ProgressView(value: status.progress)
                } else {
                    Text(verbatim: BatchQueueStatus.stateTitle(item.state)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, alignment: .leading)
            Text(verbatim: status.result).foregroundStyle(status.attention ? Color.orange : Color.primary)
                .lineLimit(2).help(item.error.map { BatchMessage.localized($0) } ?? status.result).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if item.state == .running {
                    Button("Cancel", action: model.cancel)
                } else if !model.running, run.retryableItems.contains(index), item.state != .waiting {
                    Button("Retry") { model.retry([index]) }.disabled(model.checking)
                        .accessibilityIdentifier("batch-retry-\(index + 1)")
                }
                if item.state != .running, item.project != nil {
                    Button(status.attention ? String(localized: "Open to fix") : String(localized: "Open")) {
                        model.openItem(index)
                    }
                    .disabled(model.running).help(model.running ? "The batch is still running" : "Open in the editor")
                    .accessibilityIdentifier("batch-open-\(index + 1)")
                    Button("Reveal") { model.revealItem(index) }
                }
            }
            .controlSize(.small).frame(width: 250, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .font(.callout)
    }
}
