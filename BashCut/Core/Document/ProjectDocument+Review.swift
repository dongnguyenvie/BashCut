import BashCutAgent
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutPlugin
import BashCutProject
import Foundation

extension ProjectDocument {
    /// The project's export presets (`output.presets`), known ones only, first one primary.
    var outputPresets: [ExportPreset] { project.outputPresets.compactMap(ExportPreset.init(argument:)) }

    /// The preset the Export sheet starts with: the project's first output, else the shape's (a UI default the user
    /// sees and changes).
    var primaryExportPreset: ExportPreset {
        outputPresets.first ?? (project.width > project.height ? .youtube1080 : .tiktok)
    }

    /// The preset a loudness measurement uses: the project's first output, else Quick Draft — no platform, so the
    /// target is the project's own (never a guessed platform's).
    var measurePreset: ExportPreset { outputPresets.first ?? .quickDraft }

    /// The platforms of the project's outputs whose zones the viewer's safe-area overlay and the text checks use
    /// (the strictest of each side); nil when no output of the frame's shape is set.
    var layoutPlatform: OutputPlatform? { reviewTargets.layoutPlatform(for: project) }

    var reviewTargets: ReviewTargets {
        ReviewTargets(
            measureArguments: ["preset": .string(measurePreset.argument)], measuresPicture: true,
            platforms: outputPresets.compactMap(\.platform))
    }

    /// The review the panel, the export sheet and `review.run` show: installed fonts, the text presets' defaults,
    /// the last loudness and picture measurements of this session, the output platforms and the project's review
    /// profile.
    func reviewIssues() -> [ReviewIssue] { TimelineReview.run(project, context: reviewContext()) }

    /// What the review and `review.layout` know beyond the project: fonts, preset defaults, the renderer's text
    /// layout (#465), the last measurements and the targets.
    func reviewContext() -> ReviewContext {
        var context = ReviewContext(
            fontAvailable: ProjectFonts.isAvailable,
            textDefaults: { preset in
                let defaults = TextPresetStyle.defaults(preset)
                return (defaults["size"] ?? 0.055, defaults["positionY"] ?? 0.18)
            },
            textLayout: { item, width, height in TextPresetStyle.layout(item, size: CGSize(width: width, height: height)) },
            loudness: reviewLoudness, picture: reviewPicture, pluginIssues: reviewPluginIssues, targets: reviewTargets)
        let used = Set(project.tracks.flatMap(\.items).compactMap(\.mediaID))
        context.transcripts = reviewTranscripts.filter { used.contains($0.key) }
        context.missingGlyphs = ProjectFonts.missingGlyphs
        context.delivered = deliveredQC
        context.mediaKeys = sourceMediaKeys()
        context.claims = ((try? agents.knowledgeStore.claims()) ?? []).map(\.text)
        context.subjects = reviewSubjects()
        return context
    }

    /// `review.run`: the issues with the session's transcripts loaded, kept as a round; with `sinceRev`, what the
    /// round fixed, added and left against the review of that revision (P1-E2).
    func runReview(_ arguments: CommandArguments, author: Author = .user) async throws -> JSONValue {
        let measured = arguments.bool("measure") ? try await measureForReview(author: author) : nil
        let result = try await reviewResult(arguments, author: author)
        guard let measured, case .object(var object) = result else { return result }
        object["measured"] = measured
        return .object(object)
    }

    /// `review run --measure`: measures this revision when it was not (or waits for a measure already running),
    /// up to `UnixRPCClient`'s allowance for the call.
    func measureForReview(author: Author) async throws -> JSONValue? {
        guard project.duration > 0 else { return nil }
        await restoreReviewMeasurements()
        let running = jobs.jobs.first { $0.method == "review.measure" && $0.isActive }
        guard running != nil || reviewPicture?.revision != project.revision else { return nil }
        let id: String
        if let running { id = running.id } else {
            guard let started = try startReviewMeasure(author: author).object["job"]?.string else { return nil }
            id = started
        }
        let waited = try await waitForJobs([id], seconds: 100).object
        return .object(["job": .string(id), "timedOut": waited["timedOut"] ?? .bool(false)])
    }

