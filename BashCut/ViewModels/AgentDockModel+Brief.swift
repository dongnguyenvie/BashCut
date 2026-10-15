import AppKit
import BashCutAgent
import BashCutAutomation
import BashCutDocument
import Foundation

/// A button under the agent input that changes with the project state: an editor action, or a request for the agent.
struct BriefQuickAction: Identifiable {
    enum Kind {
        case action(UIAction)
        case request(String)
        case template(String)
    }

    let title: String
    let kind: Kind
    var id: String { title }

    /// The buttons for a state, the main one first. An open but empty project offers Import media instead of New.
    static func actions(for state: BriefFit, hasProject: Bool) -> [BriefQuickAction] {
        switch state {
        case .none:
            return hasProject
                ? [.init(title: String(localized: "Import media…"), kind: .action(.importMedia)),
                   .init(title: String(localized: "Open…"), kind: .action(.openProject))]
                : [.init(title: String(localized: "New project"), kind: .action(.newProject)),
                   .init(title: String(localized: "Open…"), kind: .action(.openProject))]
        case .footage:
            return [
                .init(title: String(localized: "Survey footage"),
                      kind: .request(String(localized: "Survey the project footage and summarize missing coverage."))),
                .init(title: String(localized: "Rough cut"),
                      kind: .request(String(localized: "Make a first rough cut from the footage."))),
                .init(title: String(localized: "Write VO"),
                      kind: .request(String(localized: "Draft voiceover without overlapping real speech."))),
            ]
        case .talk:
            return [
                .init(title: String(localized: "Cut short clips"), kind: .template("clips")),
                .init(title: String(localized: "Remove silences"), kind: .template("silence")),
                .init(title: String(localized: "Captions"), kind: .template("captions")),
            ]
        case .timeline:
            return [
                .init(title: String(localized: "Review"), kind: .action(.showReview)),
                .init(title: String(localized: "Export draft"), kind: .action(.showExport)),
                .init(title: String(localized: "Grade"), kind: .template("color")),
            ]
        case .selection:
            return [
                .init(title: String(localized: "Fix this clip"), kind: .template("fix")),
                .init(title: String(localized: "Replace shot"),
                      kind: .request(String(localized: "Replace the selected shot with a better one from the footage."))),
                .init(title: String(localized: "Review this part"),
                      kind: .request(String(localized: "Review the selected part for pacing, framing and text."))),
            ]
        }
    }
}

extension ProjectDocument {
    /// The project state the brief templates fit: no project, footage, one long talk, a timeline or a selection.
    var briefState: BriefFit {
        let media = project.media.filter { $0.kind == "video" || $0.kind == "audio" }.map {
            BriefFit.Media(seconds: $0.durationSeconds, hasSpeech: $0.hasAudio != false)
        }
        return BriefFit.state(
            hasProject: fileURL != nil, media: media, timelineItems: project.tracks.reduce(0) { $0 + $1.items.count },
            selected: selectedIDs.count)
    }
}

extension AgentDockModel {
    var briefState: BriefFit { document.briefState }

    var quickActions: [BriefQuickAction] {
        BriefQuickAction.actions(for: briefState, hasProject: document.fileURL != nil)
    }

    func perform(_ quick: BriefQuickAction) {
        switch quick.kind {
        case .action(let action): document.run(action)
        case .request(let request): insertBrief(request)
        case .template(let id): if let template = BriefCatalog.template(id) { insert(template) }
        }
    }

    /// A template filled with its defaults, in the agent's input.
    func insert(_ template: BriefTemplate) {
        askModel.pick(template)
        insertBrief(template.prompt())
    }

    /// Puts a request in the input of the agent or chat tab on show. With none on show it opens the New brief sheet
    /// with the request, whose Send goes to the default agent's tab or starts it (Last used, else Claude Code) — never
    /// a chat agent the user did not pick, nor a plain shell.
    func insertBrief(_ request: String) {
        if chatPluginID != nil || current?.provider.isAgent == true {
            fillInput(request)
            if !isDetached { document.ui.showAgentDock = true }
        } else {
            askModel.editDraft(request)
            openBrief()
        }
    }

    /// The New brief sheet, on `template` when given, else on what it showed last or the first quick start.
    func openBrief(template: BriefTemplate? = nil) {
        loadBriefHistory()
        if let template {
            askModel.pick(template)
        } else if askModel.draft.isEmpty, let first = BriefCatalog.quickStarts(for: briefState).first {
            askModel.pick(first)
        }
        document.ui.showAsk = true
    }

    /// The New brief sheet on the composer's message, so it can be finished there.
    func expandToBrief(_ message: String) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, text != askModel.draft {
            askModel.recordID = nil
            askModel.draft = text
            askModel.edited = askModel.template != nil
        }
        openBrief()
    }

    // MARK: Recent and saved briefs

    private var projectFolder: URL? { document.fileURL?.deletingLastPathComponent() }

    func loadBriefHistory() {
        askModel.recent = projectFolder.map(BriefHistory.loadRecent) ?? askModel.recent
        askModel.saved = BriefHistory.loadSaved()
    }

    /// Keeps a sent brief in the project's Recent list (in memory only without a saved project).
    func recordRecentBrief(_ request: String) {
        let footage = askModel.footage.map(\.url.path)
        let record = BriefRecord(
            title: askModel.briefTitle, prompt: request, templateID: askModel.templateID,
            footage: footage.isEmpty ? nil : footage)
        askModel.recent = BriefHistory.adding(record, to: askModel.recent)
        guard let projectFolder else { return }
        do { try BriefHistory.saveRecent(askModel.recent, project: projectFolder) } catch {
            document.message = error.localizedDescription
        }
    }

    /// Save as template: the request and its title, for every project on this Mac.
    func saveBriefAsTemplate() {
        let request = askModel.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        let record = BriefRecord(title: askModel.briefTitle, prompt: request, templateID: askModel.templateID)
        askModel.saved = BriefHistory.adding(record, to: askModel.saved, limit: 50)
        BriefHistory.storeSaved(askModel.saved)
        askModel.recordID = record.id
    }

    /// Add files or folder…: a panel that takes both; agents answer it with `ui respond --path`.
    func chooseBriefFootage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Footage for the agent to import: video, audio, pictures or folders")
        panel.prompt = String(localized: "Add")
        guard let urls = ModalCenter.shared.open(panel, name: "brief-footage") else { return }
        askModel.addFootage(urls)
    }

    func removeSavedBrief(_ record: BriefRecord) {
        askModel.saved.removeAll { $0.id == record.id }
        BriefHistory.storeSaved(askModel.saved)
    }
}
