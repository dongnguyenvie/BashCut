import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutPlugin
import BashCutProject
import Foundation

extension ProjectDocument {
    /// The review the panel, the export sheet and `review.run` show: installed fonts, the text presets' defaults,
    /// the last loudness and picture measurements of this session and social-video targets (-14 LUFS, -1 dBTP).
    func reviewIssues() -> [ReviewIssue] {
        let vertical = project.height > project.width
        let context = ReviewContext(
            fontAvailable: ProjectFonts.isAvailable,
            textDefaults: { preset in
                let defaults = TextPresetStyle.defaults(preset)
                return (defaults["size"] ?? 0.055, defaults["positionY"] ?? 0.18)
            },
            loudness: reviewLoudness, picture: reviewPicture,
            targets: ReviewTargets(
                integratedLUFS: project["audio"]?.object["targetLUFS"]?.double ?? -14,
                measureArguments: ["preset": .string(vertical ? ExportPreset.tiktok.rawValue : ExportPreset.youtube1080.rawValue)],
                measuresPicture: true))
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
                _ = try startPictureMeasure(author: .user)
            default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Renders the timeline small (proxies allowed) and keeps its picture measurement for this revision; the job's
    /// result has the sample count and how many picture issues the review now finds.
    func startPictureMeasure(author: Author) throws -> JSONValue {
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
        let id = jobs.start("review.measure", author: author, work: { [weak self] _ in
            let snapshot = try await engine.build(project, root: root, workspace: workspace, purpose: .preview)
            let picture = try await PictureSampler.measure(snapshot, project: project)
            guard let self else { throw CancellationError() }
            self.reviewPicture = picture
            let found = self.reviewIssues().filter { Self.pictureIssuePrefixes.contains(where: $0.id.hasPrefix) }
            return .object([
                "revision": .integer(picture.revision), "samples": .integer(picture.samples.count),
                "cuts": .integer(picture.cuts.count), "issues": .array(found.map(\.json)),
                "current": .bool(picture.revision == self.project.revision),
            ])
        }, finished: { [weak self] outcome in
            guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
            self?.message = "review.measure: " + error.localizedDescription
        })
        return .object(["job": .string(id), "state": .string("running")])
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
