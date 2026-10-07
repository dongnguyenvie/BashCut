import CryptoKit
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
        /// What was said in source files (`media.transcribe`), `<content key>.json`.
        case transcripts
        /// Source frames, contact sheets and filmstrips for agents (`media.frames`, `media.frame`, `media.strip`).
        case mediaStills = "media-stills"
        /// Capture facts of source files (`media.inventory`), `<content key>.json`.
        case inventory
        /// Contact sheets of the composed timeline (`timeline.sheet`), one folder per revision and request.
        case timelineSheets = "timeline-sheets"

        /// Where this cache was before `.bashcut/cache/`; waveforms were already there, and analysis is newer.
        var legacyPath: String? {
            [.waveforms, .analysis, .transcripts, .mediaStills, .inventory, .timelineSheets].contains(self)
                ? nil : ".bashcut/" + rawValue
        }
    }

    public static func root(projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(folder, isDirectory: true)
    }

    /// The folder holding `kind` for the project at `projectRoot`.
    public static func url(_ kind: Kind, projectRoot: URL) -> URL {
        root(projectRoot: projectRoot).appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    /// A content key for a file: SHA-256 of `namespace`, the size and the first and last mebibyte. A moved or
    /// renamed file keeps its key; an edited one gets a new key. It reads at most two mebibytes.
    /// Keys already read are remembered for the file's path, size and modification date, so asking again (as
    /// `context.get` does for every media) reads nothing.
    public static func contentKey(for url: URL, namespace: String) throws -> String {
        // Not `URL.resourceValues`: a URL keeps the values it read once.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let stamp = "\((attributes[.size] as? NSNumber)?.int64Value ?? -1)|\(modified)|\(attributes[.systemFileNumber] ?? 0)"
        let memo = namespace + "|" + url.standardizedFileURL.path
        if let known = KeyMemo.shared.key(memo, stamp: stamp) { return known }
        let key = try readContentKey(for: url, namespace: namespace)
        KeyMemo.shared.remember(memo, stamp: stamp, key: key)
        return key
    }

    private static func readContentKey(for url: URL, namespace: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        var hasher = SHA256()
        hasher.update(data: Data("\(namespace)|\(size)|".utf8))
        let chunk = UInt64(1 << 20)
        try handle.seek(toOffset: 0)
        hasher.update(data: try handle.read(upToCount: Int(chunk)) ?? Data())
        if size > chunk {
            try handle.seek(toOffset: max(chunk, size - chunk))
            hasher.update(data: try handle.read(upToCount: Int(chunk)) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The JSON record `<key>.json` of `kind`, or nil when it is missing or does not decode.
    public static func record<Record: Decodable>(_ type: Record.Type, _ kind: Kind, key: String, projectRoot: URL) -> Record? {
        let url = url(kind, projectRoot: projectRoot).appendingPathComponent(key + ".json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Writes `record` as `<key>.json` of `kind`.
    public static func store<Record: Encodable>(_ record: Record, _ kind: Kind, key: String, projectRoot: URL) throws {
        let folder = url(kind, projectRoot: projectRoot)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: folder.appendingPathComponent(key + ".json"), options: .atomic)
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

/// Content keys by path, valid while the file's size and modification date stay the same.
private final class KeyMemo: @unchecked Sendable {
    static let shared = KeyMemo()
    private let lock = NSLock()
    private var keys: [String: (stamp: String, key: String)] = [:]

    func key(_ memo: String, stamp: String) -> String? {
        lock.withLock { keys[memo].flatMap { $0.stamp == stamp ? $0.key : nil } }
    }

    func remember(_ memo: String, stamp: String, key: String) {
        lock.withLock {
            if keys.count > 10_000 { keys.removeAll() }
            keys[memo] = (stamp, key)
        }
    }
}
