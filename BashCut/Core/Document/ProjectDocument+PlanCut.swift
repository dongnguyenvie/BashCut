import BashCutAutomation
import BashCutEngine
import BashCutProject
import Foundation

/// `plan.check` and `plan.apply`: the edit as one list, checked on a scratch copy and built as one undoable edit.
extension ProjectDocument {
    func registerPlanCutCommands() {
        handle("plan.check") { document, arguments, _ in
            let spec = try document.planCutSpec(arguments)
            return try await document.checkPlanCut(spec).json
        }
        handleAuthored("plan.apply") { document, arguments, author in
            let spec = try document.planCutSpec(arguments)
            let baseRevision = try arguments.int("baseRev")
            let check = try await document.checkPlanCut(spec)
            if arguments.bool("dryRun") { return check.json }
            guard check.errors.isEmpty, let built = check.built else {
                throw RPCFailure(-32602, "The edit list has errors; fix them (plan check lists them)", data: .object([
                    "problems": .array(check.errors.map(\.json)),
                    "remediation": .object(["command": .string("plan.check")]),
                ]))
            }
            var operations = built.planner.operations
            if let cut = arguments["cut"], cut != .null {
                var plan = document.project["plan"]?.object ?? [:]
                plan["cut"] = cut
                operations.insert(.setProjectProperties(patch: ["plan": .object(plan)]), at: 0)
            }
            let label = "Apply edit list"
            let result = try document.commitEdit(
                .group(label: label, author: author, ops: operations), label: label, author: author,
                baseRevision: baseRevision, note: try Self.editNote(arguments))
            var json = check.json.object
            json["rev"] = .integer(result.revision)
            json["changed"] = .bool(result.changed)
            json["review"] = nil
            json["items"] = .array(document.project.tracks.flatMap(\.items)
                .filter { $0.fields[PlanCut.tag] != nil && $0.fields["linkedVideo"] == nil }
                .map { .object(["item": .string($0.id), "entry": $0.fields[PlanCut.tag] ?? .null]) })
            return .object(json)
        }
    }

    /// The list from `cut`, else `plan.cut`.
    func planCutSpec(_ arguments: CommandArguments) throws -> PlanCut.Spec {
        let value = arguments["cut"].flatMap { $0 == .null ? nil : $0 } ?? project["plan"]?.object["cut"]
        guard let value else {
            throw RPCFailure(-32602, "No edit list: give cut (a JSON file) or set plan.cut", data: .object([
                "remediation": .object(["command": .string("project.set-data"), "hint": .string("plan --merge with {cut: …}")]),
            ]))
        }
        do { return try PlanCut.decode(value) } catch let error as ProjectError { throw RPCFailure.invalid(error) }
    }

    /// The library text presets the titles name (renderer presets need none), and an error for a name that is
    /// neither.
    func planTextPresets(_ spec: PlanCut.Spec) -> ([String: LibraryTextPreset], [PlanCut.Problem]) {
        var presets: [String: LibraryTextPreset] = [:]
        var problems: [PlanCut.Problem] = []
        let catalog = libraryCatalog
        let named = spec.titles.map { ($0.id, $0.preset) } + [("captions", spec.captions?.preset)]
        for (entry, preset) in named {
            guard let name = preset, !TextPreset.all.contains(name), presets[name] == nil else { continue }
            if let item = try? catalog.item(name), item.kind == .textPreset, let look = try? textPreset(item) {
                presets[name] = look
            } else {
                problems.append(PlanCut.Problem(
                    id: "unknown-preset", severity: "error", entry: entry,
                    detail: "No text preset \(name): use \(TextPreset.all.joined(separator: ", ")) or a text-preset ID "
                        + "from library list --kind text-preset"))
            }
        }
        return (presets, problems)
    }

