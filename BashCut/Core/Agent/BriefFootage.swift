import Foundation
import UniformTypeIdentifiers

/// Files and folders a brief brings for the agent to import: the footage of a new video, or pictures and sources
/// for an explainer. The request names them; the agent imports them with `media import`.
public enum BriefFootage {
    /// How much a template needs footage.
    public enum Need: Sendable, Equatable {
        /// Made from what was shot: the row stands out, and says so while there is none.
        case main
        /// Pictures, screenshots or sources help.
        case optional
        /// An edit of the timeline: no row unless footage was added.
        case none
    }

    /// Templates made from footage.
    static let mainTemplates: Set<String> = [
        "vlog", "travel", "food", "short", "talk", "clips", "review", "ad", "montage", "tutorial",
    ]
    /// Templates and requests where pictures or sources help.
    static let optionalTemplates: Set<String> = ["explainer", "news", "promo", "broll"]

    /// What `templateID` needs; a request written from scratch may bring footage too.
    public static func need(_ templateID: String?) -> Need {
        guard let templateID else { return .optional }
        if mainTemplates.contains(templateID) { return .main }
        return optionalTemplates.contains(templateID) ? .optional : .none
    }

    /// A file or folder added to the brief.
    public struct Item: Sendable, Hashable, Identifiable {
        public let url: URL
        public let isFolder: Bool
        /// Video, audio and picture files in the folder (and its subfolders); 1 for a file.
        public let mediaFiles: Int
        public var id: URL { url }

        public init(url: URL, isFolder: Bool, mediaFiles: Int) {
            self.url = url
            self.isFolder = isFolder
            self.mediaFiles = mediaFiles
        }

        /// The path with `~` for the home folder, a folder ending in `/`.
        public var path: String {
            let path = (url.path as NSString).abbreviatingWithTildeInPath
            return isFolder ? path + "/" : path
        }

        public var name: String { url.lastPathComponent + (isFolder ? "/" : "") }
    }

    /// Whether `url` names a video, audio or picture file.
    public static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .audiovisualContent) || type.conforms(to: .image)
    }

    /// The item for a dropped or chosen URL: a folder with its media files counted (hidden files and packages
    /// skipped, at most `limit` looked at), or a file. Nil when it does not exist.
    public static func item(_ url: URL, limit: Int = 5000) -> Item? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        guard isDirectory.boolValue else { return Item(url: url, isFolder: false, mediaFiles: isMedia(url) ? 1 : 0) }
        var count = 0
        var seen = 0
        let files = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let file = files?.nextObject() as? URL, seen < limit {
            seen += 1
            if isMedia(file) { count += 1 }
        }
        return Item(url: url, isFolder: true, mediaFiles: count)
    }

    /// `items` plus `added`, without the same path twice.
    public static func adding(_ added: [Item], to items: [Item]) -> [Item] {
        added.reduce(items) { list, item in list.contains { $0.url == item.url } ? list : list + [item] }
    }

    /// The line the request ends with: "Footage to import: `~/trip/` (folder, 42 media files), `~/hook.mp4`".
    /// Empty without items.
    public static func line(_ items: [Item]) -> String {
        guard !items.isEmpty else { return "" }
        let parts = items.map { item in
            item.isFolder ? "`\(item.path)` (folder, \(item.mediaFiles) media files)" : "`\(item.path)`"
        }
        return "Footage to import: " + parts.joined(separator: ", ")
    }

    /// `request` with the footage line after it.
    public static func request(_ request: String, items: [Item]) -> String {
        let line = line(items)
        return line.isEmpty ? request : request + "\n" + line
    }
}
