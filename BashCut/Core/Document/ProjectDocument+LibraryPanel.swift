import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation
import UniformTypeIdentifiers

/// What the library panels do (#80): Add…, drops, Save selection as…, and each item's context menu. Every action
/// runs the same code as its `library` command, as the user.
extension ProjectDocument {
    /// Where the panels save: the open project, or this Mac without one.
    var defaultLibraryScope: LibraryScope { fileURL == nil ? .user : .project }

    // MARK: Item sheet

    func beginSaveSelection(as kind: LibraryKind) {
        let params: [String: JSONValue]
        do {
            params = try selectionParams(kind).params
        } catch {
            message = error.localizedDescription
            return
        }
        let text = selected?["text"]?.string.map { String($0.prefix(40)) }
        let name = (kind == .textPreset ? text : nil) ?? String(localized: "My \(Self.kindTitle(kind))")
        var request = LibraryEditorRequest(
            mode: .saveSelection(kind), name: name.prefix(1).uppercased() + name.dropFirst(), scope: defaultLibraryScope)
        if kind == .audio { request.audio = try? LibraryAudio(params: params) }
        if kind == .sticker {
            request.sticker = try? LibrarySticker(params: params, file: params["emoji"] == nil ? "sticker.png" : nil)
        }
        if kind == .textPreset { request.textPreset = try? LibraryTextPreset(params: params) }
        ui.libraryEditor = request
    }

    func beginDuplicate(_ item: LibraryItem) {
        let name = item.scope == .builtIn ? String(localized: String.LocalizationValue(item.name)) : item.name
        var request = LibraryEditorRequest(
            mode: .duplicate(item), name: String(localized: "\(name) copy"), tags: item.tags, pack: item.pack,
            scope: defaultLibraryScope, transition: editableTransition(item), look: editableLook(item),
            keepsLUT: editableLook(item) != nil && item.file != nil ? true : nil)
        request.audio = editableAudio(item)
        request.sticker = editableSticker(item)
        request.textPreset = editableTextPreset(item)
        ui.libraryEditor = request
    }

    /// Rename…, and Edit… for a transition preset, whose kind, duration, easing and sound the sheet also shows, for
    /// a look, whose grade and LUT it shows, or for a text preset, whose size, position, outline and animation it shows.
    func beginRename(_ item: LibraryItem) {
        var request = LibraryEditorRequest(
            mode: .rename(item), name: item.name, tags: item.tags, pack: item.pack, scope: item.scope,
            transition: editableTransition(item), look: editableLook(item),
            keepsLUT: editableLook(item) != nil && item.file != nil ? true : nil)
        request.audio = editableAudio(item)
        request.sticker = editableSticker(item)
        request.textPreset = editableTextPreset(item)
        ui.libraryEditor = request
    }

    /// A text preset's style and animation for the sheet (#380).
    private func editableTextPreset(_ item: LibraryItem) -> LibraryTextPreset? {
        item.kind == .textPreset ? try? LibraryTextPreset(params: item.params) : nil
    }

    /// An image, animated or video sticker's size, position and animation for the sheet (#64); emoji stickers have
    /// none.
    private func editableSticker(_ item: LibraryItem) -> LibrarySticker? {
        guard item.kind == .sticker, let sticker = try? LibrarySticker(params: item.params, file: item.file) else {
            return nil
        }
        return sticker.isMedia ? sticker : nil
    }

    /// An audio item's role and loop flag for the sheet (#78).
    private func editableAudio(_ item: LibraryItem) -> LibraryAudio? {
        item.kind == .audio ? (try? LibraryAudio(params: item.params)) ?? LibraryAudio() : nil
    }

    private func editableLook(_ item: LibraryItem) -> FilterStack? {
        item.kind == .look ? try? FilterStack(params: item.params) : nil
    }

