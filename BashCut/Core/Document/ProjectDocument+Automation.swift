import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutInterchange
import BashCutProject
import Foundation

extension ProjectDocument {
    typealias CommandBody = @MainActor (ProjectDocument, CommandArguments, Author?) async throws -> JSONValue
    typealias AuthoredCommandBody = @MainActor (ProjectDocument, CommandArguments, Author) async throws -> JSONValue

    func startAutomation() {
        registerReadCommands()
        registerProjectCommands()
        registerCaptionCommands()
        registerCapabilityCommands()
        registerDialogCommands()
        registerDialogs()
        registerEditCommands()
        registerLayerCommands()
        registerSpeedCommands()
        registerAdjustmentCommands()
        registerImportCommands()
        registerProxyCommands()
        registerPrivilegedCommands()
        registerUICommands()
        registerUIActionCommands()
        registerToolCommands()
        registerPluginCommands()
        plugins.jobs = jobs
        plugins.service.optionValues = { [weak self] plugin in
            await MainActor.run { self?.pluginOptionValues(plugin) ?? [:] }
        }
        plugins.refresh(projectRoot: nil)
        emitPluginEvent(.appLaunched)
        assert(registry.unhandledCommands.isEmpty, "Unhandled commands: \(registry.unhandledCommands)")
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

    /// Edit and privileged commands: the registry has already rejected requests without a session token.
    func handleAuthored(_ method: String, _ body: @escaping AuthoredCommandBody) {
        handle(method) { document, arguments, author in
            guard let author else { throw RPCFailure(-32001, "A live agent session token is required") }
            return try await body(document, arguments, author)
        }
    }

    private func registerReadCommands() {
        handle("context.get") { document, _, _ in
            .object([
                "project": document.fileURL.map { .string($0.path) } ?? .null,
                "rev": .integer(document.project.revision), "playhead": .integer(document.playhead),
                "selection": document.selectedID.map(JSONValue.string) ?? .null,
                "selectedTrack": document.selectedTrackID.map(JSONValue.string) ?? .null,
                "dirty": .bool(document.dirty), "conflict": .bool(document.conflict),
                "busy": .bool(document.busy), "saving": .bool(document.saving),
            ])
        }
        handle("project.get") { document, _, _ in .object(document.project.fields) }
        handle("timeline.get") { document, arguments, _ in
            if arguments.optionalString("format") == "text" { return .string(document.timelineText()) }
            let project = document.project
            return .object([
                "rev": .integer(project.revision), "format": project["format"] ?? .null,
                "tracks": project["tracks"] ?? .array([]),
                "luts": .array(project.colorLUTs.map { .object($0.fields) }),
                "looks": .array(project.looks.map(\.json)), "styleKits": .array(project.styleKits.map(\.json)),
            ])
        }
        handle("media.list") { document, _, _ in
            .array(document.project.media.map { media in
                var fields = media.fields
                fields["proxy"] = .string(document.proxyState(media).rawValue)
                return .object(fields)
            })
        }
        handle("review.run") { document, _, _ in
            .array(
                TimelineReview.run(document.project).map { issue in
                    .object([
                        "id": .string(issue.id), "title": .string(issue.title),
                        "detail": .string(issue.detail), "frame": .integer(issue.frame),
                    ])
                })
        }
        handle("export.status") { document, _, _ in document.exports.statusJSON }
    }

    private func registerEditCommands() {
        handleAuthored("timeline.apply") { document, arguments, author in
            let label = try arguments.string("label")
            let revision = try document.commit(
                .group(label: label, author: author, ops: WireOperations.decode(arguments.value("ops"))),
                label: label, author: author, baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(revision)])
        }
        handleAuthored("timeline.undo") { document, arguments, author in
            .object(["rev": .integer(try document.commitUndo(author: author, baseRevision: arguments.int("baseRev")))])
        }
        handleAuthored("timeline.redo") { document, arguments, author in
            .object(["rev": .integer(try document.commitRedo(author: author, baseRevision: arguments.int("baseRev")))])
        }
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

    private func registerPrivilegedCommands() {
        handleAuthored("export.start") { document, arguments, author in
            guard let preset = ExportPreset(argument: try arguments.string("preset")) else {
                throw RPCFailure(-32602, "Unknown export preset")
            }
            let (name, directory) = try document.exportDestination(arguments)
            guard document.project.duration > 0 else { throw RPCFailure(-32602, "The timeline is empty") }
            let includeSubRip = arguments.bool("includeSRT")
            let normalizeAudio = arguments.bool("normalizeAudio")
            let output = directory.appendingPathComponent(name).appendingPathExtension(preset.fileExtension)
            let approval = try document.queuePrivilegedApproval(
                method: "export.start", author: author,
                arguments: [
                    "captions": includeSubRip ? "include .srt" : "burned in only",
                    "normalization": normalizeAudio ? "two-pass LUFS" : "off",
                    "output": output.path, "preset": preset.title,
                ]
            ) { [weak document] in
                guard let document else { throw RPCFailure(-32000, "Editor closed") }
                try document.startExportAuthorized(
                    name: name, preset: preset, directory: directory, includeSubRip: includeSubRip,
                    normalizeAudio: normalizeAudio, author: author)
            }
            if !approval.autoApproved {
                document.message = String(localized: "Waiting for approval: export.start")
            }
            return approval.json(output: output)
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
            let id = arguments.optionalString("item")
            if let id, !document.project.tracks.flatMap(\.items).contains(where: { $0.id == id }) {
                throw RPCFailure(-32602, "Unknown item")
            }
            if let track = arguments.optionalString("track") {
                guard document.project.tracks.contains(where: { $0.id == track }) else {
                    throw RPCFailure(-32602, "Unknown layer \(track)")
                }
                document.selectedTrackID = track
                if id != nil { document.selectedID = id }
            } else {
                document.selectedID = id
            }
            return .bool(true)
        }
        handle("ui.seek") { document, arguments, _ in
            let frame = try arguments.int("frame")
            guard frame <= document.project.duration else {
                throw RPCFailure(-32602, "frame must be within the timeline")
            }
            document.preview.seek(frame)
            return .bool(true)
        }
        handle("ui.panel") { document, arguments, _ in
            let name = try arguments.string("panel")
            guard let tab = LibraryTab(panelName: name) else {
                throw RPCFailure(-32602, "Unknown panel \(name)")
            }
            document.showLibraryTab(tab)
            return .bool(true)
        }
        handle("ui.notify") { document, arguments, _ in
            document.message = String(try arguments.string("message").prefix(2000))
            return .bool(true)
        }
    }

    func showLibraryTab(_ tab: LibraryTab) {
        DebugLog.write("ui", "library panel \(ui.libraryTab.rawValue) → \(tab.rawValue)")
        ui.libraryTab = tab
    }

    func timelineText() -> String {
        var lines = [
            "project \(project.name) rev \(project.revision) \(project.width)x\(project.height) \(project.fps.value)fps"
        ]
        for track in project.tracks {
            for item in track.items.sorted(by: { $0.at < $1.at }) {
                let media = item.mediaID ?? (track.isAdjustment ? "adjustment" : "text")
                lines.append(
                    "\(track.role.uppercased()) \(item.id) \(item.at)-\(item.end) media=\(media) in=\(item.sourceIn) \(item.text)"
                )
            }
        }
        return lines.joined(separator: "\n")
    }

    func contextText() -> String {
        """
        [BashCut context]
        project: \(fileURL?.path ?? "unsaved")
        rev: \(project.revision)
        selection: \(selectedID ?? "none")
        playhead: \(playhead) frames
        [/BashCut context]
        """
    }
    func markAgentChanges(from before: Project, author: Author, label: String) {
        let changes = project.itemChanges(from: before)
        agentChange = AgentChangeRecord(
            author: author, label: label, beforeRevision: before.revision,
            afterRevision: project.revision, changes: changes)
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
