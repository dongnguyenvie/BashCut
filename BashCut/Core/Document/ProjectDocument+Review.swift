import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutPlugin
import BashCutProject
import Foundation

extension ProjectDocument {
    /// The project's export presets (`output.presets`), known ones only, first one primary.
    var outputPresets: [ExportPreset] { project.outputPresets.compactMap(ExportPreset.init(argument:)) }

    /// The preset the Export sheet and a loudness fix start with: the project's first output, else the shape's.
    var primaryExportPreset: ExportPreset {
        outputPresets.first ?? (project.width > project.height ? .youtube1080 : .tiktok)
    }

    /// The platforms of the project's outputs whose zones the viewer's safe-area overlay and the text checks use
    /// (the strictest of each side); nil when no output of the frame's shape is set.
    var layoutPlatform: OutputPlatform? { reviewTargets.layoutPlatform(for: project) }

    var reviewTargets: ReviewTargets {
        ReviewTargets(
            measureArguments: ["preset": .string(primaryExportPreset.argument)], measuresPicture: true,
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
        return context
    }

    /// `review.run`: the issues with the session's transcripts loaded, kept as a round; with `sinceRev`, what the
    /// round fixed, added and left against the review of that revision (P1-E2).
    func runReview(_ arguments: CommandArguments) async throws -> JSONValue {
        await loadReviewTranscripts()
        let all = reviewIssues()
        let previous = arguments.optionalInt("sinceRev").map { revision in reviewRounds.last { $0.revision == revision } }
        if let previous, previous == nil {
            throw RPCFailure(-32602, "No review of that revision in this session; reviewed: "
                + reviewRounds.map { "\($0.revision)" }.joined(separator: ", "))
        }
        // One round per revision, holding its latest review (after a measure, say).
        if reviewRounds.last?.revision == project.revision { reviewRounds.removeLast() }
        reviewRounds.append((project.revision, all))
        reviewRounds = Array(reviewRounds.suffix(50))
        var issues = all
        if let minimum = arguments.optionalString("minSeverity").flatMap(ReviewSeverity.init(rawValue:)) {
            issues = issues.filter { $0.severity <= minimum }
        }
        let list = JSONValue.array(issues.map(\.json))
        guard arguments.bool("summary") || previous != nil else { return list }
        var result: [String: JSONValue] = [
            "issues": list, "summary": ReviewSummary(all).json, "rev": .integer(project.revision),
            "round": .integer(reviewRounds.count),
        ]
        if let previous, let previous {
            var diff = ReviewRounds.diff(before: previous.issues, after: all).object
            diff["sinceRev"] = .integer(previous.revision)
            result["diff"] = .object(diff)
        }
        return .object(result)
    }

    /// `review.accept`: keeps a warning or note with the reason (or drops the acceptance) as one undoable edit.
    func acceptReviewIssue(_ arguments: CommandArguments, author: Author) throws -> JSONValue {
        let id = try arguments.string("id")
        var review = project["review"]?.object ?? [:]
        var accepted = review["accepted"]?.object ?? [:]
        if arguments.bool("remove") {
            guard accepted.removeValue(forKey: id) != nil else { throw RPCFailure(-32602, "\(id) is not accepted") }
        } else {
            guard let reason = arguments.optionalString("reason") else { throw RPCFailure(-32602, "Give the reason") }
            if let issue = reviewIssues().first(where: { $0.id == id }), issue.severity == .error {
                throw RPCFailure(-32602, "\(id) is an error: fix it, or change its severity in review.severities with a reason")
            }
            accepted[id] = .object([
                "reason": .string(reason), "rev": .integer(project.revision), "author": .string(author.rawValue),
            ])
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
                let ops = try WireOperations.decode(fix.arguments["ops"] ?? .null)
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
            if let measured { self.reviewPicture = measured }
            if usePlugins { self.reviewPluginIssues = ReviewPluginIssues(revision: project.revision, issues: reported) }
            let found = self.reviewIssues().filter { issue in
                issue.source != nil || Self.pictureIssuePrefixes.contains(where: issue.id.hasPrefix)
            }
            return .object([
                "revision": .integer(project.revision), "samples": .integer(measured?.samples.count ?? 0),
                "cuts": .integer(measured?.cuts.count ?? 0),
                "pluginChecks": .array(checks.map { .object(["plugin": .string($0.plugin.id), "provider": .string($0.provider.id)]) }),
                "issues": .array(found.map(\.json)), "current": .bool(project.revision == self.project.revision),
            ])
        }, finished: { [weak self] outcome in
            guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
            self?.message = "review.measure: " + error.localizedDescription
        })
        return .object(["job": .string(id), "state": .string("running")])
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
    static let pictureIssuePrefixes = ["black-", "still-", "jump-", "shot-"]

    /// Keeps the loudness a finished export measured, for the revision it now describes.
    func recordReviewLoudness(_ measurement: LoudnessMeasurement?, revision: Int, preset: ExportPreset) {
        guard let measurement else { return }
        let target = project.loudnessTarget(preset: preset.argument, platform: preset.platform)
        reviewLoudness = ReviewLoudness(
            revision: revision, integratedLUFS: measurement.integratedLUFS, truePeakDbTP: measurement.truePeakDbTP,
            loudnessRangeLU: measurement.loudnessRangeLU, targetLUFS: target.lufs, maxTruePeakDbTP: target.truePeak,
            preset: preset.argument)
    }
}
