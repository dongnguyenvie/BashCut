import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutProject
import BashCutStorage
import Foundation

/// A stop at a workflow gate (P1-D5): the agent's summary and attachments, bound to the revision it shows. Only the
/// user answers it (approve, changes, reject) in the app; an agent can read it and withdraw its own request.
struct CheckpointRequest: Identifiable {
    enum Status: String { case awaitingUser = "awaiting_user", approved, changes, rejected, skipped, notified, withdrawn }

    let id: String
    let gate: WorkflowGate
    let summary: String
    let attachments: [URL]
    let revision: Int
    let author: Author
    var status: Status
    var note: String?

    func json(currentRevision: Int) -> JSONValue {
        var row: [String: JSONValue] = [
            "id": .string(id), "gate": .string(gate.rawValue), "name": .string(gate.name), "status": .string(status.rawValue),
            "rev": .integer(revision), "summary": .string(summary),
            "attachments": .array(attachments.map { .string($0.path) }), "requestedBy": .string(author.rawValue),
        ]
        if let note { row["note"] = .string(note) }
        if [.approved, .changes, .rejected].contains(status) { row["answeredBy"] = .string("user") }
        // An approval covers the revision it was shown; later edits leave it standing but say so.
        row["stale"] = .bool(currentRevision != revision)
        return .object(row)
    }
}

extension ProjectDocument {
    /// The run log of the saved project; nil before the first save.
    var runLog: RunLog? { fileURL.map { RunLog(projectRoot: $0.deletingLastPathComponent()) } }

    /// `context.get`'s `workflow`: the gate modes, the round limit and the checkpoint waiting for the user.
    var workflowContext: JSONValue {
        var row = settings.workflowJSON.object
        row["checkpoint"] = checkpoint?.json(currentRevision: project.revision) ?? .null
        return .object(row)
    }

    func registerWorkflowCommands() {
        handle("workflow.gates") { document, _, _ in document.settings.workflowJSON }
        handleAuthored("workflow.set-gates") { document, arguments, author in
            try document.setGates(arguments, author: author)
        }
        handleAuthored("checkpoint.request") { document, arguments, author in
            try document.requestCheckpoint(arguments, author: author)
        }
        handle("checkpoint.status") { document, arguments, _ in
            let id = arguments.optionalString("id")
            guard let request = id.map({ id in document.checkpoints.last { $0.id == id } }) ?? document.checkpoints.last else {
                throw RPCFailure(-32602, id.map { "No checkpoint \($0) in this session" } ?? "No checkpoint in this session")
            }
            return request.json(currentRevision: document.project.revision)
        }
        handle("run.log") { document, arguments, _ in
            guard let log = document.runLog else { throw RPCFailure(-32602, "Save the project first") }
            return log.read(
                run: arguments.optionalString("run") ?? "current", kind: arguments.optionalString("kind"),
                limit: arguments.optionalInt("limit"))
        }
        handleAuthored("run.append") { document, arguments, author in try document.appendRunLog(arguments, author: author) }
    }

    /// `run.append`: an entry of any kind but `gate`, with the given fields over `data`, the revision and the author.
    func appendRunLog(_ arguments: CommandArguments, author: Author) throws -> JSONValue {
        guard let log = runLog else { throw RPCFailure(-32602, "Save the project first") }
        let kind = try arguments.string("kind")
        guard kind.count <= 40, kind != "gate" else {
            throw RPCFailure(-32602, "kind must be 1–40 characters and not gate (checkpoints write gate entries)")
        }
        var entry = arguments.values["data"]?.object ?? [:]
        entry["kind"] = .string(kind)
        entry["author"] = .string(author.rawValue)
        entry["rev"] = .integer(project.revision)
        for key in ["stage", "text"] { if let value = arguments.optionalString(key) { entry[key] = .string(value) } }
        for key in ["round", "fixed", "left"] { if let value = arguments.optionalInt(key) { entry[key] = .integer(value) } }
        for key in ["measured", "notMeasured"] {
            if let value = arguments.optionalString(key) {
                entry[key] = .array(value.split(separator: ",").map { .string($0.trimmingCharacters(in: .whitespaces)) })
            }
        }
        do { return try log.append(entry) } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
    }

