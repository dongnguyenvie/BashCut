import Foundation

/// The remote plugin catalog: a static `registry.json` (by default in `dongnguyenvie/bashcut-plugins`) listing
/// plugins and the archives of their recent versions. There is no server; archives are GitHub Release assets.
public struct PluginRegistryDocument: Codable, Sendable, Equatable {
    public static let supportedSchema = 1

    public let schemaVersion: Int
    public let publishers: [String: PluginRegistryPublisher]
    public let plugins: [PluginRegistryEntry]

    public init(schemaVersion: Int = 1, publishers: [String: PluginRegistryPublisher] = [:], plugins: [PluginRegistryEntry]) {
        self.schemaVersion = schemaVersion
        self.publishers = publishers
        self.plugins = plugins
    }

    public func entry(_ id: String) -> PluginRegistryEntry? { plugins.first { $0.id == id } }

    /// Keys the registry lists for a third-party publisher; none for `bashcut`, whose keys only the app carries.
    public func keys(for publisher: String?) -> [String] {
        guard let publisher, publisher != "bashcut" else { return [] }
        return publishers[publisher]?.keys ?? []
    }
}

public struct PluginRegistryPublisher: Codable, Sendable, Equatable {
    public let name: LocalizedText
    /// ed25519 public keys (`ed25519:BASE64`) that sign this publisher's archives. Keys listed for `bashcut` here
    /// are ignored: first-party keys are compiled into the app (`PluginSignature.firstPartyKeys`).
    public let keys: [String]?
    public let verified: Bool?

    public init(name: LocalizedText, keys: [String]? = nil, verified: Bool? = nil) {
        self.name = name
        self.keys = keys
        self.verified = verified
    }
}

public struct PluginRegistryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: LocalizedText
    public let summary: LocalizedText?
    public let publisher: String?
    public let category: String?
    public let homepage: String?
    /// Who wrote the plugin (from its manifest); `publisher` is who signs and ships it.
    public let author: PluginAuthor?
    public let capabilities: [String]?
    public let actions: [String]?
    public let hooks: [String]?
    public let versions: [PluginRegistryVersion]

    public init(
        id: String, name: LocalizedText, summary: LocalizedText? = nil, publisher: String? = nil,
        category: String? = nil, homepage: String? = nil, capabilities: [String]? = nil, actions: [String]? = nil,
        hooks: [String]? = nil, author: PluginAuthor? = nil, versions: [PluginRegistryVersion]
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.publisher = publisher
        self.category = category
        self.homepage = homepage
        self.author = author
        self.capabilities = capabilities
        self.actions = actions
        self.hooks = hooks
        self.versions = versions
    }

    /// Newest version this app can install, or why none can be.
    public func resolve(appVersion: String, platform: String = PluginPlatform.current) -> Result<PluginRegistryVersion, PluginError> {
        let app = SemanticVersion(appVersion)
        let published = versions.filter { $0.yanked == nil }
        guard !published.isEmpty else { return .failure(.invalid("Every version was withdrawn")) }
        let candidates = published.filter { $0.platforms?.contains(where: { PluginPlatform.matches($0, platform) }) ?? true }
        guard !candidates.isEmpty else { return .failure(.invalid("No build for this Mac (\(platform))")) }
        let apiFits = candidates.filter { version in
            let needed = version.minApiVersion ?? version.apiVersion
            return needed <= PluginAPI.current && version.apiVersion >= PluginAPI.minimum
        }
        guard !apiFits.isEmpty else { return .failure(.invalid("Needs a newer BashCut (plugin API)")) }
        // Development builds have no real version; they accept every minAppVersion.
        let appFits = apiFits.filter { version in
            guard let app, let minimum = version.minAppVersion.flatMap(SemanticVersion.init) else { return true }
            return minimum <= app
        }
        guard let best = appFits.max(by: { SemanticVersion($0.version) ?? .zero < SemanticVersion($1.version) ?? .zero })
        else { return .failure(.invalid("Needs a newer BashCut")) }
        return .success(best)
    }

    /// The registry's record of an installed version, to tell whether it was yanked.
    public func version(_ version: String) -> PluginRegistryVersion? { versions.first { $0.version == version } }

    /// True when the entry matches a search text (name, summary, id, category, capability or author).
    public func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        let fields: [String] = [id, category ?? "", author?.name ?? ""]
        let haystack: [String] = fields + (capabilities ?? []) + Array(name.values.values)
            + Array((summary?.values ?? [:]).values)
        return haystack.contains { $0.lowercased().contains(needle) }
    }
}