    private func reviewResult(_ arguments: CommandArguments, author: Author) async throws -> JSONValue {
        await loadReviewTranscripts()
        await restoreReviewMeasurements()
        let all = reviewIssues()
        let previous = arguments.optionalInt("sinceRev").map { revision in reviewRounds.last { $0.revision == revision } }
        if let previous, previous == nil {
            throw RPCFailure(-32602, "No review of that revision in this session; reviewed: "
                + reviewRounds.map { "\($0.revision)" }.joined(separator: ", "))
        }
        // One round per revision, holding its latest review (after a measure, say).
        if reviewRounds.last?.revision == project.revision { reviewRounds.removeLast() }
        reviewRounds.append((project.revision, all, project))
        reviewRounds = Array(reviewRounds.suffix(20))
        let range = try Self.reviewRange(arguments)
        let inRange = range.map { range in all.filter { TimelineReview.issue($0, overlaps: range) } } ?? all
        var issues = inRange
        if let minimum = arguments.optionalString("minSeverity").flatMap(ReviewSeverity.init(rawValue:)) {
            issues = issues.filter { $0.severity <= minimum }
        }
        // Accepted issues (review.accept) are settled: listed only when asked for, counted in the summary (B7).
        let hidden = arguments.bool("accepted") ? [] : issues.filter { $0.accepted != nil }.map(\.id)
        issues = issues.filter { !hidden.contains($0.id) }
        let list = JSONValue.array(issues.map(\.json))
        guard arguments.bool("summary") || previous != nil else { return list }
        let checks = TimelineReview.coverage(project, context: reviewContext())
        let summary = ReviewSummary(inRange, coverage: checks)
        // A range is a look at one part (a quick edit's check), not the review stage of the whole edit.
        if summary.status == .pass, range == nil {
            logAutoStage("review", evidence: ["review run rev \(project.revision): pass"], author: author)
        }
        var result: [String: JSONValue] = [
            "issues": list, "summary": summary.json, "rev": .integer(project.revision),
            "round": .integer(reviewRounds.count), "checks": checks,
        ]
        if !hidden.isEmpty { result["acceptedHidden"] = .array(hidden.map(JSONValue.string)) }
        // A pass is not the review stage while the plan's required stages are open: say which.
        let pending = WorkflowChecklist.pendingRequiredStages(project, entries: runLog?.entries() ?? [])
        if !pending.isEmpty { result["stagesPending"] = .array(pending) }
        if let range { result["range"] = .object(["from": .integer(range.lowerBound), "to": .integer(range.upperBound)]) }
        if let previous, let previous {
            var diff = ReviewRounds.diff(before: previous.issues, after: all).object
            diff["sinceRev"] = .integer(previous.revision)
            result["diff"] = .object(diff)
        }
        return .object(result)
    }

    /// `review run --from --to`: the frames `[from, to)` whose issues the call lists; nil for the whole edit.
    static func reviewRange(_ arguments: CommandArguments) throws -> Range<Int>? {
        let from = arguments.optionalInt("from"), to = arguments.optionalInt("to")
        guard from != nil || to != nil else { return nil }
        let start = from ?? 0, end = to ?? Int.max
        guard end > start else { throw RPCFailure(-32602, "--to must be after --from") }
        return start..<end
    }

    /// `review.verify` (P1-E3): the issue as the last review of an earlier revision saw it, measured again now over
    /// its own range (picture issues re-sample just that range; the rest re-run on the current project), with a still
    /// window around it as proof.
    func verifyReviewIssue(_ arguments: CommandArguments) async throws -> JSONValue {
        let id = try arguments.string("id")
        if id == "all" || id.contains(",") { return try await verifyReviewIssues(id) }
        guard let round = reviewRounds.last(where: { $0.revision != project.revision && $0.issues.contains { $0.id == id } })
            ?? reviewRounds.last(where: { $0.issues.contains { $0.id == id } }),
            let before = round.issues.first(where: { $0.id == id })
        else { throw RPCFailure(-32602, "\(id) is not in a review of this session; run review run first") }
        await loadReviewTranscripts()
        await restoreReviewMeasurements()
        var context = reviewContext()
        let fps = project.fps.value
        let margin = Int(fps.rounded())
        let range = max(0, before.frame - margin)..<min(project.duration, (before.endFrame ?? before.frame + 1) + margin)
        let picture = Self.pictureIssuePrefixes.contains(where: id.hasPrefix)
        if picture, let root = fileURL?.deletingLastPathComponent(), !range.isEmpty {
            let snapshot = try await engine.build(project, root: root, workspace: settings.workspace, purpose: .preview)
            context.picture = try await PictureSampler.measure(snapshot, project: project, range: range)
        }
        let now = TimelineReview.run(project, context: context)
        let after = now.first { $0.id == id }
        var result: [String: JSONValue] = [
            "id": .string(id), "status": .string(after == nil ? "fixed" : "persisting"),
            "before": before.json, "beforeRev": .integer(round.revision), "after": after?.json ?? .null,
            "rev": .integer(project.revision),
            "measured": .string(picture ? "picture re-sampled over frames \(range.lowerBound)–\(range.upperBound)" : "review re-run"),
            "nearby": .array(now.filter { issue in
                issue.id != id && range.contains(issue.frame)
            }.map(\.json)),
        ]
        if id.hasPrefix("loudness") || id.hasPrefix("true-peak") {
            result["measured"] = .string("loudness needs a normalized export of this revision")
        }
        if project.duration > 0, !range.isEmpty {
            let center = min(project.duration - 1, (range.lowerBound + range.upperBound) / 2)
            let window = try? await reviewWindow(CommandArguments([
                "frame": .integer(center), "span": .integer(max(2, min(30, range.count / 2))),
                "step": .integer(max(1, range.count / 12)),
            ]))
            result["window"] = window?.object["path"] ?? .null
        }
        return .object(result)
    }

