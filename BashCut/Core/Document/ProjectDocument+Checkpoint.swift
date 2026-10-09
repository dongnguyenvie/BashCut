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
            "id": .string(id), "gate": .string(gate.id), "name": .string(gate.name), "status": .string(status.rawValue),
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

    /// `context.get`'s `workflow`: the gate modes, the round limit, the checkpoint waiting for the user, the
    /// checklist in short and the next stage with the one skill to read now (spec 13 §5, §9).
    var workflowContext: JSONValue {
        var row = settings.workflowJSON.object
        row["checkpoint"] = checkpoint?.json(currentRevision: project.revision) ?? .null
        let checklist = runChecklist
        row["checklist"] = WorkflowChecklist.compact(checklist)
        row["next"] = WorkflowChecklist.next(checklist)
        return .object(row)
    }

    /// `run.checklist`: derived from the plan and the run log (empty before the first save).
    var runChecklist: JSONValue { WorkflowChecklist.json(project, entries: runLog?.entries() ?? []) }

    /// A workflow guard's failure (spec 13 §7) as an error with its category and the command that fixes it.
    static func guardFailure(_ failure: WorkflowChecklist.GuardFailure) -> RPCFailure {
        RPCFailure(
            -32003, failure.message,
            category: failure.category == "recipe_unread" ? .recipeUnread : .auditMissing,
            data: ["remediation": .object(["command": .string(failure.command)])])
    }

    /// Before G2, and before the rough cut when G2 is skipped: agents need the recipe read and a strategy audit. The
    /// user is never blocked.
    func checkStrategyGuard(author: Author) throws {
        guard author != .user, let log = runLog,
            let failure = WorkflowChecklist.strategyGuard(project, entries: log.entries())
        else { return }
        throw Self.guardFailure(failure)
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
        handle("run.checklist") { document, _, _ in document.runChecklist }
    }

    /// `run.append`: an entry of any kind but `gate`, with the given fields over `data`, the revision and the author.
    /// `stage` takes a status (done with evidence, else stored unverified; skipped with a reason), `skill` a name
    /// (verified only from the kit hook), `audit` a point, verdict, findings and auditor (spec 13 §5, §6).
    func appendRunLog(_ arguments: CommandArguments, author: Author) throws -> JSONValue {
        guard let log = runLog else { throw RPCFailure(-32602, "Save the project first") }
        let kind = try arguments.string("kind")
        guard kind.count <= 40, kind != "gate" else {
            throw RPCFailure(-32602, "kind must be 1–40 characters and not gate (checkpoints write gate entries)")
        }
        var entry = Self.runLogFields(arguments)
        entry["kind"] = .string(kind)
        entry["author"] = .string(author.rawValue)
        entry["rev"] = .integer(project.revision)
        switch kind {
        case "stage": try completeStageEntry(&entry, author: author)
        case "skill":
            guard try completeSkillEntry(&entry, hook: arguments.optionalString("verifiedBy") == "hook") else {
                return .object(["ignored": .bool(true), "name": entry["name"] ?? .null])
            }
        case "audit":
            guard entry["point"] != nil, entry["verdict"] != nil else {
                throw RPCFailure(-32602, "An audit entry needs --point and --verdict")
            }
            entry["by"] = entry["by"] ?? .string("self")
            entry["timeline"] = .string(WorkflowChecklist.timelineFingerprint(project))
        default: break
        }
        do { return try log.append(entry) } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
    }

    /// Fills a `skill` entry; false when the kit hook reported a skill that is not BashCut's (nothing is written).
    private func completeSkillEntry(_ entry: inout [String: JSONValue], hook: Bool) throws -> Bool {
        guard let name = entry["name"]?.string, !name.isEmpty else { throw RPCFailure(-32602, "A skill entry needs --name") }
        // A plugin skill loaded by its agent name (`vlog-product-ad`) is recorded by its ID (`bashcut.vlog:product-ad`).
        if let plugin = plugins.skills.first(where: { $0.linkName == name }) {
            entry["name"] = .string(plugin.id)
            entry["origin"] = .string("plugin")
        } else if hook, !name.hasPrefix("bc:"), !name.contains(":") {
            // The hook sees every skill an agent loads; only BashCut's own are recorded.
            return false
        }
        entry["origin"] = entry["origin"] ?? .string(name.hasPrefix("bc:") ? "kit" : name.contains(":") ? "plugin" : "project")
        entry["verified"] = .bool(hook)
        return true
    }

    /// The `data` object with the named fields over it: strings, counts, comma lists and `;`-separated evidence.
    private static func runLogFields(_ arguments: CommandArguments) -> [String: JSONValue] {
        var entry = arguments.values["data"]?.object ?? [:]
        for key in ["stage", "text", "status", "reason", "name", "origin", "point", "verdict", "by"] {
            if let value = arguments.optionalString(key) { entry[key] = .string(value) }
        }
        for key in ["round", "fixed", "left", "findings"] { if let value = arguments.optionalInt(key) { entry[key] = .integer(value) } }
        for key in ["measured", "notMeasured"] {
            if let value = arguments.optionalString(key) {
                entry[key] = .array(value.split(separator: ",").map { .string($0.trimmingCharacters(in: .whitespaces)) })
            }
        }
        let evidence = (arguments.optionalString("evidence") ?? "").split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !evidence.isEmpty { entry["evidence"] = .array(evidence.map(JSONValue.string)) }
        return entry
    }

    /// A stage entry: done without evidence is unverified, skipped needs a reason, and the rough cut while G2 is
    /// skip meets the strategy guard.
    private func completeStageEntry(_ entry: inout [String: JSONValue], author: Author) throws {
        guard entry["stage"]?.string != nil else { throw RPCFailure(-32602, "A stage entry needs --stage") }
        if entry["status"] == .string("done"), entry["evidence"] == nil { entry["unverified"] = .bool(true) }
        if entry["status"] == .string("skipped"), (entry["reason"]?.string ?? "").isEmpty {
            throw RPCFailure(-32602, "A skipped stage needs --reason")
        }
        if entry["stage"] == .string("rough-cut"), entry["status"] != .string("skipped"), settings.gateMode(.strategy) == .skip {
            try checkStrategyGuard(author: author)
        }
    }

    /// Changes one gate and/or the round limit. Agents may only make a gate ask more (skip → notify → ask) and may not
    /// change the round limit; the user may do anything, here or in Settings.
    func setGates(_ arguments: CommandArguments, author: Author) throws -> JSONValue {
        let order: [WorkflowGate.Mode] = [.skip, .notify, .ask]
        if let id = arguments.optionalString("gate") {
            guard let gate = WorkflowGate(id: id), let mode = arguments.optionalString("mode").flatMap(WorkflowGate.Mode.init)
            else { throw RPCFailure(-32602, "Give a gate (G1…G5 or a name) and a mode (ask, notify, skip)") }
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
            throw RPCFailure(-32602, "A gate is G1…G5, brief, strategy, roughCut, script, draft or a name of 1–40 letters, digits, ., - or _")
        }
        if gate == .strategy { try checkStrategyGuard(author: author) }
        settings.noteGate(gate)
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
            "kind": .string("gate"), "gate": .string(request.gate.id), "checkpoint": .string(request.id),
            "event": .string(event), "rev": .integer(request.revision), "author": .string(request.author.rawValue),
        ]
        if event == "requested" { entry["summary"] = .string(String(request.summary.prefix(2_000))) }
        if let note = request.note { entry["note"] = .string(note) }
        if [.approved, .changes, .rejected].contains(request.status) { entry["answeredBy"] = .string("user") }
        do { try runLog?.append(entry) } catch { DebugLog.write("runlog", "append failed: \(error)") }
    }
}