    /// The changes that save the sheet's look fields on `item`: its grade and LUT name (keeping other params), and
    /// without its LUT when the sheet dropped it.
    static func lookChanges(_ edited: FilterStack, keepsLUT: Bool?, item: LibraryItem) -> [String: JSONValue] {
        var stack = edited
        var changes: [String: JSONValue] = [:]
        if keepsLUT == false {
            stack.lutName = nil
            stack.color["lutStrength"] = nil
            changes["file"] = .null
        }
        var params = item.params
        for key in ["color", "lutName"] { params[key] = nil }
        params.merge(stack.params) { $1 }
        changes["params"] = .object(params)
        return changes
    }

    /// A transition preset's params for the sheet, with `sfx` written `scope:id` so the sound picker finds it, and
    /// `file` standing for the preset's own sound.
    private func editableTransition(_ item: LibraryItem) -> TransitionPreset? {
        guard item.kind == .transitionPreset, var preset = try? TransitionPreset(params: item.params) else { return nil }
        if let sfx = preset.sfx {
            preset.sfx = (try? libraryCatalog.item(sfx).reference) ?? sfx
        } else if item.file != nil {
            preset.sfx = Self.ownTransitionSound
        }
        return preset
    }

    /// The sheet's sound choice for a transition preset's own file.
    static let ownTransitionSound = "file"

    /// The changes that save the sheet's transition fields on `item`: its params (keeping any others) and, when
    /// the preset no longer uses its own sound, no file.
    static func transitionChanges(_ edited: TransitionPreset, item: LibraryItem) -> [String: JSONValue] {
        var preset = edited
        if preset.sfx == ownTransitionSound { preset.sfx = nil }
        var params = item.params
        for key in ["kind", "duration", "easing", "sfx"] { params[key] = nil }
        params.merge(preset.params) { $1 }
        var changes: [String: JSONValue] = ["params": .object(params)]
        if item.file != nil, edited.sfx != ownTransitionSound { changes["file"] = .null }
        return changes
    }

    /// The changes the sheet's kind fields (a transition, look, audio, sticker or text preset) make to `item`.
    private static func kindChanges(_ request: LibraryEditorRequest, item: LibraryItem) -> [String: JSONValue] {
        var changes: [String: JSONValue] = [:]
        if let transition = request.transition { changes.merge(transitionChanges(transition, item: item)) { $1 } }
        if let look = request.look { changes.merge(lookChanges(look, keepsLUT: request.keepsLUT, item: item)) { $1 } }
        if let audio = request.audio { changes["params"] = .object(audio.params(merging: item.params)) }
        if let sticker = request.sticker { changes["params"] = .object(sticker.params(merging: item.params)) }
        if let text = request.textPreset { changes["params"] = .object(text.params(merging: item.params)) }
        return changes
    }