    /// `review.verify all` or `ID1,ID2,…`: every listed issue (all: the errors and warnings of the last review of an
    /// earlier revision) against one review of now, picture issues re-sampled once over the span they cover. A row
    /// per issue with fixed or persisting; the still window only for what persists.
    func verifyReviewIssues(_ list: String) async throws -> JSONValue {
        let earlier = reviewRounds.last { $0.revision != project.revision } ?? reviewRounds.last
        let ids = list == "all"
            ? (earlier?.issues ?? []).filter { $0.severity != .info }.map(\.id)
            : list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var befores: [(id: String, issue: ReviewIssue, rev: Int)] = []
        for id in ids {
            guard let round = reviewRounds.last(where: { $0.revision != project.revision && $0.issues.contains { $0.id == id } })
                ?? reviewRounds.last(where: { $0.issues.contains { $0.id == id } }),
                let before = round.issues.first(where: { $0.id == id })
            else { throw RPCFailure(-32602, "\(id) is not in a review of this session; run review run first") }
            befores.append((id, before, round.revision))
        }
        await loadReviewTranscripts()
        await restoreReviewMeasurements()
        var context = reviewContext()
        let margin = Int(project.fps.value.rounded())
        let picture = befores.filter { item in Self.pictureIssuePrefixes.contains(where: item.id.hasPrefix) }
        if let first = picture.map({ $0.issue.frame }).min(), let root = fileURL?.deletingLastPathComponent() {
            let last = picture.map { $0.issue.endFrame ?? $0.issue.frame + 1 }.max() ?? first + 1
            let range = max(0, first - margin)..<min(project.duration, last + margin)
            if !range.isEmpty {
                let snapshot = try await engine.build(project, root: root, workspace: settings.workspace, purpose: .preview)
                context.picture = try await PictureSampler.measure(snapshot, project: project, range: range)
            }
        }
        let now = TimelineReview.run(project, context: context)
        var rows: [JSONValue] = []
        var persisting = 0
        for item in befores {
            var row: [String: JSONValue] = ["id": .string(item.id), "beforeRev": .integer(item.rev)]
            if let after = now.first(where: { $0.id == item.id }) {
                persisting += 1
                row["status"] = .string("persisting")
                row["after"] = after.json
                let center = min(max(0, project.duration - 1), after.frame)
                let window = try? await reviewWindow(CommandArguments([
                    "frame": .integer(center), "span": .integer(margin), "step": .integer(max(1, margin / 6)),
                ]))
                row["window"] = window?.object["path"] ?? .null
            } else {
                row["status"] = .string("fixed")
            }
            if item.id.hasPrefix("loudness") || item.id.hasPrefix("true-peak") {
                row["measured"] = .string("loudness needs a normalized export of this revision")
            }
            rows.append(.object(row))
        }
        return .object([
            "rev": .integer(project.revision), "fixed": .integer(befores.count - persisting),
            "persisting": .integer(persisting), "issues": .array(rows),
            "new": .array(now.filter { issue in
                issue.severity != .info && !(earlier?.issues ?? []).contains { $0.id == issue.id }
            }.map(\.json)),
        ])
    }

