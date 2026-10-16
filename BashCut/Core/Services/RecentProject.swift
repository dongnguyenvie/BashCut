import BashCutProject
import BashCutStorage
import Foundation

/// One project in the recent-projects history: its file, its name when it was last opened and when that was (#529).
/// Entries remembered by older builds have no name or date.
public struct RecentProject: Sendable, Equatable {
    public let url: URL
    public let name: String?
    public let lastOpened: Date?

    public init(url: URL, name: String? = nil, lastOpened: Date? = nil) {
        self.url = url.standardizedFileURL
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = trimmed.isEmpty ? nil : trimmed
        self.lastOpened = lastOpened
    }

    /// The project folder: the folder of `project.bashcut.json`, or a loose project file itself.
    public var folder: URL { isStandardFile ? url.deletingLastPathComponent() : url.deletingPathExtension() }

    /// The project name, or the folder's name when the project has none.
    public var title: String { name ?? folder.lastPathComponent }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// The folder with the home folder as `~` and the middle left out of a deep path: `~/…/graphics-bench/b2`.
    public func shortPath(home: String = NSHomeDirectory()) -> String {
        var path = folder.path
        if path == home || path.hasPrefix(home + "/") { path = "~" + path.dropFirst(home.count) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 4 else { return path }
        return ([parts[0], "…"] + parts.suffix(2)).joined(separator: "/")
    }

    public var json: JSONValue {
        .object([
            "name": .string(title), "path": .string(url.path),
            "lastOpened": lastOpened.map { .string(Self.dateFormat.string(from: $0)) } ?? .null,
            "exists": .bool(exists),
        ])
    }

    private var isStandardFile: Bool { url.lastPathComponent == ProjectStorage.projectFileName }

    private nonisolated(unsafe) static let dateFormat = ISO8601DateFormatter()

    // MARK: Lists

    /// Menu titles for `projects`, in order: the title alone, or with as many parent folders as tell it apart
    /// when another entry has the same title (VS Code style: `project — b2`, `project — lesson1`).
    public static func menuTitles(_ projects: [RecentProject]) -> [String] {
        let counts = Dictionary(projects.map { ($0.title, 1) }, uniquingKeysWith: +)
        return projects.map { project in
            guard counts[project.title, default: 0] > 1 else { return project.title }
            let others = projects.filter { $0.title == project.title && $0.url != project.url }.map(\.parentFolders)
            let parents = project.parentFolders
            guard !parents.isEmpty else { return project.title }
            for depth in 1...parents.count {
                let suffix = Array(parents.suffix(depth))
                if parents.count <= depth || !others.contains(where: { Array($0.suffix(depth)) == suffix }) {
                    return project.title + " — " + suffix.joined(separator: "/")
                }
            }
            return project.title
        }
    }

    /// The entries matching `query`, best first. Every word of the query must be found in the title or the folder's
    /// path, ignoring case and Vietnamese marks, as written or, in the title and the last folders, with letters in
    /// between (`gbb2` finds `graphics-bench/b2`). Titles that start with the query come first, then matches as
    /// written, then the rest; ties keep the history's order, as an empty query does.
    public static func filter(_ projects: [RecentProject], query: String?) -> [RecentProject] {
        let words = fold(query ?? "").split(separator: " ").map(String.init)
        guard !words.isEmpty else { return projects }
        let first = words.joined(separator: " ")
        let scored: [(project: RecentProject, rank: Int, index: Int)] = projects.enumerated().compactMap { index, project in
            let title = fold(project.title)
            let text = title + " " + fold(project.folder.path)
            // Letters scattered over a whole path match almost anything, so the loose match stays near the end.
            let tail = title + " " + fold(project.folder.pathComponents.suffix(3).joined(separator: "/"))
            var fuzzy = false
            for word in words where !text.contains(word) {
                guard isSubsequence(word, of: tail) else { return nil }
                fuzzy = true
            }
            return (project, (title.hasPrefix(first) ? 0 : 2) + (fuzzy ? 1 : 0), index)
        }
        return scored.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.project)
    }

    /// The folders above the project folder, outermost first.
    private var parentFolders: [String] {
        folder.deletingLastPathComponent().pathComponents.filter { $0 != "/" }
    }

    private static func isSubsequence(_ word: String, of text: String) -> Bool {
        var rest = text[...]
        for character in word {
            guard let found = rest.firstIndex(of: character) else { return false }
            rest = rest[rest.index(after: found)...]
        }
        return true
    }

    private static func fold(_ text: String) -> String {
        text.searchFolded
    }
}