    /// Changes one gate and/or the round limit. Agents may only make a gate ask more (skip → notify → ask) and may not
    /// change the round limit; the user may do anything, here or in Settings.
    func setGates(_ arguments: CommandArguments, author: Author) throws -> JSONValue {
        let order: [WorkflowGate.Mode] = [.skip, .notify, .ask]
        if let id = arguments.optionalString("gate") {
            guard let gate = WorkflowGate(id: id), let mode = arguments.optionalString("mode").flatMap(WorkflowGate.Mode.init)
            else { throw RPCFailure(-32602, "Give a gate (G1…G5) and a mode (ask, notify, skip)") }
            let current = settings.gateMode(gate)
            if author != .user, order.firstIndex(of: mode)! < order.firstIndex(of: current)! {
                throw RPCFailure(-32001, "Only the user can loosen a gate (Settings → Agents → Workflow gates)")
            }
            settings.setGateMode(gate, mode)
        }
        if let rounds = arguments.optionalInt("maxReviewRounds") {
            guard author == .user else { throw RPCFailure(-32001, "Only the user can change the review round limit") }
            settings.maxReviewRounds = rounds
        }
        return settings.workflowJSON
    }

    func requestCheckpoint(_ arguments: CommandArguments, author: Author) throws -> JSONValue {
        guard let gate = WorkflowGate(id: try arguments.string("gate")) else {
            throw RPCFailure(-32602, "Unknown gate; use G1…G5 or brief, strategy, roughCut, script, draft")
        }
        let root = fileURL?.deletingLastPathComponent()
        let attachments = (arguments.optionalString("attach") ?? "").split(separator: ",").map { part -> URL in
            let path = part.trimmingCharacters(in: .whitespaces)
            return path.hasPrefix("/") || root == nil ? URL(fileURLWithPath: path) : root!.appendingPathComponent(path)
        }
        if let missing = attachments.first(where: { !FileManager.default.fileExists(atPath: $0.path) }) {
            throw RPCFailure(-32602, "Attachment not found: \(missing.path)")
        }
        let mode = settings.gateMode(gate)
        if mode == .ask, checkpoint != nil { throw RPCFailure(-32003, "Another checkpoint is waiting for the user", category: .busyApproval) }
        var request = CheckpointRequest(
            id: String(UUID().uuidString.prefix(8)).lowercased(), gate: gate, summary: try arguments.string("summary"),
            attachments: attachments, revision: project.revision, author: author,
            status: mode == .ask ? .awaitingUser : mode == .notify ? .notified : .skipped)
        switch mode {
        case .ask:
            checkpoint = request
            NSApp.activate(ignoringOtherApps: true)
        case .notify: message = String(localized: "\(gate.title): \(request.summary)")
        case .skip: break
        }
        checkpoints.append(request)
        logGate(request, event: mode == .ask ? "requested" : request.status.rawValue)
        return request.json(currentRevision: project.revision)
    }

    /// The user's answer from the sheet, or the agent withdrawing its request.
    func resolveCheckpoint(_ status: CheckpointRequest.Status, note: String? = nil) {
        guard var request = checkpoint else { return }
        checkpoint = nil
        request.status = status
        request.note = note.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        if let index = checkpoints.lastIndex(where: { $0.id == request.id }) { checkpoints[index] = request }
        logGate(request, event: status.rawValue)
    }

    private func logGate(_ request: CheckpointRequest, event: String) {
        var entry: [String: JSONValue] = [
            "kind": .string("gate"), "gate": .string(request.gate.rawValue), "checkpoint": .string(request.id),
            "event": .string(event), "rev": .integer(request.revision), "author": .string(request.author.rawValue),
        ]
        if event == "requested" { entry["summary"] = .string(String(request.summary.prefix(2_000))) }
        if let note = request.note { entry["note"] = .string(note) }
        if [.approved, .changes, .rejected].contains(request.status) { entry["answeredBy"] = .string("user") }
        do { try runLog?.append(entry) } catch { DebugLog.write("runlog", "append failed: \(error)") }
    }
}
