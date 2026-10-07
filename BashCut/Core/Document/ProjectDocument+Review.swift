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

    /// The platform whose zones the viewer's safe-area overlay and the text checks use.
    var layoutPlatform: OutputPlatform {
        ReviewTargets(platform: outputPresets.lazy.compactMap(\.platform).first).layoutPlatform(for: project)
    }

    /// The review the panel, the export sheet and `review.run` show: installed fonts, the text presets' defaults,
    /// the last loudness and picture measurements of this session and the targets of the project's first output
    /// platform (#441; -14 LUFS, -1 dBTP when it names none).
    func reviewIssues() -> [ReviewIssue] {
        let platform = outputPresets.lazy.compactMap(\.platform).first
        let context = ReviewContext(
            fontAvailable: ProjectFonts.isAvailable,
            textDefaults: { preset in
                let defaults = TextPresetStyle.defaults(preset)
                return (defaults["size"] ?? 0.055, defaults["positionY"] ?? 0.18)
            },
            loudness: reviewLoudness, picture: reviewPicture, pluginIssues: reviewPluginIssues,
            targets: ReviewTargets(
                integratedLUFS: project["audio"]?.object["targetLUFS"]?.double ?? platform?.targetLUFS ?? -14,
                maxTruePeakDbTP: platform?.maxTruePeakDbTP ?? -1,
                measureArguments: ["preset": .string(primaryExportPreset.argument)],
                measuresPicture: true, platform: platform))
        return TimelineReview.run(project, context: context)
    }

    /// Whether the Review panel can apply `fix` itself (an edit or an export); other fixes go to the agent.
    func canApply(_ fix: ReviewFix) -> Bool {
        ["timeline.apply", "timeline.close-gap", "export.start", "review.measure"].contains(fix.command ?? "")
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
    func recordReviewLoudness(_ measurement: LoudnessMeasurement?, revision: Int) {
        guard let measurement else { return }
        reviewLoudness = ReviewLoudness(
            revision: revision, integratedLUFS: measurement.integratedLUFS, truePeakDbTP: measurement.truePeakDbTP,
            loudnessRangeLU: measurement.loudnessRangeLU)
    }
}
