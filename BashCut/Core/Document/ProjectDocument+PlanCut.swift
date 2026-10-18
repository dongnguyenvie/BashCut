import BashCutAutomation
import BashCutEngine
import BashCutProject
import Foundation

/// `plan.check` and `plan.apply`: the edit as one list, checked on a scratch copy and built as one undoable edit.
extension ProjectDocument {
    func registerPlanCutCommands() {
        handle("plan.check") { document, arguments, author in
            let spec = try document.planCutSpec(arguments)
            let check = try await document.checkPlanCut(spec, words: arguments.bool("words"))
            guard arguments.bool("save") else { return check.json }
            return try document.savePlanCut(check, arguments, author: author)
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
            let bed = await document.planMusicBed(spec.music, built: built.planner.project, handLevel: built.hand.keepsMusicLevel)
            operations += bed.operations
            var properties: [String: JSONValue] = [:]
            let given = [arguments["cut"], arguments["patch"]].contains { $0 != nil && $0 != .null }
            if given, let cut = try document.planCutValue(arguments) {
                var plan = document.project["plan"]?.object ?? [:]
                plan["cut"] = cut
                properties["plan"] = .object(plan)
            }
            if let review = document.planReview(spec) { properties["review"] = .object(review) }
            if !properties.isEmpty { operations.insert(.setProjectProperties(patch: properties), at: 0) }
            let label = "Apply edit list"
            let result = try document.commitEdit(
                .group(label: label, author: author, ops: operations), label: label, author: author,
                baseRevision: baseRevision, note: try Self.editNote(arguments))
            var json = check.json.object
            json["rev"] = .integer(result.revision)
            json["music"] = bed.report
            let clips = spec.clips.count, lines = spec.voiceover.count
            let sections = Set(spec.clips.compactMap(\.section) + spec.voiceover.compactMap(\.section)).count
            let made = lines > 0 && clips == 0 ? "\(lines) voiceover lines" : "\(clips) clips"
            document.logAutoStage("story", evidence: [
                "plan.cut: \(made) in \(sections) sections", "plan check ok at rev \(baseRevision)",
            ], author: author)
            document.logAutoStage("rough-cut", evidence: ["plan.apply rev \(result.revision)", made], author: author)
            if lines > 0 {
                document.logAutoStage("voiceover", evidence: ["plan.apply rev \(result.revision)", "\(lines) lines"], author: author)
            }
            if spec.captions != nil {
                document.logAutoStage("captions", evidence: ["plan.apply rev \(result.revision) captions from plan.cut"], author: author)
            }
            json["changed"] = .bool(result.changed)
            // What the build left to fix, without the info rows: the review run of the new revision.
            json["review"] = .array((check.json.object["review"]?.array ?? []).filter {
                $0.object["severity"]?.string != ReviewSeverity.info.rawValue
            })
            json["items"] = .array(document.project.tracks.flatMap(\.items)
                .filter { $0.fields[PlanCut.tag] != nil && $0.fields["linkedVideo"] == nil }
                .map { .object(["item": .string($0.id), "entry": $0.fields[PlanCut.tag] ?? .null]) })
            // The storyboard of the new revision in the same call (timeline sheet --cuts --text).
            if arguments.bool("sheet"), !arguments.bool("dryRun") {
                json["sheet"] = try await document.timelineSheet(CommandArguments(["cuts": .bool(true), "text": .bool(true)]))
            }
            return arguments.bool("full") ? .object(json) : Self.briefApply(json)
        }
    }

    /// What an agent reads after a build: the per-clip facts it already had from plan check, the change list, the
    /// item IDs and the sheet's cells cost thousands of tokens on every later turn, so they come only with --full;
    /// a clip's problems, the review and the sheet's image paths stay.
    static func briefApply(_ json: [String: JSONValue]) -> JSONValue {
        var brief = json.filter { !["clips", "changes", "items", "sheet", "lines", "graphics"].contains($0.key) }
        brief["clips"] = .integer(json["clips"]?.array.count ?? 0)
        for key in ["lines", "graphics"] where !(json[key]?.array ?? []).isEmpty {
            brief[key] = .integer(json[key]?.array.count ?? 0)
        }
        if let sheet = json["sheet"]?.object {
            brief["sheet"] = .array((sheet["sheets"]?.array ?? []).compactMap { $0.object["path"] })
        }
        return .object(brief)
    }