    /// `review.accept`: keeps an issue with the reason (or drops the acceptance) as one undoable edit. An error can
    /// be kept too when no fix exists (#507-31); it is recorded with its severity and counted as acceptedErrors.
    func acceptReviewIssue(_ arguments: CommandArguments, author: Author) throws -> JSONValue {
        let id = try arguments.string("id")
        var review = project["review"]?.object ?? [:]
        var accepted = review["accepted"]?.object ?? [:]
        if arguments.bool("remove") {
            guard accepted.removeValue(forKey: id) != nil else { throw RPCFailure(-32602, "\(id) is not accepted") }
        } else {
            guard let reason = arguments.optionalString("reason") else { throw RPCFailure(-32602, "Give the reason") }
            var record: [String: JSONValue] = [
                "reason": .string(reason), "rev": .integer(project.revision), "author": .string(author.rawValue),
            ]
            if let issue = reviewIssues().first(where: { $0.id == id }) { record["severity"] = .string(issue.severity.rawValue) }
            accepted[id] = .object(record)
        }
        review["accepted"] = accepted.isEmpty ? nil : .object(accepted)
        let revision = try commit(
            .setProjectProperties(patch: ["review": review.isEmpty ? .null : .object(review)]),
            label: arguments.bool("remove") ? "Reopen review issue" : "Accept review issue", author: author,
            baseRevision: arguments.int("baseRev"))
        return .object(["rev": .integer(revision), "accepted": .object(accepted)])
    }

    /// Loads the stored transcripts of the media on the timeline for the review.
    func loadReviewTranscripts() async {
        let used = Set(project.tracks.flatMap(\.items).compactMap(\.mediaID))
        var loaded: [String: SourceTranscript] = [:]
        for mediaID in used.sorted() {
            if let stored = try? await storedTranscript(mediaID) { loaded[mediaID] = stored }
        }
        reviewTranscripts = loaded
    }

    /// Whether the Review panel can apply `fix` itself (an edit or an export); other fixes go to the agent.
    func canApply(_ fix: ReviewFix) -> Bool {
        ["timeline.apply", "timeline.close-gap", "export.start", "review.measure", "project.format"].contains(fix.command ?? "")
    }

