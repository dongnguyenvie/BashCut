import BashCutAutomation
import BashCutProject
import Foundation

/// The agent's notes as project data (P1-D1, P1-D2): the brief, the edit plan or any key of its own, read and set as
/// undoable edits; brief and plan are summarised in `context.get` so an agent can resume from them.
extension ProjectDocument {
    func registerPlanCommands() {
        handle("project.data") { document, arguments, _ in document.project[try arguments.string("key")] ?? .null }
        handle("project.credits") { document, _, _ in
            ProjectCredits.of(document.project).json
        }
        handleAuthored("project.set-data") { document, arguments, author in
            let key = try arguments.string("key")
            return try document.setPlanObject(
                key, arguments, author: author,
                label: key == "brief" ? "Set brief" : key == "plan" ? "Set edit plan" : "Set \(key)")
        }
        handle("review.coverage") { document, _, _ in PlanCoverage.coverage(document.project) }
        handle("script.check") { document, arguments, _ in
            var beats = try arguments.values["beats"]?.array.map { beat -> [String: JSONValue] in
                guard case .object(let fields) = beat, fields["text"]?.string != nil else {
                    throw RPCFailure(-32602, "Each beat is an object with text")
                }
                return fields
            }
            if beats == nil, let text = arguments.optionalString("text") { beats = [["id": .string("script"), "text": .string(text)]] }
            let (words, source) = await document.syncWords()
            var result = PlanCoverage.scriptCheck(document.project, words: words, beats: beats).object
            result["wordSource"] = .string(source)
            return .object(result)
        }
    }

    /// Replaces `key` (or with merge, its top-level fields) as one undoable edit; null clears it.
    func setPlanObject(_ key: String, _ arguments: CommandArguments, author: Author, label: String) throws -> JSONValue {
        guard let value = arguments["value"] else { throw RPCFailure(-32602, "Give the \(key) as JSON") }
        var next = value
        if arguments.bool("merge"), case .object(let patch) = value, case .object(var current)? = project[key] {
            for (field, fieldValue) in patch { current[field] = fieldValue == .null ? nil : fieldValue }
            next = .object(current)
        }
        do {
            try ProjectPlan.validateNotes(next, key: key)
            let revision = try commit(
                .setProjectProperties(patch: [key: next]), label: label, author: author,
                baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(revision), key: project[key] ?? .null])
        } catch let error as ProjectError {
            throw RPCFailure.invalid(error)
        }
    }
}