public struct PluginRegistryVersion: Codable, Sendable, Equatable {
    public let version: String
    public let apiVersion: Int
    public let minApiVersion: Int?
    public let minAppVersion: String?
    public let platforms: [String]?
    public let url: String
    public let sha256: String
    public let signature: String?
    public let size: Int?
    /// Models or tools the plugin's install recipes download, shown before approval.
    public let downloadBytes: Int?
    public let releasedAt: String?
    /// Why this version was withdrawn (a serious bug, a bad archive). Yanked versions are never offered; users who
    /// have one are told to update.
    public let yanked: String?

    public init(
        version: String, apiVersion: Int, minApiVersion: Int? = nil, minAppVersion: String? = nil,
        platforms: [String]? = nil, url: String, sha256: String, signature: String? = nil, size: Int? = nil,
        downloadBytes: Int? = nil, releasedAt: String? = nil, yanked: String? = nil
    ) {
        self.version = version
        self.apiVersion = apiVersion
        self.minApiVersion = minApiVersion
        self.minAppVersion = minAppVersion
        self.platforms = platforms
        self.url = url
        self.sha256 = sha256
        self.signature = signature
        self.size = size
        self.downloadBytes = downloadBytes
        self.releasedAt = releasedAt
        self.yanked = yanked
    }
}

public enum PluginPlatform {
    public static var current: String {
        #if arch(arm64)
            "macos-arm64"
        #else
            "macos-x86_64"
        #endif
    }

    static func matches(_ listed: String, _ platform: String) -> Bool { listed == platform || listed == "macos-universal" }
}

/// `MAJOR.MINOR.PATCH[-pre]`, compared numerically; a prerelease sorts before its release.
public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public static let zero = SemanticVersion(numbers: [0, 0, 0], prerelease: nil)
    let numbers: [Int]
    let prerelease: String?

    init(numbers: [Int], prerelease: String?) {
        self.numbers = numbers
        self.prerelease = prerelease
    }

    public init?(_ text: String) {
        let main = text.split(separator: "+", maxSplits: 1).first.map(String.init) ?? text
        let parts = main.split(separator: "-", maxSplits: 1).map(String.init)
        let numbers = parts.first?.split(separator: ".").map { Int($0) } ?? []
        guard (1...3).contains(numbers.count), numbers.allSatisfy({ $0 != nil }) else { return nil }
        self.numbers = numbers.compactMap { $0 } + Array(repeating: 0, count: 3 - numbers.count)
        prerelease = parts.count > 1 ? parts[1] : nil
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, _): return false
        case (_, nil): return true
        case (let left?, let right?): return left < right
        }
    }

    public var description: String { numbers.map(String.init).joined(separator: ".") + (prerelease.map { "-" + $0 } ?? "") }
}

