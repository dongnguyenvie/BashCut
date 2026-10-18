import BashCutAutomation
import BashCutDocument
import BashCutProject
import Testing

/// The batch-fix steps (P2-C3) as the runner checks them.
struct BatchFixStepTests {
    @Test("Every built-in step of the catalog is a step a batch may run, so a fix pipeline passes the check")
    @MainActor func stepsPassTheCheck() throws {
        var steps = BatchStepCatalog.entries.map(\.step)
        steps[steps.count - 1].params["presets"] = .array([.string(OutputPresetName.all[0])])
        let pipeline = BatchPipeline(name: "Fix", inputs: [BatchInput(path: "/a.bashcut", kind: .project)], steps: steps)
        try BatchRunner.check(pipeline) { _ in false }
        for entry in BatchStepCatalog.entries where entry.action != BatchRunner.exportAction {
            #expect(CommandCatalog.spec(named: entry.action) != nil, "\(entry.action) is not a command")
        }
    }
}
