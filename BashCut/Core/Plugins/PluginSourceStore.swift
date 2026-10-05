import BashCutPlugin
import Foundation

/// Where plugins installed from a link came from (#83), by installed folder, in
/// `~/Library/Application Support/BashCut/PluginSources.json`. Kept outside the plugin folder so the trusted files
/// stay exactly the downloaded ones.
public struct PluginSourceStore: Sendable {
    public let file: URL

    public init(file: URL) { self.file = file }

    /// The store next to the user plugin folder.
    public init(userRoot: URL) {
        self.init(file: userRoot.deletingLastPathComponent().appendingPathComponent("PluginSources.json"))
    }

    public func origin(of directory: URL) -> PluginLinkOrigin? { load()[Self.key(directory)] }

    /// Records `origin` for the plugin installed at `directory`; nil forgets it.
    public func set(_ origin: PluginLinkOrigin?, for directory: URL) throws {
        var all = load()
        all[Self.key(directory)] = origin
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(all).write(to: file, options: .atomic)
    }

    private func load() -> [String: PluginLinkOrigin] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: PluginLinkOrigin].self, from: data)) ?? [:]
    }

    private static func key(_ directory: URL) -> String { directory.resolvingSymlinksInPath().standardizedFileURL.path }
}
