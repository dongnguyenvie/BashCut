import BashCutAutomation
import BashCutProject
import Foundation

/// Text from the library: text presets with their stored style and animation (#380), and emoji stickers.
extension ProjectDocument {
    /// A text preset item's preset, text, style and animation.
    func textPreset(_ item: LibraryItem) throws -> LibraryTextPreset {
        do { return try LibraryTextPreset(params: item.params, label: item.reference) } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
    }

    /// Places a text item; `style` gives the properties a text preset item adds to it (#380).
    func placeText(
        _ text: String, preset: String, label: String, _ placement: LibraryPlacement,
        style: ((Item, Project) throws -> [String: JSONValue])? = nil
    ) throws -> (revision: Int, itemID: String) {
        let start = placement.frame ?? playhead
        var item = Item(at: start, duration: placement.duration ?? max(1, min(90, project.duration - start)))
        item["text"] = .string(text)
        item["textPreset"] = .string(preset)
        if let style {
            for (key, value) in try style(item, project) { item[key] = value }
        }
        var planner = LayerPlanner(project)
        let track = try planner.place(item, on: placement.trackID ?? project.requireTrack(role: TrackRole.captions).id)
        let revision = try commitPlan(planner, label: label, author: placement.author, baseRevision: placement.baseRevision)
        selectedTrackID = track
        selectedID = item.id
        return (revision, item.id)
    }
}