    /// Titles whose font lacks letters of the project's content language, or is not on this Mac.
    func planFontProblems(_ after: Project) -> [PlanCut.Problem] {
        after.tracks.flatMap(\.items).compactMap { item -> PlanCut.Problem? in
            guard let entry = item.fields[PlanCut.tag]?.string, item["text"] != nil else { return nil }
            let font = item["textStyle"]?.object["font"]?.string ?? TextPresetStyle.font(item.textPreset)
            if !ProjectFonts.isAvailable(font) {
                return PlanCut.Problem(
                    id: "font-missing", severity: "error", entry: entry,
                    detail: "Font \(font) is not on this Mac (it would draw as Helvetica): pick one from fonts list")
            }
            guard !contentLanguage.isEmpty, ProjectFonts.covers(font, language: contentLanguage) == false else { return nil }
            return PlanCut.Problem(
                id: "font-language", severity: "error", entry: entry,
                detail: "Font \(font) lacks letters of \(contentLanguage): pick one from fonts list --covers, such as "
                    + "System-CondensedBlack or Arial-BoldMT", facts: ["font": .string(font)])
        }
    }

    struct PlanCutCheck {
        var built: (planner: LayerPlanner, placements: [PlanCut.Placement], kept: [String])?
        var problems: [PlanCut.Problem]
        var json: JSONValue
        var errors: [PlanCut.Problem] { problems.filter { $0.severity == "error" } }
    }

    /// Resolves, builds on a scratch copy and reviews the result; nothing changes.
    func checkPlanCut(_ spec: PlanCut.Spec) async throws -> PlanCutCheck {
        var transcripts: [String: SourceTranscript] = [:]
        for mediaID in Set(spec.clips.map(\.media)).sorted() {
            if let stored = try? await storedTranscript(mediaID) { transcripts[mediaID] = stored }
        }
        let (clips, resolveProblems) = PlanCut.resolve(spec, project: project, transcripts: transcripts)
        let (textPresets, presetProblems) = planTextPresets(spec)
        var problems = resolveProblems + presetProblems
        var result: [String: JSONValue] = ["baseRev": .integer(project.revision)]
        var built: (planner: LayerPlanner, placements: [PlanCut.Placement], kept: [String])?
        do {
            built = try PlanCut.build(spec, clips: clips, on: project, textPresets: textPresets, transcripts: transcripts)
        } catch {
            problems.append(PlanCut.Problem(id: "cannot-build", severity: "error", entry: nil, detail: "\(error)"))
        }
        if let built {
            let after = built.planner.project
            let facts = PlanCut.facts(spec, clips: clips, placements: built.placements, on: after)
            problems += facts.problems + planFontProblems(built.planner.project)
            let fps = after.fps.value
            result["duration"] = .number((Double(after.duration) / fps * 100).rounded() / 100)
            result["clips"] = .array(facts.clips)
            if !facts.titles.isEmpty { result["titles"] = .array(facts.titles) }
            if spec.captions != nil {
                let cues = after.tracks.flatMap(\.items).filter { $0.fields[PlanCut.tag] == .string("captions") }
                result["captions"] = .integer(cues.count)
                // Clips picked by quote or words already report a missing transcript.
                let timed = spec.clips.filter { $0.role == "speech" && $0.quote == nil && $0.words == nil }
                for media in Set(timed.map(\.media)).sorted()
                where transcripts[media] == nil {
                    problems.append(PlanCut.Problem(
                        id: "no-transcript", severity: "warning", entry: nil,
                        detail: "Media \(media) has no stored transcript, so its speech gets no captions: media "
                            + "transcribe --media \(media) first", facts: ["media": .string(media)]))
                }
            }
            result["sections"] = .array(after.sectionMarkers.enumerated().map { index, marker in
                let end = index + 1 < after.sectionMarkers.count ? after.sectionMarkers[index + 1].at : after.duration
                return .object([
                    "id": .string(marker.id), "label": .string(marker.label),
                    "at": .number((Double(marker.at) / fps * 100).rounded() / 100),
                    "seconds": .number((Double(end - marker.at) / fps * 100).rounded() / 100),
                ])
            })
            if !built.kept.isEmpty { result["otherItems"] = .integer(built.kept.count) }
            // The review of the edit as it would be; picture, loudness and plugin checks belong to a rendered revision.
            var context = reviewContext()
            context.picture = nil
            context.loudness = nil
            context.pluginIssues = nil
            context.delivered = []
            context.transcripts = transcripts
            let review = TimelineReview.run(after, context: context).filter { $0.accepted == nil }
            result["review"] = .array(review.map(\.json))
        }
        result["problems"] = .array(problems.map(\.json))
        result["ok"] = .bool(!problems.contains { $0.severity == "error" })
        return PlanCutCheck(built: built, problems: problems, json: .object(result))
    }
}
