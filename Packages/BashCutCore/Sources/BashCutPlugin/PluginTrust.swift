import BashCutProject
import CryptoKit
import Foundation

/// SHA-256 of a plugin's manifest, entrypoint and every other file in its folder, pinned when the user approves
/// the plugin. Any change (a script the entrypoint runs, a bundled helper) needs approval again.
public struct PluginFingerprint: Codable, Sendable, Equatable {
    public let manifestSHA256: String
    public let entrypointSHA256: String
    /// Digest of every file's relative path, mode and contents; nil in grants made before it existed.
    public var treeSHA256: String?

    public init(manifestSHA256: String, entrypointSHA256: String, treeSHA256: String? = nil) {
        self.manifestSHA256 = manifestSHA256
        self.entrypointSHA256 = entrypointSHA256
        self.treeSHA256 = treeSHA256
    }

    public init(plugin: InstalledPlugin) throws {
        let manifest = try Data(contentsOf: plugin.directory.appendingPathComponent("plugin.json"))
        let entrypoint = try Data(contentsOf: plugin.entrypointURL())
        self.init(
            manifestSHA256: Self.hex(manifest), entrypointSHA256: Self.hex(entrypoint),
            treeSHA256: try Self.tree(plugin.directory))
    }

    /// Same files as `other`, treating a grant without a tree digest as matching on manifest and entrypoint.
    func matches(_ other: PluginFingerprint) -> Bool {
        manifestSHA256 == other.manifestSHA256 && entrypointSHA256 == other.entrypointSHA256
            && (other.treeSHA256 == nil || treeSHA256 == other.treeSHA256)
    }

    /// Files under the folder, sorted: `path`, executable bit and SHA-256 (or a link's target). Hidden files,
    /// `__pycache__` and `.pyc` files are skipped; they change on their own.
    static func tree(_ folder: URL) throws -> String {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { throw PluginError.invalid("Cannot read the plugin folder") }
        var lines: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true, url.lastPathComponent == "__pycache__" {
                enumerator.skipDescendants()
                continue
            }
            let relative = String(url.standardizedFileURL.path.dropFirst(root.path.count + 1))
            if values.isSymbolicLink == true {
                let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? ""
                lines.append("\(relative)\0link\0\(target)")
            } else if values.isRegularFile == true, url.pathExtension != "pyc" {
                let executable = FileManager.default.isExecutableFile(atPath: url.path) ? "x" : "-"
                lines.append("\(relative)\0\(executable)\0\(hex(try Data(contentsOf: url)))")
            }
        }
        return hex(Data(lines.sorted().joined(separator: "\n").utf8))
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
    /// Development builds: a plugin folder that is a symbolic link (`dev-link.sh`) is checked on its manifest and
    /// entrypoint only, so its other files can change while it is being written.
    public var relaxesLinkedPlugins = false
    private let lock = NSLock()
    private var contents: Contents
    /// Fingerprints by plugin folder, reused while both files keep their size and modification date.
    private var fingerprints: [String: (stamp: [String], value: PluginFingerprint)] = [:]

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
        guard let current = try? fingerprint(plugin) else { return .changed }
        let linked = relaxesLinkedPlugins
            && (try? plugin.directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        if linked {
            return current.manifestSHA256 == grant.fingerprint.manifestSHA256
                && current.entrypointSHA256 == grant.fingerprint.entrypointSHA256 ? .ready : .changed
        }
        guard current.matches(grant.fingerprint) else { return .changed }
        if grant.fingerprint.treeSHA256 == nil {
            // An older grant: pin the folder as it is now, since manifest and entrypoint still match.
            try? update { $0.grants[plugin.id]?.fingerprint = current }
        }
        return .ready
    }

    /// The plugin's fingerprint, hashed again only when a file in its folder was added, removed or changed size or
    /// date.
    func fingerprint(_ plugin: InstalledPlugin) throws -> PluginFingerprint {
        let stamp = Self.stamp(plugin.directory)
        let key = plugin.directory.standardizedFileURL.path
        if let cached = locked({ fingerprints[key] }), cached.stamp == stamp { return cached.value }
        let value = try PluginFingerprint(plugin: plugin)
        locked { fingerprints[key] = (stamp, value) }
        return value
    }

    private static func stamp(_ folder: URL) -> [String] {
        let root = folder.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var entries: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            entries.append("\(url.path)|\(values?.fileSize ?? -1)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        return entries.sorted()
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
