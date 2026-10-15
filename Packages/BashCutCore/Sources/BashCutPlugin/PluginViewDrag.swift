import BashCutProject
import Foundation
import UniformTypeIdentifiers

/// Drag and drop from plugin views (#408, host feature `views.drag`): a list row's `file` or an `image` component's
/// `file` (its `path` when left out) can be dragged onto the timeline or the Media panel, which import it like
/// `media import` (placed with `--place` on the timeline). Only local video, audio and image files qualify.
public enum PluginViewDrag {
    /// The file a drag carries, or nil when `path` is not an absolute path to an existing video, audio or image file.
    public static func file(_ path: String?) -> URL? {
        guard let path, path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard isMedia(url) else { return nil }
        var folder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &folder), !folder.boolValue else { return nil }
        return url
    }

    /// The pasteboard text a library item drag carries: this prefix and the item's reference (`scope:id`).
    public static let libraryPrefix = "bashcut-library:"

    /// The drag payload of a row's or image's `libraryItem` (`scope:id`, as `library list` gives it), or nil when it
    /// is not a reference to a library scope. The timeline places it like `library place`, which checks the rest.
    public static func libraryPayload(_ reference: String?) -> String? {
        guard let reference = libraryReference(reference) else { return nil }
        return libraryPrefix + reference
    }

    /// The library reference a dropped pasteboard text carries, or nil for other text.
    public static func libraryReference(dropped text: String) -> String? {
        guard text.hasPrefix(libraryPrefix) else { return nil }
        return libraryReference(String(text.dropFirst(libraryPrefix.count)))
    }

    private static func libraryReference(_ reference: String?) -> String? {
        guard let reference, (3...300).contains(reference.count), let colon = reference.firstIndex(of: ":"),
            LibraryScope(rawValue: String(reference[..<colon])) != nil, reference.index(after: colon) < reference.endIndex,
            !reference.contains(where: { $0.isNewline || $0 == "\0" })
        else { return nil }
        return reference
    }

    /// A grid tile with `drag: "download"` (API 11): an online result that is not in the library yet. Dropped on the
    /// timeline, the host sends the view a `drag` event for `item` and places the library item the answer names.
    public struct Download: Sendable, Equatable, Codable {
        public let plugin: String
        public let view: String
        public let node: String
        public let item: String

        public init(plugin: String, view: String, node: String, item: String) {
            self.plugin = plugin
            self.view = view
            self.node = node
            self.item = item
        }

        /// The view's key, `<plugin>/<view>`.
        public var key: String { plugin + "/" + view }
    }

    /// The pasteboard text a download drag carries: this prefix and the tile as JSON.
    public static let downloadPrefix = "bashcut-plugin-download:"

    public static func downloadPayload(_ download: Download) -> String? {
        guard !download.item.isEmpty, download.item.count <= 300,
            let data = try? JSONEncoder().encode(download), let json = String(data: data, encoding: .utf8)
        else { return nil }
        return downloadPrefix + json
    }

    /// The tile a dropped pasteboard text carries, or nil for other text.
    public static func download(dropped text: String) -> Download? {
        guard text.hasPrefix(downloadPrefix), text.count <= 2000,
            let download = try? JSONDecoder().decode(Download.self, from: Data(text.dropFirst(downloadPrefix.count).utf8)),
            !download.item.isEmpty, !download.plugin.isEmpty, !download.view.isEmpty, !download.node.isEmpty
        else { return nil }
        return download
    }

    /// Whether the file's type is video, audio or an image (what the timeline and Media panel import).
    public static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .audio) || type.conforms(to: .image)
    }
}
