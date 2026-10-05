import BashCutProject
import Foundation

/// What a composition is for. Preview may read lighter stand-ins; export always reads the originals.
public enum RenderPurpose: Sendable {
    case preview
    case export
}

/// Picks the file the engine reads for a media entry. Items always reference the original; a source
/// may substitute another file with the same timing (a proxy) for some purposes.
public protocol MediaSource: Sendable {
    func url(for media: Media, root: URL, workspace: URL?, purpose: RenderPurpose) throws -> URL
}

/// The original file the project references, for every purpose.
public struct OriginalMediaSource: MediaSource {
    public init() {}

    public func url(for media: Media, root: URL, workspace: URL?, purpose: RenderPurpose) throws -> URL {
        try MediaPathResolver.resolve(media.path, projectRoot: root, workspaceRoot: workspace)
    }
}

/// Previews read `.bashcut/cache/proxies/<media id>.mov` (or `.mp4`) when one exists next to the project;
/// exports and media without a proxy read the original. Proxies must keep the original's frame timing.
public struct ProxyMediaSource: MediaSource {
    public static let folder = ProjectCache.folder + "/" + ProjectCache.Kind.proxies.rawValue
    public static let extensions = ["mov", "mp4"]
    private let original = OriginalMediaSource()

    public init() {}

    public func url(for media: Media, root: URL, workspace: URL?, purpose: RenderPurpose) throws -> URL {
        if purpose == .preview, let proxy = Self.proxyURL(for: media, root: root) { return proxy }
        return try original.url(for: media, root: root, workspace: workspace, purpose: purpose)
    }

    /// The proxy file for `media`, if one exists. Media IDs are restricted to safe file-name characters.
    public static func proxyURL(for media: Media, root: URL) -> URL? {
        guard isSafe(media.id) else { return nil }
        let directory = root.appendingPathComponent(folder, isDirectory: true)
        return extensions.lazy.map { directory.appendingPathComponent(media.id).appendingPathExtension($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Whether a media ID can name a proxy file: letters, digits, `.`, `_`, `-`, not starting with a dot.
    public static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && !id.hasPrefix(".") && id.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }
}