    /// Saves what the item sheet shows and closes it.
    func commitLibraryEditor() {
        guard let request = ui.libraryEditor else { return }
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            message = String(localized: "Give the item a name")
            return
        }
        ui.libraryEditor = nil
        let tags = request.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let pack = request.pack.trimmingCharacters(in: .whitespacesAndNewlines)
        var edited: [String: JSONValue] = [
            "name": .string(name), "tags": tags.isEmpty ? .null : .array(tags.map(JSONValue.string)),
            "pack": pack.isEmpty ? .null : .string(pack),
        ]
        switch request.mode {
        case .duplicate(let item), .rename(let item): edited.merge(Self.kindChanges(request, item: item)) { $1 }
        case .saveSelection: break
        }
        let changes = edited
        runLibraryPanelChange(done: String(localized: "Saved “\(name)” in the library")) { document in
            switch request.mode {
            case .saveSelection(let kind):
                var fields = changes
                let selection = try document.selectionParams(kind, mediaID: request.mediaID)
                fields["params"] = .object(
                    request.audio.map { $0.params(merging: selection.params) }
                        ?? request.sticker.map { $0.params(merging: selection.params) }
                        ?? request.textPreset.map { $0.params(merging: selection.params) } ?? selection.params)
                let preview = kind == .effectPreset ? await document.effectPreview(itemID: nil) : nil
                return try await document.addLibraryItem(
                    kind: kind, name: name, scope: request.scope, changes: fields, file: selection.file, preview: preview,
                    author: .user, method: "library.save-selection")
            case .duplicate(let item):
                return try await document.duplicateLibraryItem(item, into: request.scope, changes: changes, author: .user)
            case .rename(let item):
                let store = try document.libraryCatalog.store(item.scope)
                return try await document.libraryChange(
                    "library.update", scope: item.scope, author: .user, arguments: ["id": item.reference]
                ) {
                    try store.update(item.id, changes: changes).json()
                }
            }
        }
    }

    /// The item sheet as automation sees it: save with the shown fields, or cancel.
    func libraryEditorSheet() -> ModalSheet? {
        guard let request = ui.libraryEditor else { return nil }
        let title = switch request.mode {
        case .saveSelection: "Save selection as"
        case .duplicate: "Duplicate & Edit"
        case .rename: "Rename"
        }
        return ModalSheet(
            name: "library-item", title: title,
            message: "\(request.name) · \(request.scope.rawValue); library save-selection, update --as and update "
                + "--name do the same with every field.",
            options: [ModalOption("save", String(localized: "Save")), ModalOption("cancel", String(localized: "Cancel"))]
        ) { [weak self] option in
            if option == "save" { self?.commitLibraryEditor() } else { self?.ui.libraryEditor = nil }
        }
    }

    /// Saves a copy of `item` under a new ID made from its new name (`library update --as`).
    func duplicateLibraryItem(
        _ item: LibraryItem, into scope: LibraryScope, changes: [String: JSONValue], author: Author
    ) async throws -> JSONValue {
        let catalog = libraryCatalog
        _ = try catalog.store(scope)
        let taken = Set(try catalog.items().map(\.id))
        let slug = Self.libraryID(from: changes["name"]?.string ?? "")
        let base = String((slug.isEmpty ? "\(item.id)-copy" : slug).prefix(60))
        var id = base
        var number = 2
        while taken.contains(id) {
            id = "\(base)-\(number)"
            number += 1
        }
        let newID = id
        let createdBy = LibraryItem.creator(author: author)
        return try await libraryChange(
            "library.update", scope: scope, author: author, arguments: ["id": item.reference, "as": newID]
        ) {
            try catalog.copy(item, as: newID, into: scope, changes: changes, createdBy: createdBy).json()
        }
    }

    // MARK: Context menu

    func moveFromLibraryPanel(_ item: LibraryItem, to scope: LibraryScope) {
        let place = scope == .project ? String(localized: "the project") : String(localized: "this Mac")
        runLibraryPanelChange(done: String(localized: "Moved “\(item.name)” to \(place)")) { document in
            try await document.moveLibraryItem(item, to: scope, author: .user)
        }
    }

    func removeFromLibraryPanel(_ item: LibraryItem) {
        let answer = ModalCenter.shared.alert(
            "remove-library-item", title: String(localized: "Remove “\(item.name)”?"),
            message: String(localized: "Its files and earlier versions are deleted. Timeline items that used it stay."),
            buttons: [
                ModalOption("remove", String(localized: "Remove from Library")), ModalOption("cancel", String(localized: "Cancel")),
            ])
        guard answer == "remove" else { return }
        runLibraryPanelChange(done: String(localized: "Removed “\(item.name)”")) { document in
            try await document.removeLibraryItem(item, author: .user)
        }
    }

    /// Where an item came from, its license and who made it (`library get` returns the same fields).
    func showLibraryItemInfo(_ item: LibraryItem) {
        let none = String(localized: "Not given")
        var lines = [
            String(localized: "Source: \(item["source"]?.string ?? none)"),
            String(localized: "License: \(item.licenseTerms?.displayName ?? none)"),
            String(localized: "Made by: \(Self.creatorTitle(item))"),
            String(localized: "Version \(String(item.version)) · \(Self.scopeTitle(item.scope))"),
        ]
        if let basedOn = item["basedOn"]?.string { lines.append(String(localized: "Based on: \(basedOn)")) }
        let source = item["source"]?.string.flatMap(URL.init(string:)).flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil }
        var buttons = [ModalOption("ok", String(localized: "OK"))]
        if source != nil { buttons.append(ModalOption("open-source", String(localized: "Open Source"))) }
        let answer = ModalCenter.shared.alert(
            "library-item-info", title: item.name, message: lines.joined(separator: "\n"), buttons: buttons,
            style: .informational)
        if answer == "open-source", let source { NSWorkspace.shared.open(source) }
    }

    func revealLibraryFile(_ item: LibraryItem) {
        guard let url = libraryCatalog.fileURL(of: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Adding

    /// Add…: files of `kind` (audio, sticker images) or packs.
    func chooseLibraryFiles(kind: LibraryKind?) {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose files or a library pack (a folder with pack.json, or a .zip)")
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = (kind.map(Self.fileTypes) ?? []) + [.zip, .folder]
        guard let urls = ModalCenter.shared.open(panel, name: "library-add") else { return }
        addFilesToLibrary(urls, kind: kind)
    }

    /// Adds dropped or chosen files: packs are imported, other files become `kind` items named after the file.
    func addFilesToLibrary(_ urls: [URL], kind: LibraryKind?) {
        let scope = defaultLibraryScope
        Task {
            var added = 0
            for url in urls {
                do {
                    var isFolder: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
                    if isFolder.boolValue || url.pathExtension.lowercased() == "zip" {
                        _ = try await importLibraryPack(url, scope: scope, replace: false, author: .user)
                    } else if let kind, Self.accepts(url, kind: kind) {
                        _ = try await addLibraryItem(
                            kind: kind, name: url.deletingPathExtension().lastPathComponent, scope: scope, changes: [:],
                            file: url, author: .user)
                    } else {
                        throw RPCFailure(-32602, String(localized: "\(url.lastPathComponent) is not a pack or a file this panel takes"))
                    }
                    added += 1
                } catch {
                    message = error.localizedDescription
                }
            }
            if added > 0 { message = String(localized: "Added \(added) to the library") }
        }
    }

    // MARK: Helpers

    private func runLibraryPanelChange(
        done: String, _ change: @escaping @MainActor (ProjectDocument) async throws -> JSONValue
    ) {
        Task {
            do {
                let result = try await change(self)
                message = result.object["approval"] == nil ? done : message
            } catch {
                message = error.localizedDescription
            }
        }
    }

    static func fileTypes(_ kind: LibraryKind) -> [UTType] {
        switch kind {
        case .audio: [.audio]
        case .sticker: [.image, .movie]
        case .look: [UTType(filenameExtension: "cube")].compactMap { $0 }
        case .clip: [.image, .movie]
        default: []
        }
    }

    static func accepts(_ url: URL, kind: LibraryKind) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return fileTypes(kind).contains { type.conforms(to: $0) }
    }

    static func kindTitle(_ kind: LibraryKind) -> String {
        switch kind {
        case .audio: String(localized: "audio")
        case .textPreset: String(localized: "text style")
        case .sticker: String(localized: "sticker")
        case .effectPreset: String(localized: "effect")
        case .transitionPreset: String(localized: "transition")
        case .look: String(localized: "look")
        case .voice: String(localized: "voice")
        case .clip: String(localized: "clip")
        }
    }

    static func scopeTitle(_ scope: LibraryScope) -> String {
        switch scope {
        case .builtIn: String(localized: "Built-in")
        case .user: String(localized: "This Mac")
        case .project: String(localized: "Project")
        case .plugin: String(localized: "Plugin")
        }
    }

    static func creatorTitle(_ item: LibraryItem) -> String {
        switch item.creator {
        case "agent": item.createdBy["agent"]?.string.map { String(localized: "Agent (\($0))") } ?? String(localized: "Agent")
        case "plugin": item.createdBy["plugin"]?.string ?? String(localized: "Plugin")
        case "user": String(localized: "You")
        default: String(localized: "BashCut")
        }
    }
}
