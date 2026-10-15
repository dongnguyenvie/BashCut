import BashCutAgent
import Foundation
import Observation

/// The New brief sheet: a template with its fields, and the request it makes. Edits to the request by hand stay
/// when fields change, until Reset to template.
@MainActor @Observable final class AgentAskModel {
    var draft = ""
    var attachFrame = false
    /// Files and folders the agent imports for this brief; kept when another template is picked.
    var footage: [BriefFootage.Item] = []
    var sending = false
    /// Where Send goes, when the user picked it in the sheet; nil follows the dock (`AgentDockModel.briefTarget`).
    var target: BriefTarget?
    /// What Send is doing while it starts or waits for an agent.
    var status = ""
    /// Why the last Send failed; the brief stays in the sheet.
    var error = ""
    /// The Send under way, which Cancel stops.
    @ObservationIgnored var sendTask: Task<Void, Never>?
    /// The template whose fields show; nil for a request written from scratch.
    var templateID: String?
    /// The recent or saved brief shown, if one was picked instead of a template.
    var recordID: UUID?
    /// Each field's value by field ID.
    var values: [String: String] = [:]
    /// What the user typed in a field's "other…" chip.
    var custom: [String: String] = [:]
    /// The request was changed by hand: field changes no longer rewrite it.
    var edited = false
    var search = ""
    var recent: [BriefRecord] = []
    var saved: [BriefRecord] = []

    var template: BriefTemplate? { templateID.flatMap(BriefCatalog.template) }

    /// Shows a template with its default values and the request they make.
    func pick(_ template: BriefTemplate) {
        templateID = template.id
        recordID = nil
        values = template.defaultValues
        custom = [:]
        edited = false
        draft = template.prompt(values)
    }

    /// Shows a recent or saved brief: its request as written, and its template's fields when it had one.
    func pick(_ record: BriefRecord) {
        recordID = record.id
        templateID = record.templateID
        values = template?.defaultValues ?? [:]
        custom = [:]
        edited = true
        draft = record.prompt
        footage = (record.footage ?? []).compactMap { BriefFootage.item(URL(fileURLWithPath: $0)) }
    }

    func addFootage(_ urls: [URL]) {
        footage = BriefFootage.adding(urls.compactMap { BriefFootage.item($0) }, to: footage)
    }

    func removeFootage(_ item: BriefFootage.Item) { footage.removeAll { $0.url == item.url } }

    func set(_ field: BriefField, _ value: String) {
        values[field.id] = value
        if !edited, let template { draft = template.prompt(values) }
    }

    /// The request typed in the preview: from now on field changes leave it alone.
    func editDraft(_ text: String) {
        guard text != draft else { return }
        draft = text
        if template != nil { edited = true }
    }

    func resetToTemplate() {
        guard let template else { return }
        edited = false
        draft = template.prompt(values)
    }

    /// The name a sent or saved brief gets: its template's title, or the request's first words.
    var briefTitle: String {
        if let template {
            let topic = template.fields.first(where: \.isText).flatMap { values[$0.id] }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return topic.isEmpty ? template.title : template.title + " · " + topic
        }
        let words = draft.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ")
        return words.isEmpty ? String(localized: "Brief") : words
    }
}
