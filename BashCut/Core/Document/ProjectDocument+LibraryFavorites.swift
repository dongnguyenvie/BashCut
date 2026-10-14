import BashCutAutomation
import BashCutProject
import Foundation

/// Favorites (global, on this Mac) and Recent (per project) in the library panels, `library favorite`, and the
/// `favorite` mark in `library list` and `library get`.
extension ProjectDocument {
    /// The item as `library list` returns it, with `favorite: true|false`.
    static func favoriteJSON(_ item: LibraryItem, usage: LibraryUsage?, favorites: Set<String>) -> JSONValue {
        guard case .object(var result) = item.json(usage: usage) else { return .null }
        result["favorite"] = .bool(favorites.contains(item.reference))
        return .object(result)
    }

    /// `library favorite <id> [--off]`.
    func setLibraryFavoriteCommand(_ arguments: CommandArguments) async throws -> JSONValue {
        let catalog = libraryCatalog
        let item = try catalog.item(try arguments.string("id"), scope: Self.scope(arguments))
        let on = !arguments.bool("off")
        try await LibraryWorker.shared.run { try catalog.setFavorite(item, on) }
        libraryRevision += 1
        return .object(["item": .string(item.reference), "favorite": .bool(on)])
    }

    /// The star on a tile and in the context menu. Best effort like usage counts: a failed write shows its message.
    func toggleLibraryFavorite(_ item: LibraryItem, currently: Bool) {
        let catalog = libraryCatalog
        Task {
            do {
                try await LibraryWorker.shared.run { try catalog.setFavorite(item, !currently) }
                libraryRevision += 1
            } catch { message = error.localizedDescription }
        }
    }
}
