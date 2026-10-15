import BashCutDocument
import BashCutProject
import Foundation

/// What the status bar says (P1-5): the selection, the project length and the jobs that are running.
extension ProjectDocument {
    /// "1 selected · formula", "3 selected", or "Nothing selected".
    var selectionSummary: String {
        let count = max(selectedIDs.count, selectedID == nil ? 0 : 1)
        guard count > 0 else { return String(localized: "Nothing selected") }
        guard count == 1, let item = selected else { return String(format: String(localized: "%lld selected"), count) }
        return String(localized: "1 selected") + " · " + name(of: item)
    }

    /// The name the timeline draws on a clip: its text, its media's file name or its layer effect's title.
    func name(of item: Item) -> String {
        if selectedItemTrack?.isAdjustment == true { return String(localized: String.LocalizationValue(item.adjustmentTitle(in: project))) }
        if !item.text.isEmpty { return item.text }
        return item.mediaID.flatMap { id in project.media.first { $0.id == id } }.map(\.fileName) ?? item.id
    }

    /// The jobs the status bar counts: queued and running ones.
    var activeJobs: [Job] { jobs.jobs.filter(\.isActive) }

    /// A job's name for people: the tool it belongs to, else its command.
    func jobTitle(_ job: Job) -> String {
        switch job.method {
        case "captions.generate": String(localized: "Auto captions")
        case "beats.detect": String(localized: "Beat detection")
        case "voice.speak": String(localized: "Voiceover")
        case "plugins.run": job.detail.flatMap { plugins.action($0)?.title } ?? job.method
        default: job.method
        }
    }

    /// Opens the place a job runs from: its tool in the Tools panel, else the run panel.
    func openJob(_ job: Job) {
        let tool: String? = switch job.method {
        case "captions.generate": ToolID.captions
        case "beats.detect": ToolID.beats
        case "voice.speak": ToolID.voice
        case "plugins.run": job.detail.flatMap { id in toolEntries.contains { $0.id == id } ? id : nil }
        default: nil
        }
        if let tool { showTool(tool) } else { run(.showRunPanel) }
    }
}
