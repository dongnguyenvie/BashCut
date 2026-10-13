import BashCutAutomation
import BashCutEngine
import BashCutProject
import Foundation

/// Text from the library: text presets with their stored style and animation (#380), and emoji stickers.
extension ProjectDocument {
    /// A text preset item's preset, text, style and animation. A preset that carries its font file (saved from a
    /// project font) brings the font into this project first, so it draws the same here as where it was saved.
    func textPreset(_ item: LibraryItem) throws -> LibraryTextPreset {
        let preset: LibraryTextPreset
        do { preset = try LibraryTextPreset(params: item.params, label: item.reference) } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
        if let name = preset.textStyle["font"]?.string, let file = libraryCatalog.fileURL(of: item),
            let root = fileURL?.deletingLastPathComponent(), ProjectFonts.file(named: name, projectRoot: root) == nil
        {
            do {
                if try !ProjectFonts.adopt(file, name: name, projectRoot: root).isEmpty {
                    ProjectFontCatalog.shared.activate(projectRoot: root)
                    DebugLog.write("project", "font added from text preset \(item.reference): \(name)")
                    rebuild()
                }
            } catch { throw RPCFailure(-32603, "Could not add the font \(name) of \(item.reference): \(error.localizedDescription)") }
        }
        return preset
    }

    /// The project font file a text preset's `textStyle.font` names, saved with the preset so it travels to other
    /// projects (This Mac library) and packs; nil for other kinds and installed fonts.
    func textPresetFontFile(_ kind: LibraryKind, params: [String: JSONValue]) -> URL? {
        guard kind == .textPreset, let name = params["textStyle"]?.object["font"]?.string,
            let root = fileURL?.deletingLastPathComponent()
        else { return nil }
        return ProjectFonts.file(named: name, projectRoot: root)
    }

    /// The font file a text preset saved before presets carried their font takes when it moves, so it works from
    /// This Mac in other projects; nil when the item has a file or no project font.
    func fontToCarry(_ item: LibraryItem) -> URL? {
        item.file == nil ? item.kind.flatMap { textPresetFontFile($0, params: item.params) } : nil
    }

    /// Moves a library item, adding `font` as its file on the way (a new version).
    nonisolated static func move(_ item: LibraryItem, to scope: LibraryScope, catalog: LibraryCatalog, font: URL?) throws -> LibraryItem {
        let moved = try catalog.move(item, to: scope)
        guard let font else { return moved }
        return try catalog.store(scope).update(moved.id, changes: [:], file: font)
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
        // Without --track a preset is a title: it goes on the titles layer, never among the captions.
        let track = try planner.place(item, on: placement.trackID ?? planner.titleTrack())
        let revision = try commitPlan(planner, label: label, author: placement.author, baseRevision: placement.baseRevision)
        selectedTrackID = track
        selectedID = item.id
        return (revision, item.id)
    }
}
