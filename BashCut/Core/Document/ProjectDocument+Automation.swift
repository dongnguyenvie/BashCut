import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutInterchange
import BashCutProject
import BashCutStorage
import Foundation

extension ProjectDocument {
    typealias CommandBody = @MainActor (ProjectDocument, CommandArguments, Author?) async throws -> JSONValue
    typealias AuthoredCommandBody = @MainActor (ProjectDocument, CommandArguments, Author) async throws -> JSONValue

    func startAutomation() {
        registry.currentRevision = { [weak self] in self?.project.revision }
        registerReadCommands()
        registerProjectCommands()
        registerCaptionCommands()
        registerCapabilityCommands()
        registerDialogCommands()
        registerDialogs()
        registerEditCommands()
        registerLayerCommands()
        registerSpeedCommands()
        registerRampCommands()
        registerMotionCommands()
        registerCaptionWordCommands()
        registerAdjustmentCommands()
        registerImportCommands()
        registerProxyCommands()
        registerMediaAnalysisCommands()
        registerSourceTranscriptCommands()
        registerMediaDescriptionCommands()
        registerMediaStillsCommands()
        registerMediaInventoryCommands()
        registerMediaDigestCommands()
        registerReviewTimingCommands()
        registerTimelineStillsCommands()
        registerColorMeasureCommands()
        registerBeatGridCommands()
        registerVisionCommands()
        registerSpeechRateCommands()
        registerVoiceCheckCommands()
        registerVoiceTakeCommands()
        registerVoiceLineCommands()
        registerPlanCommands()
        registerWorkflowCommands()
        registerSelectsCommands()
        registerPlanCutCommands()
        registerVariantCommands()
        registerPackagingCommands()
        registerStorageCommands()
        registerLibraryCommands()
        registerAgentKitCommands()
        registerAppCommands()
        registerChatAgentCommands()
        registerChatScopeCommands()
        registerTerminalCommands()
        registerPrivilegedCommands()
        registerUICommands()
        registerUIActionCommands()
        registerToolCommands()
        registerPluginCommands()
        registerPluginViewCommands()
        plugins.jobs = jobs
        plugins.onSkillsChanged = { [weak self] in self?.pluginSkillsChanged() }
        plugins.service.optionValues = { [weak self] plugin in
            await MainActor.run { self?.pluginOptionValues(plugin, revealSecrets: true) ?? [:] }
        }
        plugins.refresh(projectRoot: nil)
        emitPluginEvent(.appLaunched)
        // At launch, also with no project open: a new release opens Software Update once.
        if settings.checkAppUpdatesDaily { checkAppUpdateIfDue() }
        assert(registry.unhandledCommands.isEmpty, "Unhandled commands: \(registry.unhandledCommands)")
        Task { _ = await agentConfigFolders() }
        Task {
            do {
                try await automation.start()
                applyExternalAgentAccess(enabled: settings.allowExternalAgents)
            } catch { message = error.localizedDescription }
        }
    }

    /// Registers a handler that holds the document weakly. Arguments are already validated against the spec.
    func handle(_ method: String, _ body: @escaping CommandBody) {
        registry.register(method) { [weak self] arguments, author in
            guard let self else { throw RPCFailure(-32000, "Editor closed") }
            return try await body(self, arguments, author)
        }
    }

    /// Edit and privileged commands: the registry has already rejected requests without a session token. A result
    /// object of a command that changed the project carries `changes`, a bounded digest of what changed (P2-G1).
    func handleAuthored(_ method: String, _ body: @escaping AuthoredCommandBody) {
        handle(method) { document, arguments, author in
            guard let author else { throw RPCFailure(-32001, "A live agent session token is required") }
            let before = document.project
            let result = try await body(document, arguments, author)
            guard case .object(var fields) = result, fields["changes"] == nil,
                document.project.revision != before.revision, document.project["id"] == before["id"]
            else { return result }
            fields["changes"] = ChangeDigest.json(before: before, after: document.project)
            if fields["rev"] == nil { fields["rev"] = .integer(document.project.revision) }
            return .object(fields)
        }
    }

