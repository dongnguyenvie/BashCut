import BashCutAutomation
import BashCutProject
import Foundation

/// The steps a pipeline may hold (P2-C2): the batch window's "Add step" lists them from here, so a command added to
/// the catalog that a batch may run shows up without a change to the window.
extension BatchRunner {
    /// Why `spec` cannot be a step, as a `BatchMessages.step` key; nil when it can: approval commands (exports go
    /// through the `export` step), project switches and batch commands.
    public static func stepRefusal(_ spec: CommandSpec) -> String? {
        if spec.execution == .approval || spec.mode == .privileged {
            return spec.name == "export.start" ? BatchMessages.approvalExport : BatchMessages.approval
        }
        if refusedActions.contains(spec.name) || spec.name.hasPrefix("batch.") {
            return BatchMessages.opensProjects
        }
        return nil
    }

    /// The catalogued commands "Add step" offers, in catalog order: every command a step may run, except the ones
    /// that only drive the editor's UI (`ui …`). The export step and plugin actions come on top of these.
    public static var stepCommands: [CommandSpec] {
        CommandCatalog.specs.filter { $0.mode != .ui && !$0.name.hasPrefix("ui.") && stepRefusal($0) == nil }
    }

    /// The command each built-in tool of the Tools panel runs as a step (its "Run on › Many projects / files…").
    public static let toolActions: [String: String] = [
        ToolID.captions: "captions.generate", ToolID.beats: "beats.detect", ToolID.voice: "voice.speak",
    ]

    public static func stepAction(forTool tool: String) -> String? { toolActions[tool] }

    /// A new step running built-in `tool` with the card's current settings (`params`) over `newStep`'s.
    public static func toolStep(_ tool: String, label: String, params: [String: JSONValue] = [:]) -> BatchStep? {
        toolActions[tool].map { newStep($0, label: label, params: params) }
    }

    /// A new step for `action`: the catalog entry's starter parameters (`BatchStepCatalog`), then the required ones
    /// filled where a pipeline can — a media ID is `{media}`, a path `{input}`, others take their default — and
    /// `params` on top. The export step without presets exports the template outputs, else TikTok.
    public static func newStep(_ action: String, label: String? = nil, params overrides: [String: JSONValue] = [:],
                               pipeline: BatchPipeline? = nil) -> BatchStep {
        var params = BatchStepCatalog.entry(action)?.params ?? [:]
        if action == exportAction, params["presets"] == nil {
            let outputs = pipeline?.template.outputs ?? []
            params["presets"] = .array((outputs.isEmpty ? ["tiktok"] : outputs).map(JSONValue.string))
        }
        for parameter in CommandCatalog.spec(named: action)?.parameters ?? []
        where parameter.required && params[parameter.name] == nil {
            if parameter.name == "media" {
                params["media"] = .string("{media}")
            } else if parameter.isPath {
                params[parameter.name] = .string("{input}")
            } else if let value = parameter.defaultValue {
                params[parameter.name] = value
            }
        }
        params.merge(overrides) { $1 }
        return BatchStep(action, params: params, label: label)
    }

    /// Parameters a step never shows: the runner fills `baseRev`, and request IDs and dry runs make no sense in a batch.
    public static let hiddenStepParameters: Set<String> = ["baseRev", "requestId", "dryRun"]
}
