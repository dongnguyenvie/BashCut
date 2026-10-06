import BashCutProject
import Foundation

/// Selecting several timeline items (⌘-click, ⇧-click, marquee, ⌘A) and the bulk edits on them, each one undo step.
extension ProjectDocument {
    /// The selected items that still exist, in timeline order.
    var selectedItems: [Item] {
        let wanted = Set(selectedIDs)
        return project.tracks.flatMap(\.items).filter { wanted.contains($0.id) }.sorted { $0.at < $1.at }
    }

    /// Selects `ids`; `primary` (or the last ID) becomes `selectedID`, which single-item actions use.
    func select(_ ids: [String], primary: String? = nil) {
        var seen = Set<String>()
        let unique = ids.filter { seen.insert($0).inserted }
        let previous = (selectedIDs, selectedID)
        settingSelection = true
        selectedIDs = unique
        selectedID = primary.flatMap { unique.contains($0) ? $0 : nil } ?? unique.last
        settingSelection = false
        if previous != (selectedIDs, selectedID) { selectionDidChange() }
    }

    /// ⌘-click: adds the item to the selection, or removes it.
    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            let rest = selectedIDs.filter { $0 != id }
            select(rest, primary: selectedID == id ? rest.last : selectedID)
        } else {
            select(selectedIDs + [id], primary: id)
        }
    }

    /// ⇧-click: selects the clips from the primary selection to `id` on `id`'s layer.
    func extendSelection(to id: String) {
        select(selectedIDs + SelectionEdits.range(from: selectedID, to: id, in: project), primary: id)
    }

    func selectAll() { select(SelectionEdits.all(in: project), primary: selectedID) }

    func clearSelection() { select([]) }

    /// Commits bulk operations as one undo step; nothing happens when there are none.
    func commitSelection(_ operations: [EditOperation], label: String, author: Author) throws {
        guard !operations.isEmpty else { return }
        try commit(
            operations.count == 1 ? operations[0] : .group(label: label, author: author, ops: operations),
            label: label, author: author)
    }

    func toggleMuteSelection(author: Author = .user) throws {
        let label = SelectionEdits.allMuted(selectedIDs, in: project) ? "Unmute clips" : "Mute clips"
        try commitSelection(SelectionEdits.toggleMute(selectedIDs, in: project), label: label, author: author)
    }

    /// Moves every selected clip `delta` frames on its own layer, keeping their offsets.
    func moveSelection(by delta: Int, author: Author = .user) throws {
        try commitSelection(try SelectionEdits.shift(selectedIDs, by: delta, in: project), label: "Move clips", author: author)
    }

    func copySelection() {
        guard let copied = TimelineClipboard(copying: selectedIDs, from: project) else { return }
        clipboard = copied
        message = String(format: String(localized: "Copied %d clips"), copied.entries.count)
    }

    func cutSelection(author: Author = .user) throws {
        guard let copied = TimelineClipboard(copying: selectedIDs, from: project) else { return }
        try commitSelection(SelectionEdits.delete(selectedIDs, ripple: false, in: project), label: "Cut clips", author: author)
        clipboard = copied
        clearSelection()
    }

    /// Pastes the copied clips at the playhead and selects the copies.
    func pasteClipboard(author: Author = .user) throws {
        guard let clipboard else { throw ProjectError.invalid("Copy clips first") }
        let pasted = try clipboard.paste(at: playhead, in: project)
        try commitSelection(pasted.operations, label: "Paste clips", author: author)
        select(pasted.ids)
    }
}
