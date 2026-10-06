import BashCutAutomation
import BashCutEngine
import BashCutPlugin
import BashCutProject
import Foundation

extension ProjectDocument {
    /// The review the panel, the export sheet and `review.run` show: installed fonts, the text presets' defaults,
    /// the last loudness measurement of this session and social-video targets (-14 LUFS, -1 dBTP).
    func reviewIssues() -> [ReviewIssue] {
        let vertical = project.height > project.width
        let context = ReviewContext(
            fontAvailable: ProjectFonts.isAvailable,
            textDefaults: { preset in
                let defaults = TextPresetStyle.defaults(preset)
                return (defaults["size"] ?? 0.055, defaults["positionY"] ?? 0.18)
            },
            loudness: reviewLoudness,
            targets: ReviewTargets(
                integratedLUFS: project["audio"]?.object["targetLUFS"]?.double ?? -14,
                measureArguments: ["preset": .string(vertical ? ExportPreset.tiktok.rawValue : ExportPreset.youtube1080.rawValue)]))
        return TimelineReview.run(project, context: context)
    }

    /// Whether the Review panel can apply `fix` itself (an edit or an export); other fixes go to the agent.
    func canApply(_ fix: ReviewFix) -> Bool {
        ["timeline.apply", "timeline.close-gap", "export.start"].contains(fix.command ?? "")
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
            default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Keeps the loudness a finished export measured, for the revision it now describes.
    func recordReviewLoudness(_ measurement: LoudnessMeasurement?, revision: Int) {
        guard let measurement else { return }
        reviewLoudness = ReviewLoudness(
            revision: revision, integratedLUFS: measurement.integratedLUFS, truePeakDbTP: measurement.truePeakDbTP,
            loudnessRangeLU: measurement.loudnessRangeLU)
    }
}
