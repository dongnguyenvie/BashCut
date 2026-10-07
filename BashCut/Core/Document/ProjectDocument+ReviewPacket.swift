import BashCutAutomation
import BashCutEngine
import BashCutProject
import Foundation

/// `review.packet` (P1-E4): a folder a fresh critic reviews from without the editor's reasons — the plan, what changed
/// since the last review round, the issues with the round diff, cut facts, where words land against cuts, the hook,
/// plan coverage, a contact sheet of the cuts and titles, and what was measured. Rebuilt per revision in the cache.
extension ProjectDocument {
    func reviewPacket() async throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Save the project first") }
        guard project.duration > 0 else { throw RPCFailure(-32602, "The timeline is empty") }
        let folder = ProjectCache.url(.reviewPackets, projectRoot: root).appendingPathComponent("r\(project.revision)", isDirectory: true)
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
        let files: [(String, JSONValue)] = [
            ("plan.json", .object([
                "brief": project["brief"] ?? .null, "plan": project["plan"] ?? .null, "review": project["review"] ?? .null,
                "outputs": .array(project.outputPresets.map(JSONValue.string)),
                "durationSeconds": .number(Double(project.duration) / project.fps.value),
            ])),
            ("digest.json", previous.map { round in
                var diff = ProjectDerivation.diff(round.project, project).object
                diff["sinceRev"] = .integer(round.revision)
                return .object(diff)
            } ?? .object(["sinceRev": .null, "note": .string("No earlier review round in this session")])),
            ("issues.json", .object([
                "issues": .array(issues.map(\.json)), "summary": ReviewSummary(issues).json,
                "diff": previous.map { ReviewRounds.diff(before: $0.issues, after: issues) } ?? .null,
            ])),
            ("cuts.json", ReviewCuts.json(project)),
            ("word-landing.json", {
                var sync = ReviewSync.json(project, words: words, kinds: [.cuts, .text]).object
                sync["wordSource"] = .string(wordSource)
                return .object(sync)
            }()),
            ("hook.json", ReviewHook.json(project, context: reviewContext(), words: words)),
            ("coverage.json", .object([
                "shots": PlanCoverage.coverage(project), "script": PlanCoverage.scriptCheck(project, words: words),
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        for (name, value) in files { try encoder.encode(value).write(to: folder.appendingPathComponent(name), options: .atomic) }
        var written = files.map(\.0)
        if let sheet = try? await timelineSheet(CommandArguments(["cuts": .bool(true), "text": .bool(true)])) {
            for (index, entry) in (sheet.object["sheets"]?.array ?? []).enumerated() {
                guard let path = entry.object["path"]?.string else { continue }
                let name = "sheet-\(index + 1).png"
                try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: folder.appendingPathComponent(name))
                written.append(name)
            }
        }
        let readme = """
            # Review packet, revision \(project.revision)

            - plan.json: the brief, the plan, the review profile and the outputs
            - digest.json: what changed since the last review round
            - issues.json: measured issues, counts and the round diff
            - cuts.json, word-landing.json, hook.json: cut facts, words against cuts and titles, the opening and close
            - coverage.json: planned shots and script beats against what is on the timeline
            - measured.json: what was measured and what was not
            - sheet-*.png: a contact sheet at every cut and title

            """
        try readme.write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return .object([
            "path": .string(folder.path), "revision": .integer(project.revision),
            "files": .array((["README.md"] + written).map(JSONValue.string)),
            "notMeasured": .array(notMeasured.map(JSONValue.string)),
        ])
    }
}
