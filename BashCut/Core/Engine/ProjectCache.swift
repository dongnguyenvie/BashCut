import Foundation

/// Everything BashCut can make again for a project lives under one folder, `.bashcut/cache/`, apart from the
/// project's own data in `.bashcut/` (#101). One folder is listed in `.bashcut/.gitignore`, excluded from Time
/// Machine, and cleared or measured as a whole. Before this, each cache had its own folder in `.bashcut/`;
/// `prepare` moves those in when a project is opened.
public enum ProjectCache {
    public static let folder = ".bashcut/cache"

    public enum Kind: String, CaseIterable, Sendable {
        /// Preview proxies, `<media id>.mov` or `.mp4`.
        case proxies
        /// Waveform peaks for the timeline.
        case waveforms
        /// PCM rendered for speed ramps.
        case rampAudio = "ramp-audio"
        /// One-frame movies the engine reads still images through.
        case stills
        /// Scratch files of loudness-normalized exports.
        case loudness
        /// Viewer frames attached for agents.
        case agentContext = "agent-context"
        /// Measured records of source files (`media.analyze`), `<content key>.json`.
        case analysis

        /// Where this cache was before `.bashcut/cache/`; waveforms were already there, and analysis is newer.
        var legacyPath: String? { [.waveforms, .analysis].contains(self) ? nil : ".bashcut/" + rawValue }
    }

    public static func root(projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(folder, isDirectory: true)
    }

    /// The folder holding `kind` for the project at `projectRoot`.
    public static func url(_ kind: Kind, projectRoot: URL) -> URL {
        root(projectRoot: projectRoot).appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    /// Moves caches left in their old `.bashcut/<name>` folders into `.bashcut/cache/` and marks the cache folder
    /// as excluded from backups. Moves are renames on the same volume, so this is quick even for gigabytes of
    /// proxies; a file already in the new place wins, and failures only mean a cache is made again.
    /// Returns the names of the folders that were moved.
    @discardableResult
    public static func prepare(projectRoot: URL) -> [String] {
        let manager = FileManager.default
        let bashcut = projectRoot.appendingPathComponent(".bashcut", isDirectory: true)
        guard manager.fileExists(atPath: bashcut.path) else { return [] }
        var cacheRoot = root(projectRoot: projectRoot)
        var moved: [String] = []
        for kind in Kind.allCases {
            guard let legacyPath = kind.legacyPath else { continue }
            let legacy = projectRoot.appendingPathComponent(legacyPath, isDirectory: true)
            guard manager.fileExists(atPath: legacy.path) else { continue }
            try? manager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            let destination = url(kind, projectRoot: projectRoot)
            if (try? manager.moveItem(at: legacy, to: destination)) == nil {
                // The new folder already exists: keep its files, take the rest, drop the old folder.
                for name in (try? manager.contentsOfDirectory(atPath: legacy.path)) ?? [] {
                    let target = destination.appendingPathComponent(name)
                    if !manager.fileExists(atPath: target.path) {
                        try? manager.moveItem(at: legacy.appendingPathComponent(name), to: target)
                    }
                }
                try? manager.removeItem(at: legacy)
            }
            moved.append(kind.rawValue)
        }
        if manager.fileExists(atPath: cacheRoot.path) {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? cacheRoot.setResourceValues(values)
        }
        return moved
    }
}
