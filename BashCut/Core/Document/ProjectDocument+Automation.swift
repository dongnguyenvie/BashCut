import BashCutAutomation
import BashCutEngine
import BashCutProject
import Foundation

extension ProjectDocument {
    func startAutomation() {
        registerReadCommands()
        registerCaptionCommands()
        registerEditCommands()
        registerPrivilegedCommands()
        registerUICommands()
        Task {
            do {
                try await automationServer.start(path: AutomationPaths.socket) { [registry] in
                    await registry.handle($0)
                }
            } catch { message = error.localizedDescription }
        }
    }

    private func registerReadCommands() {
        registry.register("context.get") { [weak self] _, _ in
            guard let self else { throw RPCFailure(-32000, "Editor closed") }
            return .object([
                "project": fileURL.map { .string($0.path) } ?? .null,
                "rev": .integer(project.revision), "playhead": .integer(playhead),
                "selection": selectedID.map(JSONValue.string) ?? .null,
            ])
        }
        registry.register("project.get") { [weak self] _, _ in
            guard let self else { throw RPCFailure(-32000, "Editor closed") }
            return .object(project.fields)
        }
        registry.register("timeline.get") { [weak self] params, _ in
            guard let self else { throw RPCFailure(-32000, "Editor closed") }
            if params["format"]?.string == "text" { return .string(timelineText()) }
            return .object([
                "rev": .integer(project.revision), "format": project["format"] ?? .null,
                "tracks": project["tracks"] ?? .array([]),
            ])
        }
        registry.register("media.list") { [weak self] _, _ in self?.project["media"] ?? .array([]) }
        registry.register("review.run") { [weak self] _, _ in
            guard let self else { throw RPCFailure(-32000, "Editor closed") }
            return .array(
                TimelineReview.run(project).map { issue in
                    .object([
                        "id": .string(issue.id), "title": .string(issue.title),
                        "detail": .string(issue.detail), "frame": .integer(issue.frame),
                    ])
                })
        }
        registry.register("export.status") { [weak self] _, _ in
            guard let self else { throw RPCFailure(-32000, "Editor closed") }
            var result: [String: JSONValue] = [
                "state": .string(exporting ? "running" : exportReport == nil ? "idle" : "completed"),
                "progress": .number(exportProgress),
            ]
            if let report = exportReport {
                result["preset"] = .string(report.preset.rawValue)
                result["path"] = .string(report.receipt.url.path)
                result["duration"] = .number(report.receipt.duration)
                result["bytes"] = .integer(Int(report.receipt.bytes))
                result["cuts"] = .integer(report.cutCount)
                result["captions"] = .integer(report.captionCount)
                result["includedSRT"] = .bool(report.includedSubRip)
                result["speechCoverage"] = .number(report.speechCoverage)
                result["completedAt"] = .string(
                    ISO8601DateFormatter().string(from: report.completedAt))
                if let comparison = report.comparison {
                    var values: [String: JSONValue] = [
                        "duration": .number(comparison.duration),
                        "bytes": .integer(Int(comparison.bytes)),
                        "cuts": .integer(comparison.cutCount),
                        "captions": .integer(comparison.captionCount),
                        "speechCoverage": .number(comparison.speechCoverage),
                    ]
                    values["lufs"] = comparison.integratedLUFS.map(JSONValue.number) ?? .null
                    result["comparison"] = .object(values)
                } else {
                    result["comparison"] = .null
                }
                if let loudness = report.loudness {
                    result["lufs"] = .number(loudness.integratedLUFS)
                    result["truePeakDbTP"] = .number(loudness.truePeakDbTP)
                    result["loudnessVerified"] = .bool(report.loudnessVerified)
                    if let gain = report.appliedGainDb { result["normalizationGainDb"] = .number(gain) }
                } else {
                    result["lufs"] = .null
                }
            }
            return .object(result)
        }
    }

    private func registerEditCommands() {
        registry.register("timeline.apply") { [weak self] params, author in
            guard let self, let author, let base = params["baseRev"]?.int,
                let ops = params["ops"], let label = params["label"]?.string, !label.isEmpty
            else {
                throw RPCFailure(-32602, "baseRev, ops and a nonempty label are required")
            }
            guard !busy, !conflict, !timelineGestureActive else {
                throw RPCFailure(-32003, "The editor is busy or has a file conflict; retry later")
            }
            let before = project
            try history.apply(
                .group(label: label, author: author, ops: WireOperations.decode(ops)),
                label: label, author: author, baseRevision: base)
            markAgentChanges(from: before, author: author, label: label)
            dirty = true
            rebuild()
            message = author.rawValue.capitalized + ": " + label
            return .object(["rev": .integer(project.revision)])
        }
        for name in ["timeline.undo", "timeline.redo"] {
            registry.register(name) { [weak self] params, author in
                guard let self, let author, let base = params["baseRev"]?.int else {
                    throw RPCFailure(-32602, "baseRev is required")
                }
                guard !busy, !conflict, !timelineGestureActive else {
                    throw RPCFailure(-32003, "Editor busy")
                }
                guard base == project.revision else {
                    throw ProjectError.staleRevision(expected: base, actual: project.revision)
                }
                let before = project
                if name == "timeline.undo" { try history.undo() } else { try history.redo() }
                markAgentChanges(
                    from: before, author: author,
                    label: name == "timeline.undo" ? "Undo" : "Redo")
                dirty = true
                rebuild()
                return .object(["rev": .integer(project.revision)])
            }
        }
    }

