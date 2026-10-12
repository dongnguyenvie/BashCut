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

    /// Replaces `key` as one undoable edit; null clears it. With merge, objects merge key by key at every depth (null
    /// deletes a key) and arrays or values replace, like `patchItems`.
    func setPlanObject(_ key: String, _ arguments: CommandArguments, author: Author, label: String) throws -> JSONValue {
        guard let value = arguments["value"] else { throw RPCFailure(-32602, "Give the \(key) as JSON") }
        var next = value
        if arguments.bool("merge"), case .object = value, case .object? = project[key] {
            next = ItemPatch.merge(project[key], value)
        }
        do {
            try ProjectPlan.validateNotes(next, key: key)
            let revision = try commit(
                .setProjectProperties(patch: [key: next]), label: label, author: author,
                baseRevision: arguments.int("baseRev"))
            if key == "brief", case .object(let brief) = next, !brief.isEmpty {
                logAutoStage("intake", evidence: ["brief set: " + brief.keys.sorted().joined(separator: ", ")], author: author)
            }
            let stored = project[key] ?? .null
            if arguments.bool("echo") { return .object(["rev": .integer(revision), key: stored]) }
            return ProjectPlan.dataAck(key: key, value: stored, revision: revision)
        } catch let error as ProjectError {
            throw RPCFailure.invalid(error)
        }
    }
}
