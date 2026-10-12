import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// Brand kits (#453): `library apply` of a `brand` item, `project create --brand` and the Brand panel.
extension ProjectDocument {
    /// Applies the brand kit `item` to the whole project (#453): the `brand` property and every text item tied to
    /// roles, as one undo step. The result names the restyled items.
    @discardableResult
    func applyBrand(_ item: LibraryItem, author: Author = .user, baseRevision: Int? = nil) throws -> JSONValue {
        let operations: [EditOperation]
        do {
            operations = try project.brandOperations(item.params, reference: item.reference, name: item.name)
        } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
        let revision = try commit(
            .group(label: String(localized: "Apply brand \(item.name)"), author: author, ops: operations),
            label: item.name, author: author, baseRevision: baseRevision)
        recordLibraryUse(item)
        let restyled = operations.compactMap { operation -> JSONValue? in
            if case .setProperties(let id, _) = operation { return .string(id) }
            return nil
        }
        return .object([
            "rev": .integer(revision), "library": .string(item.reference), "restyled": .array(restyled),
        ])
    }

    /// `library apply <brand>`: the whole project, so no item, set or range.
    func applyBrand(_ item: LibraryItem, arguments: CommandArguments, author: Author) throws -> JSONValue {
        guard arguments.optionalString("item") == nil, arguments.optionalString("set") == nil,
            arguments.optionalInt("from") == nil, arguments.optionalInt("to") == nil
        else { throw RPCFailure(-32602, "A brand kit applies to the whole project: no item, set, from or to") }
        return try applyBrand(item, author: author, baseRevision: arguments.int("baseRev"))
    }

    /// New Brand Kit… (#453): starts from the project's kit, else a dark starter palette.
    func beginNewBrand() {
        var request = LibraryEditorRequest(
            mode: .saveSelection(.brand), name: String(localized: "My brand kit"), scope: defaultLibraryScope)
        let current = (project["brand"]?.object).map(BrandLibraryView.kitParams) ?? [:]
        request.brand = current.isEmpty
            ? ["palette": .object(["accent": .string("#FFD400"), "background": .string("#111111"), "text": .string("#FFFFFF")])]
            : current
        ui.libraryEditor = request
    }

    /// The Brand panel: applies a kit to the whole project.
    func applyBrandFromLibrary(_ item: LibraryItem) {
        do { try applyBrand(item) } catch { message = error.localizedDescription }
    }

    /// The Brand panel's Remove: the project no longer has a kit; styled text keeps its colours and fonts.
    func clearBrand() {
        do {
            _ = try commit(.setProjectProperties(patch: ["brand": .null]), label: String(localized: "Remove brand kit"))
        } catch { message = error.localizedDescription }
    }
}
