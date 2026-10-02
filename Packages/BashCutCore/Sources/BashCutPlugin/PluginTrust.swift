import BashCutProject
import CryptoKit
import Foundation

/// SHA-256 of a plugin's manifest and entrypoint, pinned when the user approves the plugin.
public struct PluginFingerprint: Codable, Sendable, Equatable {
    public let manifestSHA256: String
    public let entrypointSHA256: String

    public init(manifestSHA256: String, entrypointSHA256: String) {
        self.manifestSHA256 = manifestSHA256
        self.entrypointSHA256 = entrypointSHA256
    }

    public init(plugin: InstalledPlugin) throws {
        let manifest = try Data(contentsOf: plugin.directory.appendingPathComponent("plugin.json"))
        let entrypoint = try Data(contentsOf: plugin.entrypointURL())
        self.init(manifestSHA256: Self.hex(manifest), entrypointSHA256: Self.hex(entrypoint))
    }

    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// What the user decided about one plugin.
public struct PluginGrant: Codable, Sendable, Equatable {
    public var fingerprint: PluginFingerprint
    public var version: String
    public var approvedAt: Date
    public var enabled: Bool
    public var hooksEnabled: Bool

    public init(fingerprint: PluginFingerprint, version: String, approvedAt: Date = Date(), enabled: Bool = true,
                hooksEnabled: Bool = true) {
        self.fingerprint = fingerprint
        self.version = version
        self.approvedAt = approvedAt
        self.enabled = enabled
        self.hooksEnabled = hooksEnabled
    }
}

/// Whether a discovered plugin may run, and why not.
public enum PluginAvailability: Sendable, Equatable {
    case ready
    /// The user turned it off.
    case disabled
    /// Never approved (for example a plugin that came with a project).
    case untrusted
    /// Its manifest or entrypoint changed since the user approved it.
    case changed
    /// Its API window does not include this BashCut.
    case outdated(String)

    public var name: String {
        switch self {
        case .ready: "ready"
        case .disabled: "disabled"
        case .untrusted: "untrusted"
        case .changed: "changed"
        case .outdated: "outdated"
        }
    }

    public var detail: String {
        switch self {
        case .ready: "Ready"
        case .disabled: "Turned off in Plugins"
        case .untrusted: "Not approved yet: review it in Plugins and choose Trust"
        case .changed: "Changed since it was approved: review it in Plugins and choose Trust again"
        case .outdated(let reason): reason
        }
    }
}

/// The user's plugin decisions and user-scope option values, in one 0600 JSON file. Bundled plugins are
/// trusted without a pin; every other plugin runs only after the user approves its exact files.
public final class PluginTrustStore: @unchecked Sendable {
    struct Contents: Codable {
        var grants: [String: PluginGrant] = [:]
        var options: [String: [String: JSONValue]] = [:]
    }

    public let url: URL
    /// Plugins under these folders (the app bundle) are trusted without approval.
    public let trustedRoots: [URL]
    private let lock = NSLock()
    private var contents: Contents
    /// Fingerprints by plugin folder, reused while both files keep their size and modification date.
    private var fingerprints: [String: (stamp: [Date?], sizes: [Int], value: PluginFingerprint)] = [:]

    public init(url: URL, trustedRoots: [URL] = []) {
        self.url = url
        self.trustedRoots = trustedRoots.map(\.standardizedFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        contents = (try? decoder.decode(Contents.self, from: Data(contentsOf: url))) ?? Contents()
    }

    public static var standard: PluginTrustStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return PluginTrustStore(
            url: support.appendingPathComponent("BashCut/plugin-trust.json"),
            trustedRoots: Bundle.main.builtInPlugInsURL.map { [$0] } ?? [])
    }

    public func grant(for pluginID: String) -> PluginGrant? { locked { contents.grants[pluginID] } }

    public func isBundled(_ plugin: InstalledPlugin) -> Bool {
        let path = plugin.directory.standardizedFileURL.path
        return trustedRoots.contains { path.hasPrefix($0.path + "/") }
    }

    public func availability(of plugin: InstalledPlugin) -> PluginAvailability {
        if let reason = plugin.manifest.incompatibility { return .outdated(reason) }
        let grant = grant(for: plugin.id)
        if let grant, !grant.enabled { return .disabled }
        if isBundled(plugin) { return .ready }
        guard let grant, !grant.fingerprint.manifestSHA256.isEmpty else { return .untrusted }
        guard let current = try? fingerprint(plugin), current == grant.fingerprint else { return .changed }
        return .ready
    }

    /// The plugin's fingerprint, hashed again only when one of its files changed size or date.
    func fingerprint(_ plugin: InstalledPlugin) throws -> PluginFingerprint {
        let files = [plugin.directory.appendingPathComponent("plugin.json"), try plugin.entrypointURL()]
        let attributes = files.map { try? FileManager.default.attributesOfItem(atPath: $0.path) }
        let stamp = attributes.map { $0?[.modificationDate] as? Date }
        let sizes = attributes.map { ($0?[.size] as? NSNumber)?.intValue ?? -1 }
        let key = plugin.directory.standardizedFileURL.path
        if let cached = locked({ fingerprints[key] }), cached.stamp == stamp, cached.sizes == sizes {
            return cached.value
        }
        let value = try PluginFingerprint(plugin: plugin)
        locked { fingerprints[key] = (stamp, sizes, value) }
        return value
    }

    /// Pins the plugin's current files. Only the user may call this (Plugins sheet, install approval).
    public func trust(_ plugin: InstalledPlugin) throws {
        let fingerprint = try PluginFingerprint(plugin: plugin)
        locked { fingerprints[plugin.directory.standardizedFileURL.path] = nil }
        try update { contents in
            var grant = contents.grants[plugin.id]
                ?? PluginGrant(fingerprint: fingerprint, version: plugin.manifest.version)
            grant.fingerprint = fingerprint
            grant.version = plugin.manifest.version
            grant.approvedAt = Date()
            contents.grants[plugin.id] = grant
        }
    }

    public func revoke(_ pluginID: String) throws {
        try update { $0.grants[pluginID] = nil }
    }

    /// Turns a plugin or its hooks on or off. A bundled plugin without a grant gets one so the switch persists.
    public func setEnabled(_ plugin: InstalledPlugin, enabled: Bool? = nil, hooks: Bool? = nil) throws {
        let fingerprint = (try? PluginFingerprint(plugin: plugin))
            ?? PluginFingerprint(manifestSHA256: "", entrypointSHA256: "")
        try update { contents in
            var grant = contents.grants[plugin.id] ?? PluginGrant(
                fingerprint: self.isBundled(plugin) ? fingerprint : PluginFingerprint(manifestSHA256: "", entrypointSHA256: ""),
                version: plugin.manifest.version)
            if let enabled { grant.enabled = enabled }
            if let hooks { grant.hooksEnabled = hooks }
            contents.grants[plugin.id] = grant
        }
    }

    public func hooksEnabled(_ pluginID: String) -> Bool { grant(for: pluginID)?.hooksEnabled ?? true }

    public func userOptions(_ pluginID: String) -> [String: JSONValue] { locked { contents.options[pluginID] ?? [:] } }

    public func setUserOption(_ pluginID: String, key: String, value: JSONValue?) throws {
        try update { contents in
            var values = contents.options[pluginID] ?? [:]
            values[key] = value
            contents.options[pluginID] = values.isEmpty ? nil : values
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func update(_ change: (inout Contents) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        var next = contents
        change(&next)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(next)
        let manager = FileManager.default
        try manager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        contents = next
    }
}