    /// The list from `cut`, else `plan.cut`, with `patch` merged over it.
    func planCutValue(_ arguments: CommandArguments) throws -> JSONValue? {
        let value = arguments["cut"].flatMap { $0 == .null ? nil : $0 } ?? project["plan"]?.object["cut"]
        guard let value, let patch = arguments["patch"], patch != .null else { return value }
        do { return try PlanCut.patch(value, with: patch) } catch let error as ProjectError { throw RPCFailure.invalid(error) }
    }

    /// The list from `cut`, else `plan.cut`, with `patch` merged over it; entries that cannot be read are left out
    /// with an error each (`spec.invalid`), so plan check lists them all at once.
    func planCutSpec(_ arguments: CommandArguments) throws -> PlanCut.Spec {
        let value = try planCutValue(arguments)
        guard let value else {
            throw RPCFailure(-32602, "No edit list: give cut (a JSON file) or set plan.cut", data: .object([
                "remediation": .object(["command": .string("project.set-data"), "hint": .string("plan --merge with {cut: …}")]),
            ]))
        }
        do { return try PlanCut.decodeAll(value) } catch let error as ProjectError { throw RPCFailure.invalid(error) }
    }

    /// The project's review limits with `plan.cut.review` merged over them; nil when the plan sets none.
    func planReview(_ spec: PlanCut.Spec) -> [String: JSONValue]? {
        guard let limits = spec.review, !limits.isEmpty else { return nil }
        return (project["review"]?.object ?? [:]).merging(limits) { $1 }
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

    /// Style values that cannot be meant: an outline under 1 pt (`strokeWidth` is in points, unlike `size`); a
    /// plate padding or radius given in pixels (they are × font size, so 20 draws a plate 20 font sizes round: an
    /// ellipse or a pill); one problem per entry and kind (captions share one).
    func planStyleProblems(_ after: Project) -> [PlanCut.Problem] {
        after.tracks.flatMap(\.items).flatMap { item -> [PlanCut.Problem] in
            guard let entry = item.fields[PlanCut.tag]?.string, let style = item["textStyle"]?.object else { return [] }
            var problems: [PlanCut.Problem] = []
            if let width = style["strokeWidth"]?.double, width > 0, width < 1 {
                problems.append(PlanCut.Problem(
                    id: "stroke-units", severity: "warning", entry: entry,
                    detail: "strokeWidth is in points (0–50), not a share like size: \(width) draws no visible outline; "
                        + "give it in points as the inspector's Outline (0–12 pt), or use a background",
                    facts: ["strokeWidth": .number(width)]))
            }
            let plates: [(String, [String: JSONValue]?)] = [
                ("background", style["background"]?.object), ("emphasis.plate", style["emphasis"]?.object["plate"]?.object)
            ]
            for (name, plate) in plates {
                guard let plate else { continue }
                let large = ["padding", "radius"].compactMap { key -> (String, Double)? in
                    guard let value = plate[key]?.double, value > Self.planPlateUnitsLimit else { return nil }
                    return ("\(name).\(key)", value)
                }
                guard !large.isEmpty else { continue }
                problems.append(PlanCut.Problem(
                    id: "plate-units", severity: "warning", entry: entry,
                    detail: large.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
                        + " is × font size, not pixels: the plate grows past its text and rounds into an ellipse; "
                        + "give padding about 0.3 and radius about 0.2 (0.5 for a pill)",
                    facts: Dictionary(uniqueKeysWithValues: large.map { ($0.0, JSONValue.number($0.1)) })))
            }
            return problems
        }
        .reduce(into: [PlanCut.Problem]()) { result, problem in
            if !result.contains(where: { $0.entry == problem.entry && $0.id == problem.id }) { result.append(problem) }
        }
    }

    /// Plate padding or radius above this many font sizes reads as pixels: no designed plate reaches it.
    static let planPlateUnitsLimit = 2.0

    /// Each title's smallest line as a share of the frame's short side (`textShare`), the measure review.minTextSize
    /// uses, so a template that shrinks a line shows before the build.
    func planTitleSizes(_ titles: [JSONValue], on after: Project) -> [JSONValue] {
        let context = reviewContext()
        let items = after.tracks.flatMap(\.items)
        return titles.map { title in
            var fields = title.object
            guard let id = fields["id"]?.string,
                let item = items.first(where: { $0.fields[PlanCut.tag] == .string(id) && $0["text"] != nil }),
                let share = TimelineReview.smallestTextShare(item, in: after, context: context)
            else { return title }
            fields["textShare"] = .number((share * 1_000).rounded() / 1_000)
            return .object(fields)
        }
    }

    /// The limits a review of the built edit reads and nobody set, listed at once so they are chosen with the plan;
    /// and `plan.cut.review` values out of range.
    func planReviewProblems(_ review: [String: JSONValue]?, built: Project?) -> [PlanCut.Problem] {
        var problems: [PlanCut.Problem] = []
        var profiled = built ?? project
        if let review { profiled["review"] = .object(review) }
        let profile = ReviewProfile(profiled)
        let unset = TimelineReview.applicableLimits(profiled).filter { profile[$0] == nil }
        if !unset.isEmpty {
            problems.append(PlanCut.Problem(
                id: "review-profile-unset", severity: "warning", entry: nil,
                detail: "Review limits this edit needs are unset, so review run stays incomplete: "
                    + unset.joined(separator: ", ") + ". Choose each from the recipe's ranges in plan.cut.review "
                    + "(written on plan apply) or project set-data review",
                facts: [
                    "unsetLimits": .array(unset.map(JSONValue.string)),
                    // What each limit can hold (seconds, a share 0–1, characters, a contrast ratio), not a choice.
                    "accepts": .object(Dictionary(uniqueKeysWithValues: unset.compactMap { key in
                        ReviewProfile.numberKeys[key].map { (key, JSONValue.string("\($0.lowerBound)…\($0.upperBound)")) }
                    })),
                ]))
        }
        guard let review else { return problems }
        var copy = project
        copy["review"] = .object(review)
        do { try copy.validateReviewSettings() } catch {
            problems.append(PlanCut.Problem(
                id: "review-invalid", severity: "error", entry: nil, detail: "plan.cut." + error.localizedDescription))
        }
        return problems
    }

    struct PlanCutCheck {
        var built: (planner: LayerPlanner, placements: [PlanCut.Placement], kept: [String], hand: PlanCut.HandReport)?
        var problems: [PlanCut.Problem]
        var json: JSONValue
        var errors: [PlanCut.Problem] { problems.filter { $0.severity == "error" } }
    }

    /// Entries citing fact keys this project has neither as a fact nor as a claim (P3-I4).
    func planFactProblems(_ spec: PlanCut.Spec) -> [PlanCut.Problem] {
        guard !spec.factReferences.isEmpty else { return [] }
        let store = agents.knowledgeStore
        let facts = ((try? store.values(.facts, scope: .project)) ?? []).map(\.key)
        let claims = ((try? store.claims()) ?? []).map(\.key)
        return PlanCut.factProblems(spec, known: Set(facts + claims))
    }

    /// Resolves, builds on a scratch copy and reviews the result; nothing changes.
    func checkPlanCut(_ spec: PlanCut.Spec, words: Bool = false) async throws -> PlanCutCheck {
        var transcripts: [String: SourceTranscript] = [:]
        for mediaID in Set(spec.clips.map(\.media)).sorted() {
            if let stored = try? await storedTranscript(mediaID) { transcripts[mediaID] = stored }
        }
        let (clips, resolveProblems) = PlanCut.resolve(spec, project: project, transcripts: transcripts)
        let takes = await planLineTakes(spec)
        let (textPresets, presetProblems) = planTextPresets(spec)
        var problems = resolveProblems + presetProblems + planFactProblems(spec)
        var result: [String: JSONValue] = ["baseRev": .integer(project.revision)]
        var built: (planner: LayerPlanner, placements: [PlanCut.Placement], kept: [String], hand: PlanCut.HandReport)?
        // With an entry left out, the build would report what its absence causes; its own error says enough.
        if spec.invalid.isEmpty {
            do {
                built = try PlanCut.build(
                    spec, clips: clips, on: project, textPresets: textPresets, transcripts: transcripts, takes: takes)
            } catch {
                problems.append(PlanCut.Problem(id: "cannot-build", severity: "error", entry: nil, detail: "\(error)"))
            }
        }
        let review = planReview(spec)
        if let built {
            var after = built.planner.project
            if let review { after["review"] = .object(review) }
            let facts = PlanCut.facts(spec, clips: clips, placements: built.placements, on: after)
            problems += facts.problems + planFontProblems(after) + planStyleProblems(after)
                + PlanCut.transitionProblems(spec, on: after) + PlanCut.focusProblems(spec, on: after)
            let fps = after.fps.value
            result["duration"] = .number((Double(after.duration) / fps * 100).rounded() / 100)
            result["clips"] = .array(facts.clips)
            let lineFacts = Self.lineFacts(spec, takes: takes, placements: built.placements, on: after, words: words)
            problems += lineFacts.problems
            result.merge(lineFacts.fields) { $1 }
            if !facts.titles.isEmpty { result["titles"] = .array(planTitleSizes(facts.titles, on: after)) }
            if spec.captions != nil {
                result.merge(Self.captionCounts(before: project, after: after)) { $1 }
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
            // What the apply keeps of the edits made by hand since the last one, and what it gives back to the list.
            result["handEdits"] = built.hand.isEmpty ? nil : built.hand.json
            result["music"] = spec.music.map(Self.planMusicSummary)
            // The review of the edit as it would be; picture, loudness and plugin checks belong to a rendered revision.
            var context = reviewContext()
            context.picture = nil
            context.loudness = nil
            context.pluginIssues = nil
            context.delivered = []
            context.transcripts = transcripts
            let review = TimelineReview.run(after, context: context).filter { $0.accepted == nil }
            result["review"] = .array(review.map(\.json))
            problems += [PlanCut.reviewErrorsProblem(review)].compactMap { $0 }
        }
        problems += planReviewProblems(review, built: built?.planner.project)
        problems += [PlanCut.languageProblem(contentLanguage, heard: transcripts.values.map(\.language))].compactMap { $0 }
        result["problems"] = .array(problems.map(\.json))
        result["ok"] = .bool(!problems.contains { $0.severity == "error" })
        return PlanCutCheck(built: built, problems: problems, json: .object(result))
    }

    /// The voiceover lines' and graphics' rows of plan check (with `words`, the words heard during each graphic),
    /// and their problems.
    static func lineFacts(
        _ spec: PlanCut.Spec, takes: [String: PlanCut.LineTake], placements: [PlanCut.Placement], on after: Project,
        words: Bool
    ) -> (problems: [PlanCut.Problem], fields: [String: JSONValue]) {
        var result: [String: JSONValue] = [:]
        guard !spec.voiceover.isEmpty || !spec.graphics.isEmpty else { return ([], result) }
        let more = PlanCut.lineAndGraphicFacts(spec, takes: takes, placements: placements, on: after)
        var problems = more.problems
        if !more.lines.isEmpty { result["lines"] = .array(more.lines) }
        var graphics = more.graphics
        if words {
            let heard = graphicWords(spec, takes: takes, placements: placements, fps: after.fps.value)
            graphics = graphics.map { row in
                guard case .object(var fields) = row, let id = fields["id"]?.string, let list = heard[id] else { return row }
                fields["words"] = list
                return .object(fields)
            }
        }
        if !graphics.isEmpty { result["graphics"] = .array(graphics) }
        guard spec.captions != nil else { return (problems, result) }
        for line in spec.voiceover where takes[line.id]?.words.isEmpty == true {
            problems.append(PlanCut.Problem(
                id: "no-transcript", severity: "warning", entry: line.id,
                detail: "The line's take has no stored transcript, so it gets no captions: voice lines transcribes the "
                    + "takes it makes (or voice check the take)"))
        }
        return (problems, result)
    }

    /// `captions`: the built cues; `captionsKept` when they are the ones the timeline already held, because the list
    /// generates the same captions again (hand-grouped cues stay, #628).
    static func captionCounts(before: Project, after: Project) -> [String: JSONValue] {
        let cues = after.tracks.flatMap(\.items).filter { $0.fields[PlanCut.tag] == .string("captions") }
        var fields: [String: JSONValue] = ["captions": .integer(cues.count)]
        let held = Set(before.tracks.flatMap(\.items).map(\.id))
        if !cues.isEmpty, cues.allSatisfy({ held.contains($0.id) }) { fields["captionsKept"] = .bool(true) }
        return fields
    }
}
