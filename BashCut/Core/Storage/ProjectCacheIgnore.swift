import Foundation

/// `.bashcut/.gitignore`: the folders under `.bashcut/` that BashCut can make again, so a project folder kept in git
/// (or synced by a tool that reads `.gitignore`) leaves gigabytes of proxies and caches out (#101). Written only
/// when missing, so a user's own edits stay.
public enum ProjectCacheIgnore {
    public static let fileName = ".gitignore"

    /// Folders under `.bashcut/` that are rebuilt on demand.
    public static let regenerable = ["proxies/", "cache/", "ramp-audio/", "stills/", "loudness/", "agent-context/"]

    public static var contents: String {
        """
        # Written by BashCut. Everything listed here is made again when needed (preview proxies, waveforms,
        # speed-ramp audio, still-image movies, loudness scratch files, viewer frames for agents).
        # BashCut writes this file only when it is missing; edit it freely.
        \(regenerable.joined(separator: "\n"))

        """
    }

    /// Writes `<cacheFolder>/.gitignore` when there is none; errors are ignored (the project still saves).
    public static func ensure(in cacheFolder: URL) {
        let url = cacheFolder.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? Data(contents.utf8).write(to: url, options: .withoutOverwriting)
    }
}
