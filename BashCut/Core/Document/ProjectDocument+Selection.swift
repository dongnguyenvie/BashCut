import AppKit
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
    @discardableResult
    func commitSelection(
        _ operations: [EditOperation], label: String, author: Author, baseRevision: Int? = nil,
        coalescingKey: String? = nil
    ) throws -> Int {
        guard !operations.isEmpty else { return project.revision }
        return try commit(
            operations.count == 1 ? operations[0] : .group(label: label, author: author, ops: operations),
            label: label, author: author, baseRevision: baseRevision, coalescingKey: coalescingKey)
    }

    /// Inspector multi-edit: sets `key` (inside `group`) on every selected item it applies to, as one undo step;
    /// slider drags coalesce.
    func patchSelection(_ key: String, group: String? = nil, value: JSONValue, label: String, coalescing: Bool = false) {
        let operations = SelectionEdits.patch(selectedIDs, key: key, group: group, value: value, in: project)
        do {
            try commitSelection(
                operations, label: label, author: .user,
                coalescingKey: coalescing ? "selection.\(group ?? "").\(key).\(selectedIDs.joined(separator: ","))" : nil)
        } catch { message = error.localizedDescription }
    }

    /// Moves the selected clips of magnetic layer `trackID` as one block before `before` (nil: the end).
    func reorderSelection(on trackID: String, before: String?, author: Author = .user) throws {
        try commitSelection(
            try SelectionEdits.reorder(selectedIDs, on: trackID, before: before, in: project), label: "Move clips",
            author: author)
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
        writePasteboard(copied)
        message = String(format: String(localized: "Copied %d clips"), copied.entries.count)
    }

    func cutSelection(author: Author = .user) throws {
        guard let copied = TimelineClipboard(copying: selectedIDs, from: project) else { return }
        writePasteboard(copied)
        try commitSelection(SelectionEdits.delete(selectedIDs, ripple: false, in: project), label: "Cut clips", author: author)
        clipboard = copied
        clearSelection()
    }

    /// Pastes the copied clips at the playhead and selects the copies: BashCut clips on the OS pasteboard (copied in
    /// this or another project or BashCut), adding the media they need, else the clips copied in this window.
    func pasteClipboard(author: Author = .user) throws {
        var source = clipboard
        var addMedia: [EditOperation] = []
        if let json = Self.pasteboardClips() {
            let read = try TimelineClipboard.fromPasteboard(
                json, into: project, projectRoot: fileURL?.deletingLastPathComponent(), workspaceRoot: settings.workspace)
            source = read.clipboard
            addMedia = read.addMedia
        }
        guard let source else { throw ProjectError.invalid("Copy clips first") }
        let staged = addMedia.isEmpty ? project : try project.applying(.group(label: "Paste", author: author, ops: addMedia)).project
        let pasted = try source.paste(at: playhead, in: staged)
        try commitSelection(addMedia + pasted.operations, label: "Paste clips", author: author)
        select(pasted.ids)
    }

    /// Whether the OS pasteboard holds BashCut clips.
    static var pasteboardHasClips: Bool {
        NSPasteboard.general.availableType(from: [NSPasteboard.PasteboardType(TimelineClipboard.pasteboardType)]) != nil
    }

    private static func pasteboardClips() -> JSONValue? {
        guard let data = NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(TimelineClipboard.pasteboardType))
        else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Puts `copied` on the OS pasteboard under BashCut's private type, so it pastes in other projects and windows.
    private func writePasteboard(_ copied: TimelineClipboard) {
        let json = copied.pasteboardJSON(
            from: project, projectRoot: fileURL?.deletingLastPathComponent(), workspaceRoot: settings.workspace)
        guard let data = try? JSONEncoder().encode(json) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(TimelineClipboard.pasteboardType))
    }
}