    private func registerReadCommands() {
        handle("context.get") { document, _, _ in
            let analysis = await document.analysisReadiness()
            return .object([
                "project": document.fileURL.map { .string($0.path) } ?? .null,
                "rev": .integer(document.project.revision), "playhead": .integer(document.playhead),
                "selection": document.selectedID.map(JSONValue.string) ?? .null,
                "selectedItems": .array(document.selectedIDs.map(JSONValue.string)),
                "selectedTrack": document.selectedTrackID.map(JSONValue.string) ?? .null,
                "dirty": .bool(document.dirty), "conflict": .bool(document.conflict),
                "busy": .bool(document.busy), "saving": .bool(document.saving),
                "knowledge": document.agents.knowledgeStore.summary().json,
                "scope": document.agentScopeJSON,
                "agentPermissions": document.agentPermissionsJSON, "analysis": analysis,
                "plan": ProjectPlan.summary(document.project), "workflow": document.workflowContext,
                "contentLanguage": document.project["contentLanguage"] ?? .null,
                "recentFailures": document.registry.recentFailures(token: CommandCaller.token),
            ])
        }
        handle("project.get") { document, _, _ in .object(document.project.fields) }
        handle("timeline.get") { document, arguments, _ in
            arguments.optionalString("format") == "text"
                ? .string(TimelineSummary.text(document.project)) : TimelineSummary.json(document.project)
        }
        handle("media.list") { document, arguments, _ in
            var list: [JSONValue] = []
            for media in document.project.media {
                var fields = media.fields
                fields["proxy"] = .string(document.proxyState(media).rawValue)
                if arguments.bool("analysis") {
                    fields["analysis"] = document.mediaAnalysisOverview(media)
                    fields["transcript"] = await document.mediaTranscriptOverview(media)
                }
                // Shots stay out of the list; media.description reads them.
                if fields["description"] != nil {
                    fields["description"] = arguments.bool("analysis")
                        ? document.mediaDescriptionCoverage(media) : media.shotDescription?.summaryJSON ?? .null
                }
                list.append(.object(fields))
            }
            return .array(list)
        }
        handle("review.run") { document, arguments, author in
            try await document.runReview(arguments, author: author ?? .user)
        }
        handleAuthored("review.measure") { document, arguments, author in
            try document.startReviewMeasure(
                author: author, picture: arguments.optionalBool("picture") ?? true,
                plugins: arguments.optionalBool("plugins") ?? true)
        }
        handle("review.picture") { document, arguments, _ in
            guard let picture = document.reviewPicture else {
                throw RPCFailure(-32602, "No picture measurement yet: run review measure first")
            }
            return picture.json(
                for: document.project, from: arguments.optionalInt("from") ?? 0, to: arguments.optionalInt("to"),
                samples: arguments.optionalBool("samples") ?? true, cuts: arguments.optionalBool("cuts") ?? true)
        }
        handle("export.status") { document, _, _ in
            var status = document.exports.statusJSON.object
            status["delivered"] = .array(document.deliveredQC.map(\.json))
            return .object(status)
        }
    }

    private func registerEditCommands() {
        handleAuthored("timeline.apply") { document, arguments, author in
            let label = try arguments.string("label")
            let ops = try WireOperations.decode(arguments.value("ops"), project: document.project)
            let baseRevision = try arguments.int("baseRev")
            let fingerprint = try EditFingerprint.of(ops, baseRevision: baseRevision)
            let operation = EditOperation.group(label: label, author: author, ops: ops)
            let warnings = ProjectSchema.unreadFieldWarnings(ops)
            if arguments.bool("dryRun") {
                await document.loadReviewTranscripts()
                guard case .object(var fields) = try document.dryRunEdit(operation, author: author, baseRevision: baseRevision)
                else { throw RPCFailure(-32603, "Dry run returned no object") }
                fields["fingerprint"] = .string(fingerprint)
                if !warnings.isEmpty { fields["warnings"] = .array(warnings) }
                return .object(fields)
            }
            if let expected = arguments.optionalString("expectFingerprint"), expected != fingerprint {
                throw RPCFailure(-32602, "The ops or baseRev differ from the dry run that was reviewed", data: .object([
                    "expected": .string(expected), "actual": .string(fingerprint),
                    "remediation": .object([
                        "command": .string("timeline.apply"),
                        "hint": .string("Dry-run these ops, review the result, then apply with its fingerprint."),
                    ]),
                ]))
            }
            let result = try document.commitEdit(
                operation, label: label, author: author, baseRevision: baseRevision, note: try Self.editNote(arguments))
            var fields: [String: JSONValue] = [
                "rev": .integer(result.revision), "changed": .bool(result.changed), "fingerprint": .string(fingerprint),
            ]
            if !warnings.isEmpty { fields["warnings"] = .array(warnings) }
            return .object(fields)
        }
        handle("timeline.changes") { document, arguments, _ in
            TimelineChanges.json(
                history: document.history, limit: try arguments.int("limit"), author: arguments.optionalString("author"),
                isAgent: \.isAgent)
        }
        handleAuthored("timeline.undo") { document, arguments, author in
            .object(["rev": .integer(try document.commitUndo(author: author, baseRevision: arguments.int("baseRev")))])
        }
        handleAuthored("timeline.redo") { document, arguments, author in
            .object(["rev": .integer(try document.commitRedo(author: author, baseRevision: arguments.int("baseRev")))])
        }
    }

