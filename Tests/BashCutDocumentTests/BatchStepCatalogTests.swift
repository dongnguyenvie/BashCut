import BashCutAutomation
import BashCutDocument
import BashCutProject
import Testing

/// The steps the batch window's "Add step" offers (P2-C2) and the step a new one starts as.
@MainActor
struct BatchStepCatalogTests {
    @Test("Add step lists every catalogued command a batch may run, and only those")
    func stepCommands() throws {
        let names = Set(BatchRunner.stepCommands.map(\.name))
        #expect(names.isSuperset(of: ["captions.generate", "beats.detect", "voice.speak", "review.run", "media.import"]))
        #expect(names.isDisjoint(with: BatchRunner.refusedActions))
        #expect(!names.contains("export.start"))
        #expect(!names.contains { $0.hasPrefix("batch.") || $0.hasPrefix("ui.") })
        // Every listed command passes the runner's check as a step.
        for spec in BatchRunner.stepCommands {
            let pipeline = BatchPipeline(inputs: [BatchInput(path: "/")], steps: [BatchStep(spec.name)])
            try BatchRunner.check(pipeline) { _ in false }
        }
        // A command the catalog marks for approval is refused with the same reason check gives.
        let approval = try #require(CommandCatalog.specs.first { $0.execution == .approval })
        #expect(BatchRunner.stepRefusal(approval)?.contains("approval") == true)
    }

    @Test("A new step fills the media and paths a pipeline knows; export takes the template outputs")
    func newStep() {
        var pipeline = BatchPipeline(inputs: [], steps: [])
        #expect(BatchRunner.newStep("captions.generate", pipeline: pipeline).params["media"] == .string("{media}"))
        #expect(BatchRunner.newStep("media.import", pipeline: pipeline).params["path"] == .string("{input}"))
        #expect(BatchRunner.newStep("review.run", label: "Review", pipeline: pipeline).label == "Review")
        #expect(BatchRunner.newStep(BatchRunner.exportAction, pipeline: pipeline).params["presets"] == .array([.string("tiktok")]))
        pipeline.template.outputs = ["shorts", "reels"]
        let export = BatchRunner.newStep(BatchRunner.exportAction, pipeline: pipeline)
        #expect(BatchRunner.presets(export, pipeline) == ["shorts", "reels"])
    }

    @Test("Each built-in tool runs as a step command")
    func toolSteps() {
        for tool in ToolID.builtIn {
            let action = BatchRunner.stepAction(forTool: tool)
            #expect(action.flatMap(CommandCatalog.spec(named:)).flatMap(BatchRunner.stepRefusal) == nil)
            #expect(action != nil)
        }
        #expect(BatchRunner.stepAction(forTool: "plugin/view") == nil)
        // A tool card's settings go on top of the step's defaults.
        let captions = BatchRunner.toolStep(ToolID.captions, label: "Captions", params: ["replace": .bool(false)])
        #expect(captions?.action == "captions.generate")
        #expect(captions?.params["media"] == .string("{media}"))
        #expect(captions?.params["replace"] == .bool(false))
    }
}
