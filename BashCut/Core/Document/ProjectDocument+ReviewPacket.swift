import BashCutAutomation
import BashCutEngine
import BashCutProject
import BashCutStorage
import Foundation

/// `review.packet` (P1-E4, spec 13 §6.2): a folder a fresh critic reviews from without the editor's reasons, one per
/// audit point. `draft` (the default): the plan, what changed since the last review round, the issues with the round
/// diff, cut facts, where words land against cuts, the hook, plan coverage, the checks to judge (the kit's generic
/// ones and the plan's), a contact sheet of the cuts and titles, and what was measured. `strategy`: the brief (with
/// what was inferred), the plan, the checks and what is missing. `process`: the run checklist, the run log and the
/// timeline changes. Rebuilt per revision in the cache.
extension ProjectDocument {
    func reviewPacket(_ arguments: CommandArguments) async throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Save the project first") }
        let point = arguments.optionalString("point") ?? "draft"
        let name = point == "draft" ? "r\(project.revision)" : "r\(project.revision)-\(point)"
        let folder = ProjectCache.url(.reviewPackets, projectRoot: root).appendingPathComponent(name, isDirectory: true)
        switch point {
        case "strategy": return try await strategyPacket(folder)
        case "process": return try processPacket(folder)
        default: return try await draftPacket(folder)
        }
    }

    /// The checks a critic judges: the kit's generic ones, then the plan's (a recipe's), with the plan's promise.
    private var packetChecks: JSONValue {
        let plan = project["plan"]?.object ?? [:]
        return .object([
            "generic": .array(WorkflowChecklist.genericChecks), "plan": plan["checks"] ?? .array([]),
            "promise": plan["promise"] ?? .null,
        ])
    }

    private func draftPacket(_ folder: URL) async throws -> JSONValue {
        guard project.duration > 0 else { throw RPCFailure(-32602, "The timeline is empty") }
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await loadReviewTranscripts()
        let issues = reviewIssues()
        let previous = reviewRounds.last { $0.revision != project.revision }
        let (words, wordSource) = await syncWords()
        var notMeasured: [String] = []
        if reviewPicture?.revision != project.revision { notMeasured.append("picture (review measure)") }
        if reviewLoudness?.revision != project.revision { notMeasured.append("loudness (normalized export)") }
        if wordSource == "none" { notMeasured.append("words (media transcribe or captions)") }
        let coverage = TimelineReview.coverage(project, context: reviewContext())
        let files: [(String, JSONValue)] = [
            ("plan.json", .object([
                "brief": project["brief"] ?? .null, "plan": project["plan"] ?? .null, "review": project["review"] ?? .null,
                "outputs": .array(project.outputPresets.map(JSONValue.string)),
                "durationSeconds": .number(Double(project.duration) / project.fps.value),
            ])),
            ("checks.json", packetChecks),
            ("digest.json", previous.map { round in
                var diff = ProjectDerivation.diff(round.project, project).object
                diff["sinceRev"] = .integer(round.revision)
                return .object(diff)
            } ?? .object(["sinceRev": .null, "note": .string("No earlier review round in this session")])),
            ("issues.json", .object([
                "issues": .array(issues.map(\.json)), "summary": ReviewSummary(issues, coverage: coverage).json,
                "diff": previous.map { ReviewRounds.diff(before: $0.issues, after: issues) } ?? .null,
            ])),
            ("shots.json", ReviewShots.json(project, picture: reviewPicture, summary: true)),
            ("word-landing.json", {
                var sync = ReviewSync.json(project, words: words, kinds: [.cuts, .text]).object
                sync["wordSource"] = .string(wordSource)
                return .object(sync)
            }()),
            ("coverage.json", .object([
                "clips": PlanCoverage.coverage(project), "script": PlanCoverage.scriptCheck(project, words: words),
            ])),
            ("measured.json", .object([
                "picture": reviewPicture.map { $0.revision == project.revision ? .bool(true) : .string("stale") } ?? .bool(false),
                "loudness": reviewLoudness.map { loudness in
                    .object(["integratedLUFS": .number(loudness.integratedLUFS), "truePeakDbTP": .number(loudness.truePeakDbTP),
                             "revision": .integer(loudness.revision)])
                } ?? .null,
                "notMeasured": .array(notMeasured.map(JSONValue.string)),
            ])),
        ]
        var written = try Self.writePacketFiles(files, to: folder)
        written += await copySheets(to: folder)
        let readme = """
            # Review packet, revision \(project.revision)

            - plan.json: the brief, the plan, the review profile and the outputs
            - checks.json: the checks to judge as a viewer — the kit's generic ones, the plan's, and the promise
            - digest.json: what changed since the last review round
            - issues.json: measured issues, counts and the round diff
            - shots.json, word-landing.json: shots and cuts on Main, words against cuts and titles
            - coverage.json: the described shot each clip plays, and the plan's script beats against the words heard
            - measured.json: what was measured and what was not
            - sheet-*.png: a contact sheet at every cut and title

            """
        try readme.write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return .object([
            "path": .string(folder.path), "revision": .integer(project.revision), "point": .string("draft"),
            "files": .array((["README.md"] + written).map(JSONValue.string)),
            "notMeasured": .array(notMeasured.map(JSONValue.string)),
        ])
    }

    /// The strategy audit's folder (after the story stage): brief, plan, checks and a sheet of the timeline when it
    /// has one; what the critic would need but the project lacks is listed in `missing`.
    private func strategyPacket(_ folder: URL) async throws -> JSONValue {
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let brief = project["brief"]?.object ?? [:]
        let plan = project["plan"]?.object ?? [:]
        let inferred = brief.filter { $0.value.object["status"] == .string("inferred") }.keys.sorted()
        var missing: [String] = []
        if brief.isEmpty { missing.append("brief (project set-data brief)") }
        if plan.isEmpty { missing.append("plan (project set-data plan)") }
        if plan["promise"] == nil { missing.append("plan.promise {hook, payoff}") }
        if (plan["sections"]?.array ?? []).isEmpty { missing.append("plan.sections") }
        if plan["mode"] == .string("create"), (plan["options"]?.array ?? []).isEmpty {
            missing.append("plan.options (2–3 story options in create mode)")
        }
        let files: [(String, JSONValue)] = [
            ("brief.json", .object([
                "brief": project["brief"] ?? .null, "inferred": .array(inferred.map(JSONValue.string)),
                "outputs": .array(project.outputPresets.map(JSONValue.string)),
                "contentLanguage": project["contentLanguage"] ?? .null,
            ])),
            ("plan.json", project["plan"] ?? .null),
            ("checks.json", packetChecks),
        ]
        var written = try Self.writePacketFiles(files, to: folder)
        let sheets = project.duration > 0 ? await copySheets(to: folder) : []
        if sheets.isEmpty { missing.append("story sheet (attach one: media frames --sheet of the planned shots)") }
        written += sheets
        let readme = """
            # Strategy packet, revision \(project.revision)

            Judge the plan before the rough cut: one message; promise.payoff answers promise.hook; it fits the brief;
            the plan's checks that apply to a plan. Fields in brief.json › inferred were guessed: check each guess.

            - brief.json: the brief, the fields inferred rather than stated, the outputs and the language
            - plan.json: the plan (mode, options, promise, sections, shots, checks)
            - checks.json: the kit's generic checks, the plan's, and the promise
            - sheet-*.png: the timeline so far, when there is one

            Missing: \(missing.isEmpty ? "nothing" : missing.joined(separator: "; "))

            """
        try readme.write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return .object([
            "path": .string(folder.path), "revision": .integer(project.revision), "point": .string("strategy"),
            "files": .array((["README.md"] + written).map(JSONValue.string)),
            "missing": .array(missing.map(JSONValue.string)),
        ])
    }

    /// The process audit's folder (after export): the derived checklist, the current run's log and the timeline
    /// changes with their reasons.
    private func processPacket(_ folder: URL) throws -> JSONValue {
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files: [(String, JSONValue)] = [
            ("checklist.json", runChecklist),
            ("run-log.json", runLog?.read() ?? .null),
            ("changes.json", TimelineChanges.json(history: history, limit: 200, isAgent: \.isAgent)),
        ]
        let written = try Self.writePacketFiles(files, to: folder)
        let readme = """
            # Process packet, revision \(project.revision)

            Judge how the edit was made: required stages skipped, stages done without evidence, skills not read,
            audits missing or self-run, and claims in the hand-off summary the log does not back. Write the lessons
            for bc:self-learn.

            - checklist.json: run checklist (stages, skills read, status, evidence, audits, open)
            - run-log.json: the current run's log
            - changes.json: timeline changes (label, author, why, evidence)

            """
        try readme.write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return .object([
            "path": .string(folder.path), "revision": .integer(project.revision), "point": .string("process"),
            "files": .array((["README.md"] + written).map(JSONValue.string)),
        ])
    }

    private static func writePacketFiles(_ files: [(String, JSONValue)], to folder: URL) throws -> [String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        for (name, value) in files { try encoder.encode(value).write(to: folder.appendingPathComponent(name), options: .atomic) }
        return files.map(\.0)
    }

    /// A contact sheet at every cut and title, copied in as `sheet-N.png`.
    private func copySheets(to folder: URL) async -> [String] {
        guard let sheet = try? await timelineSheet(CommandArguments(["cuts": .bool(true), "text": .bool(true)])) else { return [] }
        var written: [String] = []
        for (index, entry) in (sheet.object["sheets"]?.array ?? []).enumerated() {
            guard let path = entry.object["path"]?.string else { continue }
            let name = "sheet-\(index + 1).png"
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: folder.appendingPathComponent(name))
            written.append(name)
        }
        return written
    }
}
