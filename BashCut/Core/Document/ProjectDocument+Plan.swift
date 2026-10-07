import BashCutAutomation
import BashCutProject
import Foundation

/// The brief and the edit plan as project data (P1-D1, P1-D2): read and set as undoable edits, summarised in
/// `context.get` so an agent can resume from them.
extension ProjectDocument {
    func registerPlanCommands() {
        handle("project.brief") { document, _, _ in document.project["brief"] ?? .null }
        handleAuthored("project.set-brief") { document, arguments, author in
            try document.setPlanObject("brief", arguments, author: author, label: "Set brief")
        }
        handle("plan.get") { document, _, _ in document.project["plan"] ?? .null }
        handleAuthored("plan.set") { document, arguments, author in
            try document.setPlanObject("plan", arguments, author: author, label: "Set edit plan")
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
            let revision = try commit(
                .setProjectProperties(patch: [key: next]), label: label, author: author,
                baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(revision), key: project[key] ?? .null])
        } catch let error as ProjectError {
            throw RPCFailure(-32602, error.localizedDescription)
        }
    }
}
