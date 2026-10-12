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

    /// Whether the file's type is video, audio or an image (what the timeline and Media panel import).
    public static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .audio) || type.conforms(to: .image)
    }
}