    /// `why` and `evidence` of an edit command (P2-G3), bounded so the history journal stays small.
    static func editNote(_ arguments: CommandArguments) throws -> EditNote? {
        let why = arguments.optionalString("why")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let evidence = (arguments.optionalString("evidence") ?? "").split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard (why?.count ?? 0) <= 500 else { throw RPCFailure(-32602, "why must be at most 500 characters") }
        guard evidence.count <= 20, evidence.allSatisfy({ $0.count <= 200 }) else {
            throw RPCFailure(-32602, "evidence takes at most 20 entries of 200 characters each")
        }
        let note = EditNote(why: why?.isEmpty == true ? nil : why, evidence: evidence)
        return note.isEmpty ? nil : note
    }

    /// Resolves an export name and optional directory against the saved project's folder.
    private func exportDestination(_ arguments: CommandArguments) throws -> (name: String, directory: URL) {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw RPCFailure(-32602, "Save the project before exporting")
        }
        let name = try arguments.string("name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.contains("/"), !name.contains(":"), name.count <= 180 else {
            throw RPCFailure(-32602, "name must be 1–180 characters without slashes or colons")
        }
        let directory = arguments.optionalString("directory").map {
            URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL
        } ?? root.appendingPathComponent("render", isDirectory: true)
        return (name, directory)
    }

    /// `export start --wait`: the finished job (or `timedOut`), and with `save` the project saved once it landed.
    private func waitForExport(_ job: String, save: Bool) async throws -> [String: JSONValue] {
        let waited = try await waitForJobDone(job, seconds: 100).object
        var result: [String: JSONValue] = ["finished": waited["job"] ?? .null, "timedOut": waited["timedOut"] ?? .bool(false)]
        if save, waited["timedOut"] == .bool(false) {
            if dirty { try await saveNow() }
            result["saved"] = .bool(true)
        }
        return result
    }

    /// The name an export gets (#507-23): a name taken by an earlier export gets the next free suffix, or with
    /// `overwrite` keeps it and returns the old files to replace; a queued export's name is never shared.
    private func exportName(
        _ asked: String, preset: ExportPreset, directory: URL, includeSubRip: Bool, overwrite: Bool
    ) -> (name: String, replaced: [URL]) {
        let name = ExportRequest.availableName(
            asked, preset: preset, directory: directory, includeSubRip: includeSubRip,
            reserved: exports.queue.reservedOutputs, ignoringFiles: overwrite)
        guard overwrite, name == asked else { return (name, []) }
        return (name, ExportRequest.existingOutputs(asked, preset: preset, directory: directory))
    }

    /// Moves an earlier export's files to the Trash before it is written again.
    /// Audio roles an export leaves out (`without`: music, sfx, voiceover or dialogue, comma separated).
    static func exportWithoutRoles(_ list: String?) throws -> Set<String> {
        guard let list else { return [] }
        let allowed: Set<String> = [TrackRole.music, TrackRole.sfx, TrackRole.voiceover, TrackRole.dialogue]
        return try Set(list.split(separator: ",").map { name in
            let role = name.trimmingCharacters(in: .whitespaces)
            guard allowed.contains(role) else {
                throw RPCFailure(-32602, "Unknown sound role \(role): use \(allowed.sorted().joined(separator: ", "))")
            }
            return role
        })
    }

    private static func trash(_ files: [URL]) throws {
        for url in files { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }

    private func registerPrivilegedCommands() {
        handleAuthored("export.start") { document, arguments, author in
            guard let preset = ExportPreset(argument: try arguments.string("preset")) else {
                throw RPCFailure(-32602, "Unknown export preset")
            }
            let (asked, directory) = try document.exportDestination(arguments)
            guard document.project.duration > 0 else { throw RPCFailure(-32602, "The timeline is empty") }
            // A final export by an agent needs a passing draft audit of this timeline or the user's G5 approval
            // (spec 13 §7), whatever agentPermissions say; drafts and the user are never blocked.
            if author != .user, preset != .quickDraft, let log = document.runLog,
                let failure = WorkflowChecklist.draftGuard(document.project, entries: log.entries())
            {
                throw Self.guardFailure(failure)
            }
            let includeSubRip = arguments.bool("includeSRT")
            let normalizeAudio = arguments.bool("normalizeAudio")
            let bitRate = arguments.optionalDouble("bitrate").map { Int($0 * 1_000_000) }
            let without = try Self.exportWithoutRoles(arguments.optionalString("without"))
            let (name, replaced) = document.exportName(
                asked, preset: preset, directory: directory, includeSubRip: includeSubRip,
                overwrite: arguments.bool("overwrite"))
            let output = directory.appendingPathComponent(name).appendingPathExtension(preset.fileExtension)
            // The report's speech coverage reads the clips' stored transcripts (#507-36).
            await document.loadReviewTranscripts()
            // Filled when the export starts at once (auto-approved), so the caller can `jobs wait --done` on it.
            let started = StartedJob()
            let approval = try document.queuePrivilegedApproval(
                method: "export.start", author: author,
                arguments: [
                    "captions": includeSubRip ? "include .srt" : "burned in only",
                    "normalization": normalizeAudio ? "two-pass LUFS" : "off",
                    "output": output.path, "preset": preset.title,
                    "bitrate": bitRate.map { "\(Double($0) / 1_000_000) Mbps" } ?? "preset default",
                    "sound": without.isEmpty ? "full mix" : "without " + without.sorted().joined(separator: ", "),
                ]
            ) { [weak document] in
                guard let document else { throw RPCFailure(-32000, "Editor closed") }
                try Self.trash(replaced)
                started.id = try document.startExportAuthorized(
                    name: name, preset: preset, directory: directory, includeSubRip: includeSubRip,
                    normalizeAudio: normalizeAudio, author: author, videoBitRate: bitRate, withoutRoles: without)
            }
            if !approval.autoApproved {
                document.message = String(localized: "Waiting for approval: export.start")
            }
            var json = approval.json(output: output).object
            json["job"] = started.id.map(JSONValue.string)
            json["renamedFrom"] = name == asked ? nil : .string(asked)
            json["replaced"] = replaced.isEmpty ? nil : .array(replaced.map { .string($0.path) })
            if let job = started.id, arguments.bool("wait") {
                json.merge(try await document.waitForExport(job, save: arguments.bool("save"))) { $1 }
            }
            return .object(json)
        }
        handleAuthored("export.otio") { document, arguments, author in
            let (name, directory) = try document.exportDestination(arguments)
            let output = directory.appendingPathComponent(name).appendingPathExtension("otio")
            guard !FileManager.default.fileExists(atPath: output.path) else {
                throw RPCFailure(-32602, "The OTIO output already exists")
            }
            let approval = try document.queuePrivilegedApproval(
                method: "export.otio", author: author,
                arguments: ["output": output.path, "format": "OpenTimelineIO"]
            ) { [weak document] in
                guard let document else { throw RPCFailure(-32000, "Editor closed") }
                try TimelineFormats.write(document.project, with: OpenTimelineIOExporter(), to: output)
                document.message = String(localized: "OTIO exported")
            }
            if !approval.autoApproved {
                document.message = String(localized: "Waiting for approval: export.otio")
            }
            return approval.json(output: output)
        }
    }

    private func registerUICommands() {
        handle("ui.select") { document, arguments, _ in
            var ids = arguments.optionalString("item").map { [$0] } ?? []
            ids += (arguments.optionalString("items") ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let existing = Set(document.project.tracks.flatMap(\.items).map(\.id))
            if let unknown = ids.first(where: { !existing.contains($0) }) {
                throw RPCFailure(-32602, "Unknown item \(unknown)")
            }
            if arguments.bool("add") { ids = document.selectedIDs + ids }
            if let track = arguments.optionalString("track") {
                guard document.project.tracks.contains(where: { $0.id == track }) else {
                    throw RPCFailure(-32602, "Unknown layer \(track)")
                }
                document.selectedTrackID = track
                if !ids.isEmpty { document.select(ids) }
            } else {
                document.select(ids)
            }
            document.showTimelineViewer()
            return .bool(true)
        }
        handle("ui.seek") { document, arguments, _ in
            let frame = try arguments.int("frame")
            guard frame <= document.project.duration else {
                throw RPCFailure(-32602, "frame must be within the timeline")
            }
            document.showTimelineViewer()
            document.preview.seek(frame)
            return .bool(true)
        }
        handle("ui.frame") { document, arguments, _ in
            let frame = arguments.optionalInt("frame")
            if let frame, frame >= document.project.duration {
                throw RPCFailure(-32602, "frame must be within the timeline")
            }
            var maximum = 1_280
            if let width = arguments.bool("phone") ? 390 : arguments.optionalInt("width") {
                let project = document.project
                maximum = Int((Double(width) * Double(max(project.width, project.height)) / Double(max(1, project.width))).rounded())
            }
            let capture = try await document.captureAgentFrame(at: frame, maximumDimension: maximum)
            var path = capture.url.path
            if let out = arguments.optionalString("out") {
                // `--out` (#507-25b): the caller's own file, as well as the kept copy.
                let url = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                try FileManager.default.copyItem(at: capture.url, to: url)
                path = url.path
            }
            return .object([
                "path": .string(path), "frame": .integer(capture.frame),
                "width": .integer(capture.width), "height": .integer(capture.height),
            ])
        }
    }

    /// `a`, or `a (3 items: a, b, c)` when several are selected.
    private var selectionText: String {
        guard let selectedID else { return "none" }
        guard selectedIDs.count > 1 else { return selectedID }
        return "\(selectedID) (\(selectedIDs.count) items: \(selectedIDs.joined(separator: ", ")))"
    }

    func showLibraryTab(_ tab: LibraryTab) {
        DebugLog.write("ui", "library panel \(ui.libraryTab.rawValue) → \(tab.rawValue)")
        ui.libraryTab = tab
        ui.pluginPanel = nil
    }

    func contextText() -> String {
        """
        [BashCut context]
        project: \(fileURL?.path ?? "none open yet (use project create or project open)")
        rev: \(project.revision)
        selection: \(selectionText)
        playhead: \(playhead) frames
        \(pluginActionsText())
        [/BashCut context]
        """
    }

    /// Installed plugin actions in one line each, for agent prompts: id, title, when, and parameters with their
    /// ranges and defaults.
    func pluginActionsText() -> String {
        guard !plugins.actions.isEmpty else { return "plugin actions: none installed (plugins search finds more)" }
        let lines = plugins.actions.map { action -> String in
            let params = action.params.map { option -> String in
                var text = "\(option.id) \(option.type.rawValue)"
                if let minimum = option.minimum, let maximum = option.maximum { text += " \(minimum)…\(maximum)" }
                if let value = option.defaultValue, let json = try? JSONEncoder().encode(value) {
                    text += " =" + (String(bytes: json, encoding: .utf8) ?? "")
                }
                return text
            }
            return "- \(action.id) (\(action.plugin.manifest.displayName)): \(action.title)"
                + (action.spec.when.map { "; when \($0)" } ?? "")
                + (params.isEmpty ? "" : "; params " + params.joined(separator: ", "))
        }
        return (["plugin actions (bashcut plugins run ID --params JSON):"] + lines).joined(separator: "\n")
    }
    func markAgentChanges(from before: Project, author: Author, label: String) {
        let changes = project.itemChanges(from: before)
        agentChange = AgentChangeRecord(
            author: author, label: label, beforeRevision: before.revision,
            afterRevision: project.revision, changes: changes, command: CommandCaller.method)
        agentChangedIDs = Set(changes.compactMap { $0.after == nil ? nil : $0.itemID })
    }

    func clearAgentChange() {
        agentChange = nil
        agentChangedIDs.removeAll()
        ui.showAgentChanges = false
    }

    func restoreLatestAgentChangeFromHistory() {
        guard let entry = history.lastUndo, entry.author.isAgent, let before = entry.before
        else { return clearAgentChange() }
        markAgentChanges(from: before, author: entry.author, label: entry.label)
    }

    var canUndoAgentChange: Bool {
        guard let change = agentChange, change.afterRevision == project.revision,
            let entry = history.lastUndo
        else { return false }
        return entry.author == change.author && entry.label == change.label
    }

    func undoAgentChange() {
        guard canUndoAgentChange else { return }
        undo()
    }
}