    private func registerPrivilegedCommands() {
        registry.register("export.start") { [weak self] params, author in
            guard let self, let author, let root = fileURL?.deletingLastPathComponent(), project.duration > 0,
                let presetName = params["preset"]?.string, let preset = ExportPreset(argument: presetName),
                let rawName = params["name"]?.string
            else {
                throw RPCFailure(-32602, "preset, name and a nonempty saved timeline are required")
            }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.contains("/"), !name.contains(":"), name.count <= 180 else {
                throw RPCFailure(-32602, "name must be 1–180 characters without slashes or colons")
            }
            guard !exporting else { throw RPCFailure(-32003, "An export is already running") }
            let directory: URL
            if let value = params["directory"]?.string, !value.isEmpty {
                directory = URL(fileURLWithPath: value, relativeTo: root).standardizedFileURL
            } else {
                directory = root.appendingPathComponent("render", isDirectory: true)
            }
            let includeSubRip = params["includeSRT"] == .bool(true)
            let normalizeAudio = params["normalizeAudio"] == .bool(true)
            let output = directory.appendingPathComponent(name).appendingPathExtension(preset.fileExtension)
            let approval = try queuePrivilegedApproval(
                method: "export.start", author: author,
                arguments: [
                    "captions": includeSubRip ? "include .srt" : "burned in only",
                    "normalization": normalizeAudio ? "two-pass LUFS" : "off",
                    "output": output.path, "preset": preset.title,
                ]
            ) { [weak self] in
                guard let self else { throw RPCFailure(-32000, "Editor closed") }
                try startExportAuthorized(
                    name: name, preset: preset, directory: directory, includeSubRip: includeSubRip,
                    normalizeAudio: normalizeAudio)
            }
            message = String(localized: "Waiting for approval: export.start")
            return .object([
                "approval": .string("pending"), "requestId": .string(approval.uuidString),
                "output": .string(output.path),
            ])
        }
        registry.register("export.otio") { [weak self] params, author in
            guard let self, let author, let root = fileURL?.deletingLastPathComponent(),
                let rawName = params["name"]?.string
            else { throw RPCFailure(-32602, "name and a saved project are required") }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.contains("/"), !name.contains(":"), name.count <= 180 else {
                throw RPCFailure(-32602, "name must be 1–180 characters without slashes or colons")
            }
            let directory = params["directory"]?.string.map {
                URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL
            } ?? root.appendingPathComponent("render", isDirectory: true)
            let output = directory.appendingPathComponent(name).appendingPathExtension("otio")
            guard !FileManager.default.fileExists(atPath: output.path) else {
                throw RPCFailure(-32602, "The OTIO output already exists")
            }
            let approval = try queuePrivilegedApproval(
                method: "export.otio", author: author,
                arguments: ["output": output.path, "format": "OpenTimelineIO"]
            ) { [weak self] in
                guard let self else { throw RPCFailure(-32000, "Editor closed") }
                try writeOTIO(to: output)
                message = String(localized: "OTIO exported")
            }
            message = String(localized: "Waiting for approval: export.otio")
            return .object([
                "approval": .string("pending"), "requestId": .string(approval.uuidString),
                "output": .string(output.path),
            ])
        }
    }

    private func registerUICommands() {
        registry.register("ui.select") { [weak self] params, _ in
            guard let self else { throw RPCFailure(-32000, "Editor closed") }
            let id = params["item"]?.string
            if let id, !project.tracks.flatMap(\.items).contains(where: { $0.id == id }) {
                throw RPCFailure(-32602, "Unknown item")
            }
            selectedID = id
            return .bool(true)
        }
        registry.register("ui.seek") { [weak self] params, _ in
            guard let self, let frame = params["frame"]?.int, frame >= 0, frame <= project.duration else {
                throw RPCFailure(-32602, "frame must be within the timeline")
            }
            seek(frame)
            return .bool(true)
        }
        registry.register("ui.notify") { [weak self] params, _ in
            self?.message = String((params["message"]?.string ?? "").prefix(2000))
            return .bool(true)
        }
    }

    func timelineText() -> String {
        var lines = [
            "project \(project.name) rev \(project.revision) \(project.width)x\(project.height) \(project.fps.value)fps"
        ]
        for track in project.tracks {
            for item in track.items.sorted(by: { $0.at < $1.at }) {
                lines.append(
                    "\(track.role.uppercased()) \(item.id) \(item.at)-\(item.end) media=\(item.mediaID ?? "text") in=\(item.sourceIn) \(item.text)"
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
        showAgentChanges = false
    }

    func restoreLatestAgentChangeFromHistory() {
        guard let entry = history.undoEntries.last,
            [.claude, .codex, .model].contains(entry.author),
            case .restore(let before) = entry.operation
        else { return clearAgentChange() }
        markAgentChanges(from: before, author: entry.author, label: entry.label)
    }

    var canUndoAgentChange: Bool {
        guard let change = agentChange, change.afterRevision == project.revision,
            let entry = history.undoEntries.last
        else { return false }
        return entry.author == change.author && entry.label == change.label
    }

    func undoAgentChange() {
        guard canUndoAgentChange else { return }
        do {
            try history.undo()
            dirty = true
            clearAgentChange()
            rebuild()
        } catch { message = error.localizedDescription }
    }
}