/// Fetches and caches the registry. A fresh copy is used for `maximumAge`; after that the server is asked with the
/// cached ETag. When the network or the file fails, the last good copy is returned with the error.
public actor PluginRegistryClient {
    public struct Snapshot: Sendable {
        public let document: PluginRegistryDocument
        public let fetchedAt: Date
        /// Set when this is a cached copy because the refresh failed.
        public let staleReason: String?
    }

    public static let defaultURL = URL(
        string: "https://raw.githubusercontent.com/dongnguyenvie/bashcut-plugins/main/registry.json")!

    public nonisolated let url: URL
    public nonisolated let cacheDirectory: URL
    public nonisolated let maximumAge: TimeInterval
    private let session: URLSession

    public init(url: URL = defaultURL, cacheDirectory: URL, maximumAge: TimeInterval = 300, session: URLSession = .shared) {
        self.url = url
        self.cacheDirectory = cacheDirectory
        self.maximumAge = maximumAge
        self.session = session
    }

    private var cacheURL: URL { cacheDirectory.appendingPathComponent("registry.json") }
    private var metaURL: URL { cacheDirectory.appendingPathComponent("registry.meta.json") }

    private struct Meta: Codable {
        let url: String
        let etag: String?
        let fetchedAt: Date
    }

    public func snapshot(force: Bool = false) async throws -> Snapshot {
        let cached = loadCache()
        if !force, let cached, Date().timeIntervalSince(cached.meta.fetchedAt) < maximumAge {
            return Snapshot(document: cached.document, fetchedAt: cached.meta.fetchedAt, staleReason: nil)
        }
        do {
            var request = URLRequest(url: Self.requestURL(url, force: force), cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 20)
            // A manual refresh skips the CDN copy (raw.githubusercontent.com keeps one for 5 minutes) and the ETag.
            if !force, let etag = cached?.meta.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 304, let cached {
                try save(cached.data, etag: cached.meta.etag)
                return Snapshot(document: cached.document, fetchedAt: Date(), staleReason: nil)
            }
            guard (200..<300).contains(status) else { throw PluginError.invalid("Registry answered HTTP \(status)") }
            guard data.count <= 8 * 1024 * 1024 else { throw PluginError.invalid("Registry is too large") }
            let document = try Self.decode(data)
            try save(data, etag: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag"))
            return Snapshot(document: document, fetchedAt: Date(), staleReason: nil)
        } catch {
            guard let cached else { throw error }
            return Snapshot(document: cached.document, fetchedAt: cached.meta.fetchedAt, staleReason: error.localizedDescription)
        }
    }

    /// Moves a registry cache left in `legacy` (Application Support before #101) to `destination`, once: files the
    /// destination already has win, and the legacy folder is removed. Errors are ignored; the cache is refetched.
    public nonisolated static func migrateCache(from legacy: URL, to destination: URL) {
        let manager = FileManager.default
        guard legacy.standardizedFileURL != destination.standardizedFileURL, manager.fileExists(atPath: legacy.path)
        else { return }
        try? manager.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in ["registry.json", "registry.meta.json"] {
            let target = destination.appendingPathComponent(name)
            if !manager.fileExists(atPath: target.path) {
                try? manager.moveItem(at: legacy.appendingPathComponent(name), to: target)
            }
        }
        try? manager.removeItem(at: legacy)
    }

    /// The last good copy, without touching the network; nil when there is none for this URL.
    public func cached() -> Snapshot? {
        loadCache().map { Snapshot(document: $0.document, fetchedAt: $0.meta.fetchedAt, staleReason: nil) }
    }

    /// The URL to fetch: with `force`, an extra `t` query item makes the CDN treat it as a new resource.
    public static func requestURL(_ url: URL, force: Bool) -> URL {
        guard force, !url.isFileURL, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = (components.queryItems ?? [])
            + [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
        return components.url ?? url
    }

    public static func decode(_ data: Data) throws -> PluginRegistryDocument {
        struct Header: Decodable { let schemaVersion: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
            throw PluginError.invalid("The plugin registry is not valid JSON")
        }
        guard header.schemaVersion <= PluginRegistryDocument.supportedSchema else {
            throw PluginError.invalid("Update BashCut to browse plugins (registry schema \(header.schemaVersion))")
        }
        do { return try JSONDecoder().decode(PluginRegistryDocument.self, from: data) } catch {
            throw PluginError.invalid("The plugin registry is malformed: \(error.localizedDescription)")
        }
    }

    private func loadCache() -> (document: PluginRegistryDocument, data: Data, meta: Meta)? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: cacheURL), let metaData = try? Data(contentsOf: metaURL),
            let meta = try? decoder.decode(Meta.self, from: metaData), meta.url == url.absoluteString,
            let document = try? Self.decode(data)
        else { return nil }
        return (document, data, meta)
    }

    private func save(_ data: Data, etag: String?) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Meta(url: url.absoluteString, etag: etag, fetchedAt: Date())).write(to: metaURL, options: .atomic)
    }
}
