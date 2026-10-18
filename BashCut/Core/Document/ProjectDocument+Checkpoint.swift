import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
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
        var data = failure.details
        data["remediation"] = .object(["command": .string(failure.command)])
        return RPCFailure(
            -32003, failure.message,
            category: RPCErrorCategory(rawValue: failure.category) ?? .auditMissing, data: data)
    }

    /// Before G2, and before the rough cut when G2 is skipped: agents need the recipe read and a strategy audit. The
    /// user is never blocked.
    func checkStrategyGuard(author: Author) throws {
        guard author != .user, let log = runLog,
            let failure = WorkflowChecklist.strategyGuard(project, entries: log.entries())
        else { return }
        throw Self.guardFailure(failure)
    }

    /// Before a final export by an agent (spec 13 §7), whatever agentPermissions say; quick drafts and the user are
    /// never blocked. No graphic rendered as a draft (#634), checked first because finalising changes the timeline;
    /// then a passing draft audit of this timeline or the user's G5 approval. `graphics: false` leaves the drafts to
    /// plugin export steps that run first; the guard runs again after them.
    func checkExportGuards(preset: ExportPreset, author: Author, graphics: Bool = true) throws {
        guard author != .user, preset != .quickDraft else { return }
        if graphics, let failure = WorkflowChecklist.graphicsDraftGuard(project) { throw Self.guardFailure(failure) }
        if let log = runLog, let failure = WorkflowChecklist.draftGuard(project, entries: log.entries()) {
            throw Self.guardFailure(failure)
        }
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
            let find = { id.map { id in document.checkpoints.last { $0.id == id } } ?? document.checkpoints.last }
            guard var request = find() else {
                throw RPCFailure(-32602, id.map { "No checkpoint \($0) in this session" } ?? "No checkpoint in this session")
            }
            // With wait, hold the call while the user has not answered, instead of the agent polling.
            let deadline = ContinuousClock.now + .seconds(arguments.optionalInt("wait") ?? 0)
            let checkpointID = request.id
            while request.status == .awaitingUser, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(250))
                guard let next = document.checkpoints.last(where: { $0.id == checkpointID }) else { break }
                request = next
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
        handle("run.status") { document, _, _ in
            await document.loadReviewTranscripts()
            return document.runStatus()
        }
    }

    /// `run.status`: the run panel's progress and, once the run exported, its result card.
    func runStatus(now: Date = Date()) -> JSONValue {
        guard let progress = RunProgress.make(project, entries: runLog?.entries() ?? []) else {
            return .object(["progress": .null, "result": .null])
        }
        var result = runResult(for: progress)
        if let current = runPanel.result, current.run == result?.run, current.main == result?.main {
            result?.thumbnail = current.thumbnail
        }
        return .object(["progress": progress.json(now: now), "result": result?.json ?? .null])
    }

    /// The result card of a run that exported: its exports from the history and the open review issues now.
    func runResult(for progress: RunProgress) -> RunResult? {
        guard progress.exportedAt != nil, let root = fileURL?.deletingLastPathComponent() else { return nil }
        let history = (try? ExportHistoryStore().all(projectRoot: root)) ?? []
        return RunResult.make(
            run: progress.run, since: progress.startedAt, history: history,
            review: ReviewSummary(reviewIssues(), coverage: .null),
            recipe: project["plan"]?.object["recipe"]?.object["skill"]?.string)
    }

    /// `run.append`: an entry of any kind but `gate`, with the given fields over `data`, the revision and the author.
    /// `stage` takes a status (done with evidence, else stored unverified; skipped with a reason), `skill` a name
    /// (verified only from the kit hook), `audit` a point, verdict, findings and auditor (spec 13 §5, §6).
    func appendRunLog(_ arguments: CommandArguments, author: Author) throws -> JSONValue {
        let kind = try arguments.string("kind")
        guard let log = runLog else { return try holdSkillRead(kind, arguments, author: author) }
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
            rememberSkillRead(entry)
        case "audit":
            guard entry["point"] != nil, entry["verdict"] != nil else {
                throw RPCFailure(-32602, "An audit entry needs --point and --verdict")
            }
            entry["by"] = entry["by"] ?? .string("self")
            entry["timeline"] = .string(WorkflowChecklist.timelineFingerprint(project))
        default: break
        }
        do {
            let written = try log.append(entry)
            if kind == "stage" { runPanel.refresh() }
            return written
        } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
    }

    /// A skill read reported before the project exists, kept for the next project that opens; other kinds need one.
    private func holdSkillRead(_ kind: String, _ arguments: CommandArguments, author: Author) throws -> JSONValue {
        guard kind == "skill" else { throw RPCFailure(-32602, "Save the project first") }
        var entry = Self.runLogFields(arguments)
        entry["kind"] = .string(kind)
        entry["author"] = .string(author.rawValue)
        guard try completeSkillEntry(&entry, hook: arguments.optionalString("verifiedBy") == "hook") else {
            return .object(["ignored": .bool(true), "name": entry["name"] ?? .null])
        }
        rememberSkillRead(entry)
        holdRunEntry(entry)
        return .object(["held": .bool(true), "name": entry["name"] ?? .null])
    }

    /// Keeps a skill read for the next project that opens within half an hour.
    func rememberSkillRead(_ entry: [String: JSONValue], now: Date = Date()) {
        recentSkillReads.removeAll { now.timeIntervalSince($0.date) > 1_800 }
        recentSkillReads.append((now, entry))
        if recentSkillReads.count > 20 { recentSkillReads.removeFirst(recentSkillReads.count - 20) }
    }

    /// Keeps an entry made before a project was open (at most the last 20).
    func holdRunEntry(_ entry: [String: JSONValue]) {
        pendingRunEntries.append(entry)
        if pendingRunEntries.count > 20 { pendingRunEntries.removeFirst(pendingRunEntries.count - 20) }
    }

    /// Writes the held entries to the run log of the project that just opened.
    func flushPendingRunEntries() {
        guard let log = runLog else { return }
        // Recent reads made while another project was open, unless this log already has them.
        let logged = Set(log.entries().filter { $0["kind"]?.string == "skill" }.compactMap { $0["name"]?.string })
        let held = Set(pendingRunEntries.compactMap { $0["name"]?.string })
        var carried = Set<String>()
        let recent = recentSkillReads.map(\.entry).filter { entry in
            guard let name = entry["name"]?.string, !logged.contains(name), !held.contains(name) else { return false }
            return carried.insert(name).inserted
        }
        for var entry in pendingRunEntries + recent {
            entry["rev"] = .integer(project.revision)
            do { try log.append(entry) } catch { DebugLog.write("runlog", "held entry not logged: \(error)") }
        }
        pendingRunEntries.removeAll()
    }

    /// Records a stage BashCut itself can prove (`plan.apply` built the rough cut, `review.run` passed, an export
    /// landed), so the agent does not spend a turn on `run append`. Agents only; review and export once per revision,
    /// the other stages once, and the rough cut only when the strategy guard would let the agent record it.
    func logAutoStage(_ stage: String, evidence: [String], author: Author) {
        guard author != .user, let log = runLog else { return }
        let entries = log.entries()
        // Once per revision for review and export (a pass or an export proves that revision); the building stages
        // once, while their latest entry is still BashCut's own done, so every plan apply does not log them again.
        let latest = entries.last { $0["kind"]?.string == "stage" && $0["stage"]?.string == stage }
        if let latest, latest["status"]?.string == "done",
            latest["rev"] == .integer(project.revision) || (latest["auto"] == .bool(true) && !["review", "export"].contains(stage))
        { return }
        if stage == "review", WorkflowChecklist.stagesGuard(project, entries: entries) != nil { return }
        if stage == "rough-cut", settings.gateMode(.strategy) == .skip,
            WorkflowChecklist.strategyGuard(project, entries: entries) != nil
        { return }
        let entry: [String: JSONValue] = [
            "kind": .string("stage"), "stage": .string(stage), "status": .string("done"),
            "evidence": .array(evidence.map(JSONValue.string)), "author": .string(author.rawValue),
            "rev": .integer(project.revision), "auto": .bool(true),
        ]
        do { try log.append(entry) } catch { DebugLog.write("runlog", "auto stage not logged: \(error)") }
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
        for key in ["round", "fixed", "left", "findings", "eta"] { if let value = arguments.optionalInt(key) { entry[key] = .integer(value) } }
        if let progress = arguments.optionalDouble("progress") { entry["progress"] = .number(progress) }
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

    /// A stage entry: done without evidence is unverified, skipped needs a reason, review done by an agent meets the
    /// stages guard, and the rough cut while G2 is skip meets the strategy guard.
    private func completeStageEntry(_ entry: inout [String: JSONValue], author: Author) throws {
        guard let stage = entry["stage"]?.string else { throw RPCFailure(-32602, "A stage entry needs --stage") }
        entry["stage"] = .string(RunProgress.stageID(stage))
        if entry["status"] == .string("done"), entry["evidence"] == nil { entry["unverified"] = .bool(true) }
        if entry["status"] == .string("skipped"), (entry["reason"]?.string ?? "").isEmpty {
            throw RPCFailure(-32602, "A skipped stage needs --reason")
        }
        if author != .user, entry["stage"] == .string("review"), entry["status"] == .string("done"), let log = runLog,
            let failure = WorkflowChecklist.stagesGuard(project, entries: log.entries())
        {
            throw Self.guardFailure(failure)
        }
        if WorkflowChecklist.stageNeedsStrategyGuard(
            stage: entry["stage"]?.string ?? "", status: entry["status"]?.string,
            strategySkipped: settings.gateMode(.strategy) == .skip) {
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
        if gate == .draft, author != .user, let log = runLog,
            let failure = WorkflowChecklist.stagesGuard(project, entries: log.entries())
        {
            throw Self.guardFailure(failure)
        }
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
        let request = CheckpointRequest(
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
