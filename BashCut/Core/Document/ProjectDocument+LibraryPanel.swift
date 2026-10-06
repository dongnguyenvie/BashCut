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
        do {
            _ = try selectionParams(kind)
        } catch {
            message = error.localizedDescription
            return
        }
        let text = selected?["text"]?.string.map { String($0.prefix(40)) }
        let name = (kind == .textPreset ? text : nil) ?? String(localized: "My \(Self.kindTitle(kind))")
        ui.libraryEditor = LibraryEditorRequest(
            mode: .saveSelection(kind), name: name.prefix(1).uppercased() + name.dropFirst(), scope: defaultLibraryScope)
    }

    func beginDuplicate(_ item: LibraryItem) {
        let name = item.scope == .builtIn ? String(localized: String.LocalizationValue(item.name)) : item.name
        ui.libraryEditor = LibraryEditorRequest(
            mode: .duplicate(item), name: String(localized: "\(name) copy"), tags: item.tags, pack: item.pack,
            scope: defaultLibraryScope)
    }

    func beginRename(_ item: LibraryItem) {
        ui.libraryEditor = LibraryEditorRequest(
            mode: .rename(item), name: item.name, tags: item.tags, pack: item.pack, scope: item.scope)
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
        let changes: [String: JSONValue] = [
            "name": .string(name), "tags": tags.isEmpty ? .null : .array(tags.map(JSONValue.string)),
            "pack": pack.isEmpty ? .null : .string(pack),
        ]
        runLibraryPanelChange(done: String(localized: "Saved “\(name)” in the library")) { document in
            switch request.mode {
            case .saveSelection(let kind):
                var fields = changes
                fields["params"] = .object(try document.selectionParams(kind))
                return try await document.addLibraryItem(
                    kind: kind, name: name, scope: request.scope, changes: fields, author: .user,
                    method: "library.save-selection")
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
            let store = try document.libraryCatalog.store(item.scope)
            return try await document.libraryChange(
                "library.remove", scope: item.scope, author: .user, arguments: ["id": item.reference, "name": item.name]
            ) {
                .object(["removed": .string(try store.remove(item.id).reference)])
            }
        }
    }

    /// Where an item came from, its license and who made it (`library get` returns the same fields).
    func showLibraryItemInfo(_ item: LibraryItem) {
        let none = String(localized: "Not given")
        var lines = [
            String(localized: "Source: \(item["source"]?.string ?? none)"),
            String(localized: "License: \(item["license"]?.string ?? none)"),
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
        case .sticker: [.image]
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