    /// Applies a review fix as the user: edits run as one undoable step, an export fix opens the Export sheet.
    func apply(_ fix: ReviewFix, label: String) {
        do {
            switch fix.command {
            case "timeline.apply":
                let ops = try WireOperations.decode(fix.arguments["ops"] ?? .null, project: project)
                let name = fix.arguments["label"]?.string ?? label
                apply(.group(label: name, author: .user, ops: ops), label: name)
            case "timeline.close-gap":
                _ = try closeGap(at: fix.arguments["atFrame"]?.int ?? 0, trackID: fix.arguments["track"]?.string)
            case "export.start":
                ui.showReview = false
                ui.showExport = true
            case "review.measure":
                _ = try startReviewMeasure(author: .user)
            case "project.format":
                var arguments = fix.arguments
                arguments["baseRev"] = .integer(project.revision)
                _ = try formatCommand(CommandArguments(arguments), author: .user)
            default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// The measured part of the review, as a job: renders the timeline small (proxies allowed) for the picture checks
    /// and runs every enabled plugin `review.check` side by side, and keeps both for this revision. The job's result
    /// has the sample count, the plugin checks that ran and the issues they and the picture checks now find.
    func startReviewMeasure(author: Author, picture: Bool = true, plugins usePlugins: Bool = true) throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw RPCFailure(-32602, "Open a saved project first")
        }
        guard project.duration > 0 else { throw RPCFailure(-32602, "The timeline is empty") }
        if let running = jobs.jobs.first(where: { $0.method == "review.measure" && $0.isActive }) {
            return .object(["job": .string(running.id), "state": .string("running")])
        }
        let project = project
        let engine = engine
        let workspace = settings.workspace
        let service = plugins.service
        let checks = usePlugins ? service.reviewCheckProviders(projectRoot: root, disabled: reviewDisabledChecks) : []
        let id = jobs.start("review.measure", author: author, work: { [weak self] _ in
            async let pluginIssues = service.runReviewChecks(checks, project: project, projectRoot: root)
            var measured: ReviewPicture?
            if picture {
                let snapshot = try await engine.build(project, root: root, workspace: workspace, purpose: .preview)
                measured = try await PictureSampler.measure(snapshot, project: project)
            }
            let reported = await pluginIssues
            guard let self else { throw CancellationError() }
            if var picture = measured {
                if self.project.revision == project.revision { picture.textContrast = try await self.measureTextContrast() }
                measured = picture
                self.reviewPicture = picture
                self.storeReviewMeasurement(picture: picture, of: project)
            }
            if usePlugins {
                self.reviewPluginIssues = ReviewPluginIssues(revision: project.revision, issues: reported)
                // Kept for the next session only when every check ran: a failed or timed-out one runs again then.
                if !checks.isEmpty, !reported.contains(where: { $0.id.hasSuffix(":failed") }) {
                    self.storeReviewMeasurement(pluginIssues: reported, of: project)
                }
            }
            let found = self.reviewIssues().filter { issue in
                issue.source != nil || Self.pictureIssuePrefixes.contains(where: issue.id.hasPrefix)
            }
            return .object([
                "revision": .integer(project.revision), "samples": .integer(measured?.samples.count ?? 0),
                // Hard cuts measured: touching clips on Main with no transition (export status cuts counts every
                // join, #508-34).
                "hardCuts": .integer(measured?.cuts.count ?? 0),
                "pluginChecks": .array(checks.map { .object(["plugin": .string($0.plugin.id), "provider": .string($0.provider.id)]) }),
                "issues": .array(found.map(\.json)), "current": .bool(project.revision == self.project.revision),
            ])
        }, finished: { [weak self] outcome in
            guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
            self?.message = "review.measure: " + error.localizedDescription
        })
        return .object(["job": .string(id), "state": .string("running")])
    }

    /// Contrast of the text on screen against the picture behind it: every title, and at most eight captions spread
    /// over the edit (they share one look).
    func measureTextContrast() async throws -> [String: ReviewPicture.TextContrast] {
        guard case .array(let rows)? = ReviewLayout.json(
            project, context: reviewContext(), frame: nil, range: nil, words: nil
        ).object["items"] else { return [:] }
        let captions = rows.filter { $0.object["trackRole"]?.string == TrackRole.captions }
        let step = max(1, captions.count / 8)
        let picked = rows.filter { $0.object["trackRole"]?.string != TrackRole.captions }
            + captions.enumerated().filter { $0.offset % step == 0 }.prefix(8).map(\.element)
        guard !picked.isEmpty else { return [:] }
        var result: [String: ReviewPicture.TextContrast] = [:]
        for row in try await measureContrast(Array(picked.prefix(48)), frame: nil) {
            guard let id = row.object["id"]?.string, let contrast = row.object["contrast"]?.object,
                let ratio = contrast["ratio"]?.double, let frame = contrast["frame"]?.int
            else { continue }
            result[id] = ReviewPicture.TextContrast(ratio: ratio, frame: frame)
        }
        return result
    }

    /// Plugin and provider IDs whose review checks this project turns off (`review.disabledChecks`).
    var reviewDisabledChecks: Set<String> {
        Set(project["review"]?.object["disabledChecks"]?.array.compactMap(\.string) ?? [])
    }

    /// The `review.check` providers for `plugins.hooks`, with whether this project runs them.
    func reviewChecksJSON() -> JSONValue {
        let root = fileURL?.deletingLastPathComponent()
        let enabled = Set(plugins.service.reviewCheckProviders(projectRoot: root, disabled: reviewDisabledChecks)
            .map(\.provider.id))
        let disabled = reviewDisabledChecks
        // The catalog itself, not the Plugins sheet's last refresh, so a plugin linked a moment ago is listed.
        return .array(plugins.service.catalog(projectRoot: root).plugins.flatMap { plugin in
            (plugin.manifest.providers ?? []).filter { $0.capability == PluginAPI.reviewCheck }.map { provider in
                .object([
                    "plugin": .string(plugin.id), "provider": .string(provider.id), "name": .string(provider.name),
                    "enabled": .bool(!disabled.contains(plugin.id) && !disabled.contains(provider.id)),
                    "active": .bool(enabled.contains(provider.id)),
                ])
            }
        })
    }

    /// Issue IDs the picture checks make (`Review+Picture.swift`).
    static let pictureIssuePrefixes = ["black-", "still-", "jump-", "shot-", "text-contrast"]

    /// Keeps the loudness a finished export measured, for the revision it now describes.
    func recordReviewLoudness(
        _ measurement: LoudnessMeasurement?, revision: Int, preset: ExportPreset, measured: Project? = nil
    ) {
        guard let measurement else { return }
        let target = project.loudnessTarget(preset: preset.argument, platform: preset.platform)
        let loudness = ReviewLoudness(
            revision: revision, integratedLUFS: measurement.integratedLUFS, truePeakDbTP: measurement.truePeakDbTP,
            loudnessRangeLU: measurement.loudnessRangeLU, targetLUFS: target.lufs, maxTruePeakDbTP: target.truePeak,
            preset: preset.argument)
        reviewLoudness = loudness
        if let measured { storeReviewMeasurement(loudness: loudness, of: measured) }
    }
}
