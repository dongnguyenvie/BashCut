import BashCutAutomation
import BashCutProject
import Foundation

/// SwiftUI also declares a `LibraryItem` (for the Xcode library); in the app it means BashCut's.
typealias LibraryItem = BashCutProject.LibraryItem

/// Where `library place` puts a new item: the playhead, a default length and layer unless given.
struct LibraryPlacement {
    var frame: Int?
    var duration: Int?
    var trackID: String?
    var author: Author = .user
    var baseRevision: Int?
}

/// Library file work: off the main actor, one job at a time, so two changes never interleave their reads and
/// writes of `library.json` and `usage.json`. Copying and hashing a file of up to 1 GB, packs and stats run here.
actor LibraryWorker {
    static let shared = LibraryWorker()

    func run<T: Sendable>(_ work: @Sendable () throws -> T) throws -> T { try work() }
}

/// Whether `queuePrivilegedApproval` is still running: an auto-approved action is called inside it.
@MainActor
private final class ApprovalCall {
    var inProgress = true
}

/// Library panel items (#74): the catalog of project, user, plugin and built-in items, and the `library` commands.
extension ProjectDocument {
    /// The user library lives in `BashCut/Library` here.
    static let libraryApplicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]

    var libraryCatalog: LibraryCatalog {
        LibraryCatalog(
            user: .user(applicationSupport: Self.libraryApplicationSupport),
            project: fileURL.map { .project(root: $0.deletingLastPathComponent()) })
    }

    // MARK: Using items

    /// Adds `item` to the timeline as a new item and counts the use.
    @discardableResult
    func placeLibraryItem(
        _ item: LibraryItem, _ placement: LibraryPlacement = LibraryPlacement(), text: String? = nil
    ) throws -> (revision: Int, itemID: String) {
        let result: (revision: Int, itemID: String)
        switch item.kind {
        case .textPreset:
            result = try placeText(
                text ?? item.params["text"]?.string ?? item.name, preset: item.params["textPreset"]?.string ?? "",
                label: "Add text", placement)
        case .sticker:
            guard let emoji = item.params["emoji"]?.string else {
                throw RPCFailure(-32602, unsupported("Placing image stickers", item))
            }
            result = try placeText(
                emoji, preset: item.params["textPreset"]?.string ?? "bold-outline", label: "Add text", placement)
        case .look:
            let added = try addAdjustment(
                color: item.params["color"]?.object ?? [:], at: placement.frame, duration: placement.duration,
                trackID: placement.trackID, author: placement.author, baseRevision: placement.baseRevision)
            result = (added.revision, added.itemID)
        default:
            throw RPCFailure(-32602, unsupported("Placing \(item.kind?.rawValue ?? "these") items", item))
        }
        recordLibraryUse(item)
        return result
    }

    /// Uses `item` on the timeline item `itemID` and counts the use.
    @discardableResult
    func applyLibraryItem(
        _ item: LibraryItem, to itemID: String, author: Author = .user, baseRevision: Int? = nil
    ) throws -> Int {
        guard let target = project.tracks.flatMap(\.items).first(where: { $0.id == itemID }) else {
            throw RPCFailure(-32602, "Unknown item \(itemID)")
        }
        let patch: [String: JSONValue]
        switch item.kind {
        case .textPreset:
            guard target["text"] != nil else { throw RPCFailure(-32602, "\(itemID) is not a text item") }
            patch = ["textPreset": item.params["textPreset"] ?? .null]
        case .effectPreset:
            patch = item.params["patch"]?.object ?? [:]
        case .look:
            patch = ["color": .object(item.params["color"]?.object ?? [:])]
        default:
            throw RPCFailure(-32602, unsupported("Applying \(item.kind?.rawValue ?? "these") items", item))
        }
        let revision = try commit(
            .setProperties(item: itemID, patch: patch), label: item.name, author: author, baseRevision: baseRevision)
        recordLibraryUse(item)
        return revision
    }

    /// Library panels: places an item at the playhead.
    func placeFromLibrary(_ item: LibraryItem) {
        do { try placeLibraryItem(item) } catch { message = error.localizedDescription }
    }

    /// Library panels: uses an item on the selected timeline item.
    func applyFromLibrary(_ item: LibraryItem) {
        guard let selectedID else { return }
        do { try applyLibraryItem(item, to: selectedID) } catch { message = error.localizedDescription }
    }

    private func placeText(
        _ text: String, preset: String, label: String, _ placement: LibraryPlacement
    ) throws -> (revision: Int, itemID: String) {
        let start = placement.frame ?? playhead
        var item = Item(at: start, duration: placement.duration ?? max(1, min(90, project.duration - start)))
        item["text"] = .string(text)
        item["textPreset"] = .string(preset)
        var planner = LayerPlanner(project)
        let track = try planner.place(item, on: placement.trackID ?? project.requireTrack(role: TrackRole.captions).id)
        let revision = try commitPlan(planner, label: label, author: placement.author, baseRevision: placement.baseRevision)
        selectedTrackID = track
        selectedID = item.id
        return (revision, item.id)
    }

    private func unsupported(_ action: String, _ item: LibraryItem) -> String {
        let file = libraryCatalog.fileURL(of: item).map { "; its file is \($0.path) (media import, then media place)" }
        return "\(action) from the library is not supported yet" + (file ?? "")
    }

    /// Usage counts are best effort and written in the background: a failed write never fails the edit.
    private func recordLibraryUse(_ item: LibraryItem) {
        let catalog = libraryCatalog
        Task {
            do { try await LibraryWorker.shared.run { try catalog.recordUse(item) } } catch {
                DebugLog.write("library", "usage not saved: \(error)")
            }
        }
    }

    // MARK: Automation

    /// Runs a change to the library on the `LibraryWorker` now, or after approval when an agent writes to the user
    /// scope.
    private func libraryChange(
        _ method: String, scope: LibraryScope, author: Author, arguments: [String: String],
        action: @escaping @Sendable () throws -> JSONValue
    ) async throws -> JSONValue {
        guard scope == .user, author != .user else { return try await runLibraryChange(action) }
        let call = ApprovalCall()
        let request = try queuePrivilegedApproval(method: method, author: author, arguments: arguments) { [weak self] in
            // Auto-approved, the change runs below. Approved later, it starts here; errors show like other actions'.
            guard !call.inProgress, let self else { return }
            Task {
                do { _ = try await self.runLibraryChange(action) } catch { self.message = error.localizedDescription }
            }
        }
        call.inProgress = false
        guard request.autoApproved else {
            message = String(localized: "Waiting for approval: \(method)")
            return .object(["approval": .string("pending"), "requestId": .string(request.id.uuidString)])
        }
        return try await runLibraryChange(action)
    }

    private func runLibraryChange(_ action: @escaping @Sendable () throws -> JSONValue) async throws -> JSONValue {
        let result = try await LibraryWorker.shared.run(action)
        libraryRevision += 1
        return result
    }

    private static func filter(_ arguments: CommandArguments) -> LibraryCatalog.Filter {
        var kinds = arguments.optionalString("kind").flatMap(LibraryKind.init(rawValue:)).map { [$0] }
        if let panel = arguments.optionalString("panel") {
            let inPanel = LibraryKind.kinds(inPanel: panel)
            kinds = kinds.map { $0.filter(inPanel.contains) } ?? inPanel
        }
        return LibraryCatalog.Filter(
            kinds: kinds, tag: arguments.optionalString("tag"),
            scope: arguments.optionalString("scope").flatMap(LibraryScope.init(rawValue:)),
            creator: arguments.optionalString("createdBy"), pack: arguments.optionalString("pack"),
            query: arguments.optionalString("query"))
    }

    /// The item fields `library add` and `library update` take, as changes.
    private static func itemChanges(_ arguments: CommandArguments) -> [String: JSONValue] {
        var changes: [String: JSONValue] = [:]
        if let name = arguments.optionalString("name") { changes["name"] = .string(name) }
        if let tags = arguments.optionalString("tags") {
            let list = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            changes["tags"] = .array(list.map(JSONValue.string))
        }
        for key in ["pack", "source", "license"] {
            if let value = arguments.optionalString(key) { changes[key] = .string(value) }
        }
        if let params = arguments["params"] { changes["params"] = params }
        return changes
    }

    private static func url(_ arguments: CommandArguments, _ key: String) -> URL? {
        arguments.optionalString(key).map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    /// An item ID from a display name: ASCII lowercase letters and digits joined by hyphens.
    static func libraryID(from name: String) -> String {
        let folded = name.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let words = folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return String(words.joined(separator: "-").prefix(64)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    func registerLibraryCommands() {
        registerLibraryReadCommands()
        registerLibraryChangeCommands()
        registerLibraryUseCommands()
        registerLibraryPackCommands()
    }

    private func registerLibraryReadCommands() {
        handle("library.list") { document, arguments, _ in
            let catalog = document.libraryCatalog
            let usage = try catalog.usage()
            return .array(try catalog.items(matching: Self.filter(arguments)).map { $0.json(usage: usage[$0.reference]) })
        }
        handle("library.get") { document, arguments, _ in
            let catalog = document.libraryCatalog
            let item = try catalog.item(try arguments.string("id"), scope: Self.scope(arguments))
            guard case .object(var result) = item.json(usage: try catalog.usage()[item.reference], includeHistory: true)
            else { return .null }
            result["fileURL"] = catalog.fileURL(of: item).map { .string($0.path) } ?? .null
            return .object(result)
        }
        handle("library.stats") { document, arguments, _ in
            let catalog = document.libraryCatalog
            let kinds = Self.filter(arguments).kinds
            return try await LibraryWorker.shared.run { try catalog.stats(kinds: kinds) }
        }
    }

    private func registerLibraryChangeCommands() {
        handleAuthored("library.add") { document, arguments, author in
            let catalog = document.libraryCatalog
            let kind = LibraryKind(rawValue: try arguments.string("kind")) ?? .sticker
            let name = try arguments.string("name")
            let slug = Self.libraryID(from: name)
            let id = arguments.optionalString("id") ?? (slug.isEmpty ? "\(kind.rawValue)-\(UUID().uuidString.prefix(8).lowercased())" : slug)
            var item = LibraryItem(id: id, kind: kind, name: name)
            for (key, value) in Self.itemChanges(arguments) { item[key] = value }
            item["createdBy"] = LibraryItem.creator(author: author)
            let scope = LibraryScope(rawValue: try arguments.string("scope")) ?? .project
            let file = Self.url(arguments, "file")
            let preview = Self.url(arguments, "preview")
            _ = try catalog.store(scope)
            let added = item
            return try await document.libraryChange(
                "library.add", scope: scope, author: author, arguments: ["id": id, "kind": kind.rawValue, "name": name]
            ) {
                try catalog.add(added, into: scope, file: file, preview: preview).json()
            }
        }
        handleAuthored("library.update") { document, arguments, author in
            let catalog = document.libraryCatalog
            let item = try catalog.item(try arguments.string("id"), scope: Self.scope(arguments))
            let changes = Self.itemChanges(arguments)
            let file = Self.url(arguments, "file")
            let preview = Self.url(arguments, "preview")
            if let newID = arguments.optionalString("as") {
                let scope = arguments.optionalString("into").flatMap(LibraryScope.init(rawValue:)) ?? .project
                _ = try catalog.store(scope)
                let createdBy = LibraryItem.creator(author: author)
                return try await document.libraryChange(
                    "library.update", scope: scope, author: author, arguments: ["id": item.reference, "as": newID]
                ) {
                    try catalog.copy(
                        item, as: newID, into: scope, changes: changes, createdBy: createdBy, file: file, preview: preview
                    ).json()
                }
            }
            guard item.scope.isWritable else {
                throw RPCFailure(
                    -32602, "\(item.reference) is read-only; pass --as <new-id> to save an improved copy")
            }
            let store = try catalog.store(item.scope)
            return try await document.libraryChange(
                "library.update", scope: item.scope, author: author, arguments: ["id": item.reference]
            ) {
                try store.update(item.id, changes: changes, file: file, preview: preview).json()
            }
        }
        handleAuthored("library.remove") { document, arguments, author in
            let catalog = document.libraryCatalog
            let item = try catalog.item(try arguments.string("id"), scope: Self.scope(arguments))
            guard item.scope.isWritable else {
                throw RPCFailure(-32602, "\(item.reference) is \(item.scope.rawValue) and cannot be removed")
            }
            let store = try catalog.store(item.scope)
            return try await document.libraryChange(
                "library.remove", scope: item.scope, author: author, arguments: ["id": item.reference, "name": item.name]
            ) {
                .object(["removed": .string(try store.remove(item.id).reference)])
            }
        }
    }

    private func registerLibraryUseCommands() {
        handleAuthored("library.apply") { document, arguments, author in
            let item = try document.libraryCatalog.item(try arguments.string("id"), scope: Self.scope(arguments))
            guard let target = arguments.optionalString("item") ?? document.selectedID else {
                throw RPCFailure(-32602, "Select an item or pass --item")
            }
            let revision = try document.applyLibraryItem(
                item, to: target, author: author, baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(revision), "item": .string(target), "library": .string(item.reference)])
        }
        handleAuthored("library.place") { document, arguments, author in
            let item = try document.libraryCatalog.item(try arguments.string("id"), scope: Self.scope(arguments))
            let placement = LibraryPlacement(
                frame: arguments.optionalInt("atFrame"), duration: arguments.optionalInt("duration"),
                trackID: arguments.optionalString("track"), author: author, baseRevision: try arguments.int("baseRev"))
            let result = try document.placeLibraryItem(item, placement, text: arguments.optionalString("text"))
            return .object([
                "rev": .integer(result.revision), "item": .string(result.itemID), "library": .string(item.reference),
            ])
        }
    }

    private func registerLibraryPackCommands() {
        handleAuthored("library.import-pack") { document, arguments, author in
            let catalog = document.libraryCatalog
            let scope = LibraryScope(rawValue: try arguments.string("scope")) ?? .project
            _ = try catalog.store(scope)
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("bashcut-pack-\(UUID().uuidString)", isDirectory: true)
            let source = URL(fileURLWithPath: try arguments.string("path")).standardizedFileURL
            let pack = try await LibraryWorker.shared.run {
                do { return try LibraryPack.read(try LibraryPack.folder(at: source, scratch: scratch)) } catch {
                    try? FileManager.default.removeItem(at: scratch)
                    throw error
                }
            }
            let replace = arguments.bool("replace")
            let createdBy = LibraryItem.creator(author: author)
            return try await document.libraryChange(
                "library.import-pack", scope: scope, author: author,
                arguments: ["pack": pack.name, "items": pack.items.map(\.id).joined(separator: ", ")]
            ) {
                defer { try? FileManager.default.removeItem(at: scratch) }
                let items = try LibraryPack.importItems(
                    pack, into: scope, catalog: catalog, replace: replace, createdBy: createdBy)
                return .object(["pack": .string(pack.name), "items": .array(items.map { $0.json() })])
            }
        }
        handleAuthored("library.export-pack") { document, arguments, _ in
            let catalog = document.libraryCatalog
            let output = URL(fileURLWithPath: try arguments.string("output")).standardizedFileURL
            let filter = Self.filter(arguments)
            guard filter.pack != nil || filter.kinds != nil || filter.scope != nil else {
                throw RPCFailure(-32602, "Choose what to export with --pack, --kind or --scope")
            }
            let name = arguments.optionalString("name") ?? filter.pack ?? output.lastPathComponent
            let items = try await LibraryWorker.shared.run {
                let items = try catalog.items(matching: filter)
                try LibraryPack.export(items, name: name, catalog: catalog, to: output)
                return items
            }
            return .object([
                "output": .string(output.path), "name": .string(name), "items": .array(items.map { .string($0.reference) }),
            ])
        }
    }

    private static func scope(_ arguments: CommandArguments) -> LibraryScope? {
        arguments.optionalString("scope").flatMap(LibraryScope.init(rawValue:))
    }
}
