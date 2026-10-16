import BashCutAutomation
import BashCutProject
import Foundation

/// The steps a pipeline may hold (P2-C2): the batch window's "Add step" lists them from here, so a command added to
/// the catalog that a batch may run shows up without a change to the window.
extension BatchRunner {
    /// Why `spec` cannot be a step, nil when it can: approval commands (exports go through the `export` step), project
    /// switches and batch commands.
    public static func stepRefusal(_ spec: CommandSpec) -> String? {
        if spec.execution == .approval || spec.mode == .privileged {
            return "needs the user's approval each time, so it cannot run in a batch"
                + (spec.name == "export.start" ? "; use the export step instead" : "")
        }
        if refusedActions.contains(spec.name) || spec.name.hasPrefix("batch.") {
            return "cannot run in a batch: the runner opens each item's project itself"
        }
        return nil
    }

    /// The catalogued commands "Add step" offers, in catalog order: every command a step may run, except the ones
    /// that only drive the editor's UI (`ui …`). The export step and plugin actions come on top of these.
    public static var stepCommands: [CommandSpec] {
        CommandCatalog.specs.filter { $0.mode != .ui && !$0.name.hasPrefix("ui.") && stepRefusal($0) == nil }
    }

    /// The command a built-in tool of the Tools panel runs as a step (its "Run on › Many projects / files…").
    public static func stepAction(forTool tool: String) -> String? {
        switch tool {
        case ToolID.captions: "captions.generate"
        case ToolID.beats: "beats.detect"
        case ToolID.voice: "voice.speak"
        default: nil
        }
    }

    /// A new step for `action` with the parameters it needs filled where a pipeline can: a required media ID is
    /// `{media}`, a required path `{input}`, and other required ones take their default. The export step exports the
    /// template outputs, else TikTok.
    public static func newStep(_ action: String, label: String? = nil, pipeline: BatchPipeline) -> BatchStep {
        if action == exportAction {
            let presets = pipeline.template.outputs.isEmpty ? ["tiktok"] : pipeline.template.outputs
            return BatchStep(action, params: ["presets": .array(presets.map(JSONValue.string))], label: label)
        }
        var params: [String: JSONValue] = [:]
        for parameter in CommandCatalog.spec(named: action)?.parameters ?? [] where parameter.required {
            if parameter.name == "media" {
                params["media"] = .string("{media}")
            } else if parameter.isPath {
                params[parameter.name] = .string("{input}")
            } else if let value = parameter.defaultValue {
                params[parameter.name] = value
            }
        }
        return BatchStep(action, params: params, label: label)
    }

    /// Parameters a step never shows: the runner fills `baseRev`, and request IDs and dry runs make no sense in a batch.
    public static let hiddenStepParameters: Set<String> = ["baseRev", "requestId", "dryRun"]
}
