import Foundation

/// Favourites and the recent list: two small files next to `usage.json`, so starring an item or placing one never
/// rewrites `library.json`. Favourites are global (`favorites.json` in the user store); the recent list is per
/// project (`recent.json` in the project store). Both keep `scope:id` references and fields they do not know.
extension LibraryStore {
    public static let maximumRecent = 20
    public static let maximumFavorites = 1_000

    public var favoritesFile: URL { root.appendingPathComponent("favorites.json") }
    public var recentFile: URL { root.appendingPathComponent("recent.json") }

    /// Favourite references, oldest first.
    public func favorites() throws -> [String] { try references(in: favoritesFile, key: "favorites") }

    /// Stars (`on`) or unstars `reference`. Starring twice keeps one entry.
    public func setFavorite(_ reference: String, _ on: Bool) throws {
        var list = try favorites()
        guard list.contains(reference) != on else { return }
        if on {
            guard list.count < Self.maximumFavorites else {
                throw ProjectError.invalid("At most \(Self.maximumFavorites) favourites")
            }
            list.append(reference)
        } else {
            list.removeAll { $0 == reference }
        }
        try saveReferences(list, in: favoritesFile, key: "favorites")
    }

    /// The last items placed or applied in this project, newest first.
    public func recent() throws -> [String] { try references(in: recentFile, key: "recent") }

    /// Puts `reference` first; the list keeps `maximumRecent` entries.
    public func recordRecent(_ reference: String) throws {
        var list = try recent()
        list.removeAll { $0 == reference }
        list.insert(reference, at: 0)
        try saveReferences(Array(list.prefix(Self.maximumRecent)), in: recentFile, key: "recent")
    }

    /// Drops a removed item from both lists.
    func forget(_ reference: String) throws {
        for (file, key) in [(favoritesFile, "favorites"), (recentFile, "recent")] {
            let list = try references(in: file, key: key)
            if list.contains(reference) { try saveReferences(list.filter { $0 != reference }, in: file, key: key) }
        }
    }

    private func document(_ file: URL) throws -> [String: JSONValue] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file)).object
        } catch {
            throw ProjectError.invalid("\(file.path) is not valid JSON: \(error.localizedDescription)")
        }
    }

    private func references(in file: URL, key: String) throws -> [String] {
        try (document(file)[key]?.array ?? []).compactMap(\.string)
    }

    private func saveReferences(_ list: [String], in file: URL, key: String) throws {
        var fields = try document(file)
        fields["format"] = .integer(Self.format)
        fields[key] = .array(list.map(JSONValue.string))
        try write(.object(fields), to: file)
    }
}
