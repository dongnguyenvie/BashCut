import BashCutAutomation
import BashCutProject
import Foundation

/// `library list` (with paging), `library save-selection` and `library update`: saving what is selected (a trimmed
/// audio clip saves only the part it plays) and improving an item (a new file is measured again like `library add`).
extension ProjectDocument {
    /// The matching items with their usage: all of them as an array, or with `offset`/`limit` one page as
    /// `{items, total, offset, limit, next}` (`next` is the offset of the following page, null after the last).
    func listLibraryCommand(_ arguments: CommandArguments) throws -> JSONValue {
        let catalog = libraryCatalog
        let usage = try catalog.usage()
        let favorites = Set(try catalog.favorites())
        var items = try catalog.items(matching: Self.filter(arguments))
        if arguments.bool("favorites") { items = items.filter { favorites.contains($0.reference) } }
        if arguments.bool("recent") {
            let order = try catalog.recent()
            items = items.filter { order.contains($0.reference) }.sorted {
                (order.firstIndex(of: $0.reference) ?? 0) < (order.firstIndex(of: $1.reference) ?? 0)
            }
        }
        let json = { (item: LibraryItem) in Self.favoriteJSON(item, usage: usage[item.reference], favorites: favorites) }
        let offset = arguments.optionalInt("offset"), limit = arguments.optionalInt("limit")
        guard offset != nil || limit != nil else { return .array(items.map(json)) }
        let page = LibraryPage(total: items.count, offset: offset ?? 0, limit: limit)
        return page.json(items: items[page.range].map(json))
    }

    func saveSelectionCommand(_ arguments: CommandArguments, author: Author) async throws -> JSONValue {
        let kind = LibraryKind(rawValue: try arguments.string("kind")) ?? .look
        var changes = Self.itemChanges(arguments)
        let selection = try selectionParams(
            kind, itemID: arguments.optionalString("item"), mediaID: arguments.optionalString("media"))
        changes["params"] = .object(selection.params)
        let preview = kind == .effectPreset ? await effectPreview(itemID: arguments.optionalString("item")) : nil
        let trimmed = try await trimmedSelectionFile(selection.params, file: selection.file)
        var waiting = false
        // A save waiting for approval copies the trimmed file later; the system's temporary folder cleans it.
        defer { if !waiting { Self.removeTrimmedSelection(trimmed) } }
        let saved = try await addLibraryItem(
            kind: kind, name: try arguments.string("name"), id: arguments.optionalString("id"),
            scope: LibraryScope(rawValue: try arguments.string("scope")) ?? .project, changes: changes,
            file: trimmed ?? selection.file, preview: preview, author: author, method: "library.save-selection")
        waiting = saved.object["approval"] != nil
        return saved
    }

    func updateLibraryItemCommand(_ arguments: CommandArguments, author: Author) async throws -> JSONValue {
        let catalog = libraryCatalog
        let item = try catalog.item(
            try arguments.string("id"), scope: arguments.optionalString("scope").flatMap(LibraryScope.init(rawValue:)))
        var changes = Self.itemChanges(arguments)
        let file = Self.url(arguments, "file")
        let preview = Self.url(arguments, "preview")
        // A new file is measured like library add, and values measured from the old one are dropped.
        var remeasured: [String: JSONValue] = [:]
        if let file {
            let fresh = item.paramsForNewFile(given: changes["params"]?.object)
            if let measured = try await measuredItemParams(item.kind ?? .sticker, fresh.params, file: file) {
                changes["params"] = .object(measured)
                remeasured["measured"] = .array(
                    LibraryItem.fileMeasuredKeys(item.kind).filter { measured[$0] != nil }.map(JSONValue.string))
                let cleared = fresh.dropped.filter { measured[$0] == nil }
                if !cleared.isEmpty {
                    remeasured["cleared"] = .array(cleared.map(JSONValue.string))
                    if item.kind == .audio { remeasured["note"] = .string("Run library analyze to measure the new file") }
                }
            }
        }
        let finalChanges = changes
        if let newID = arguments.optionalString("as") {
            let scope = arguments.optionalString("into").flatMap(LibraryScope.init(rawValue:)) ?? .project
            _ = try catalog.store(scope)
            let createdBy = LibraryItem.creator(author: author)
            return try await libraryChange(
                "library.update", scope: scope, author: author, arguments: ["id": item.reference, "as": newID]
            ) {
                try catalog.copy(
                    item, as: newID, into: scope, changes: finalChanges, createdBy: createdBy, file: file, preview: preview
                ).json()
            }.merged(remeasured)
        }
        guard item.scope.isWritable else {
            throw RPCFailure(-32602, "\(item.reference) is read-only; pass --as <new-id> to save an improved copy")
        }
        let store = try catalog.store(item.scope)
        return try await libraryChange(
            "library.update", scope: item.scope, author: author, arguments: ["id": item.reference]
        ) {
            try store.update(item.id, changes: finalChanges, file: file, preview: preview).json()
        }.merged(remeasured)
    }
}

private extension JSONValue {
    /// An object result with `extra` keys added; an approval or another shape stays as it is.
    func merged(_ extra: [String: JSONValue]) -> JSONValue {
        guard !extra.isEmpty, case .object(var fields) = self, fields["approval"] == nil else { return self }
        fields.merge(extra) { $1 }
        return .object(fields)
    }
}
