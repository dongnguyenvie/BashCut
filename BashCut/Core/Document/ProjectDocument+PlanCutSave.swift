import BashCutAutomation
import BashCutProject
import Foundation

/// `plan check --save`: the checked list kept as plan.cut without building it (#631).
extension ProjectDocument {
    /// Saves the list `cut` or `patch` gives as plan.cut in one undoable edit when the check's only errors are ones a
    /// later stage resolves (`PlanCut.stagePending`); the result is the check's with `rev` and `saved`.
    func savePlanCut(_ check: PlanCutCheck, _ arguments: CommandArguments, author: Author?) throws -> JSONValue {
        guard let author else { throw RPCFailure(-32001, "A live agent session token is required") }
        guard arguments["baseRev"] != nil else {
            throw RPCFailure(-32602, "save needs baseRev (the project revision, or last)")
        }
        let baseRevision = try arguments.int("baseRev")
        let given = [arguments["cut"], arguments["patch"]].contains { $0 != nil && $0 != .null }
        guard given, let cut = try planCutValue(arguments) else {
            throw RPCFailure(-32602, "Nothing to save: give cut or patch (plan.cut is already the stored list)")
        }
        let blockers = PlanCut.saveBlockers(check.problems)
        guard blockers.isEmpty else {
            throw RPCFailure(
                -32602, "The edit list has errors no later stage resolves; fix them (plan check lists them). "
                    + "Only " + PlanCut.stagePending.sorted().joined(separator: " and ") + " may stand when saving",
                data: .object([
                    "problems": .array(blockers.map(\.json)),
                    "remediation": .object(["command": .string("plan.check")]),
                ]))
        }
        var plan = project["plan"]?.object ?? [:]
        plan["cut"] = cut
        let label = "Save edit list"
        let result = try commitEdit(
            .setProjectProperties(patch: ["plan": .object(plan)]), label: label, author: author,
            baseRevision: baseRevision)
        var json = check.json.object
        json["rev"] = .integer(result.revision)
        json["saved"] = .bool(true)
        json["changed"] = .bool(result.changed)
        return .object(json)
    }
}
