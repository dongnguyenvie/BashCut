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
        let tree = try Self.tree(plugin.directory)
        let manifest = try Data(contentsOf: plugin.directory.appendingPathComponent("plugin.json"))
        let entrypoint = try Data(contentsOf: plugin.entrypointURL())
        self.init(
            manifestSHA256: Self.hex(manifest), entrypointSHA256: Self.hex(entrypoint),
            treeSHA256: tree)
    }

    /// Same files as `other`, treating a grant without a tree digest as matching on manifest and entrypoint.
    func matches(_ other: PluginFingerprint) -> Bool {
        manifestSHA256 == other.manifestSHA256 && entrypointSHA256 == other.entrypointSHA256
            && (other.treeSHA256 == nil || treeSHA256 == other.treeSHA256)
    }

    /// Hash every file, including hidden files and Python bytecode. Only Finder metadata is ignored.
    static func tree(_ folder: URL) throws -> String { try PluginTree.digest(folder) }

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
    /// A plugin it `requires` is missing, out of range or not ready (API 8).
    case needsPlugin(String)

    public var name: String {
        switch self {
        case .ready: "ready"
        case .disabled: "disabled"
        case .untrusted: "untrusted"
        case .changed: "changed"
        case .outdated: "outdated"
        case .needsPlugin: "needs-plugin"
        }
    }

    public var detail: String {
        switch self {
        case .ready: "Ready"
        case .disabled: "Turned off in Plugins"
        case .untrusted: "Not approved yet: review it in Plugins and choose Trust"
        case .changed: "Changed since it was approved: review it in Plugins and choose Trust again"
        case .outdated(let reason): reason
        case .needsPlugin(let reason): reason
        }
    }
}

/// The user's plugin decisions and user-scope option values, in one 0600 JSON file. Bundled plugins are
/// trusted without a pin; every other plugin runs only after the user approves its exact files.
/// Keys include the canonical installation root. Legacy ID-only grants cannot establish which copy was
/// approved, so they are intentionally ignored until the user trusts a particular installation again.
public final class PluginTrustStore: @unchecked Sendable {
    struct Contents: Codable {
        var grants: [String: PluginGrant] = [:]
        var options: [String: [String: JSONValue]] = [:]
    }

    public let url: URL
    /// Plugins under these folders (the app bundle) are trusted without approval.
    public let trustedRoots: [URL]
    private let trustedPaths: [String]
    /// Development builds: a plugin folder that is a symbolic link (`dev-link.sh`) is checked on its manifest and
    /// entrypoint only, so its other files can change while it is being written.
    public var relaxesLinkedPlugins = false
    private let lock = NSLock()
    private var contents: Contents
    /// Fingerprints by plugin folder, reused while the folder's stamp (`PluginTree.stamp`) is unchanged. `files`
    /// are plugin.json and the entrypoint when it was taken: `knownAvailability` trusts the last result only while
    /// they are unchanged.
    private var fingerprints: [String: (stamp: String, files: [PluginFileSignature?], value: PluginFingerprint)] = [:]

    public init(url: URL, trustedRoots: [URL] = []) {
        self.url = url
        self.trustedRoots = trustedRoots.map(\.standardizedFileURL)
        trustedPaths = self.trustedRoots.map { $0.path + "/" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        contents = (try? decoder.decode(Contents.self, from: Data(contentsOf: url))) ?? Contents()
    }

    public static var standard: PluginTrustStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return PluginTrustStore(
            url: support.appendingPathComponent("BashCut/plugin-trust.json"),
            trustedRoots: PluginFolders.bundled.map { [$0] } ?? [])
    }

    public func grant(for plugin: InstalledPlugin) -> PluginGrant? { locked { contents.grants[plugin.installationID] } }

    public func isBundled(_ plugin: InstalledPlugin) -> Bool {
        trustedPaths.contains { plugin.directoryPath.hasPrefix($0) }
    }

    /// Repair may execute recipes only from the approved bundle. Check the full pin independently of enabled
    /// state: a disabled plugin can also have changed files. Initial setup remains part of install approval.
    public func validateSetup(of plugin: InstalledPlugin) throws {
        guard !isBundled(plugin), let approved = grant(for: plugin),
            !approved.fingerprint.manifestSHA256.isEmpty else { return }
        guard (try? PluginFingerprint(plugin: plugin)) == approved.fingerprint else {
            throw PluginError.invalid("Plugin files changed; review and trust them before running setup")
        }
    }

    /// Whether the plugin may run, checking every file in its folder. Call it right before running the plugin.
    public func availability(of plugin: InstalledPlugin) -> PluginAvailability {
        availability(of: plugin, pinning: true) { try? self.fingerprint(plugin) } ?? .changed
    }

    /// The same answer without walking the plugin's folder, for listing many plugins (#103): the result of the last
    /// file check while plugin.json and the entrypoint are unchanged since. Nil when the files were not checked
    /// yet in this session or those two changed; then `availability(of:)` has to run. Running a plugin always
    /// checks every file again, so a stale `.ready` here cannot run changed code.
    public func knownAvailability(of plugin: InstalledPlugin) -> PluginAvailability? {
        availability(of: plugin, pinning: false) {
            let key = plugin.directoryPath
            guard let cached = self.locked({ self.fingerprints[key] }),
                cached.files == PluginFileSignature.manifestAndEntrypoint(of: plugin)
            else { return nil }
            return cached.value
        }
    }

    /// `current` is the folder's fingerprint, or nil when it is unknown (`knownAvailability`) or cannot be read.
    private func availability(
        of plugin: InstalledPlugin, pinning: Bool, current: () -> PluginFingerprint?
    ) -> PluginAvailability? {
        if let reason = plugin.manifest.incompatibility { return .outdated(reason) }
        let grant = grant(for: plugin)
        if let grant, !grant.enabled { return .disabled }
        if isBundled(plugin) { return .ready }
        guard let grant, !grant.fingerprint.manifestSHA256.isEmpty else { return .untrusted }
        guard let current = current() else { return nil }
        let linked = relaxesLinkedPlugins
            && (try? plugin.directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        if linked {
            return current.manifestSHA256 == grant.fingerprint.manifestSHA256
                && current.entrypointSHA256 == grant.fingerprint.entrypointSHA256 ? .ready : .changed
        }
        guard current.matches(grant.fingerprint) else { return .changed }
        if pinning, grant.fingerprint.treeSHA256 == nil {
            // An older grant: pin the folder as it is now, since manifest and entrypoint still match.
            try? update { $0.grants[plugin.installationID]?.fingerprint = current }
        }
        return .ready
    }

    /// The plugin's fingerprint, hashed again only when a file in its folder was added, removed or changed size or
    /// date, inode, mode or ctime.
    func fingerprint(_ plugin: InstalledPlugin) throws -> PluginFingerprint {
        // Taken before the walk, so a write during it leaves them stale and the next listing checks again.
        let files = PluginFileSignature.manifestAndEntrypoint(of: plugin)
        let stamp = try PluginTree.stamp(plugin.directory)
        let key = plugin.directoryPath
        if let cached = locked({ fingerprints[key] }), cached.stamp == stamp {
            locked { fingerprints[key]?.files = files }
            return cached.value
        }
        let value = try PluginFingerprint(plugin: plugin)
        locked { fingerprints[key] = (stamp, files, value) }
        return value
    }

    /// Credentials belong to these exact plugin files and installation. Re-trusting changed code never
    /// transfers the previous version's keys; the user must enter a key for the new fingerprint.
    public func credentialIdentity(for plugin: InstalledPlugin) throws -> String {
        let current = try fingerprint(plugin)
        let digest = [current.manifestSHA256, current.entrypointSHA256, current.treeSHA256 ?? ""].joined(separator: ":")
        return plugin.installationID + "@" + PluginFingerprint.hex(Data(digest.utf8))
    }

    /// Pins the plugin's current files. Only the user may call this (Plugins sheet, install approval).
    public func trust(_ plugin: InstalledPlugin) throws {
        // Hashed from scratch, then kept, so listing the plugin right after shows it ready without another walk.
        locked { fingerprints[plugin.directoryPath] = nil }
        let fingerprint = try self.fingerprint(plugin)
        try update { contents in
            var grant = contents.grants[plugin.installationID]
                ?? PluginGrant(fingerprint: fingerprint, version: plugin.manifest.version)
            grant.fingerprint = fingerprint
            grant.version = plugin.manifest.version
            grant.approvedAt = Date()
            contents.grants[plugin.installationID] = grant
        }
    }

    public func revoke(_ plugin: InstalledPlugin) throws {
        try update { $0.grants[plugin.installationID] = nil }
    }

    /// Turns a plugin or its hooks on or off. A bundled plugin without a grant gets one so the switch persists.
    public func setEnabled(_ plugin: InstalledPlugin, enabled: Bool? = nil, hooks: Bool? = nil) throws {
        let fingerprint = (try? PluginFingerprint(plugin: plugin))
            ?? PluginFingerprint(manifestSHA256: "", entrypointSHA256: "")
        try update { contents in
            var grant = contents.grants[plugin.installationID] ?? PluginGrant(
                fingerprint: self.isBundled(plugin) ? fingerprint : PluginFingerprint(manifestSHA256: "", entrypointSHA256: ""),
                version: plugin.manifest.version)
            if let enabled { grant.enabled = enabled }
            if let hooks { grant.hooksEnabled = hooks }
            contents.grants[plugin.installationID] = grant
        }
    }

    public func hooksEnabled(_ plugin: InstalledPlugin) -> Bool { grant(for: plugin)?.hooksEnabled ?? true }

    public func userOptions(_ plugin: InstalledPlugin) -> [String: JSONValue] { locked { contents.options[plugin.installationID] ?? [:] } }

    public func setUserOption(_ plugin: InstalledPlugin, key: String, value: JSONValue?) throws {
        try update { contents in
            var values = contents.options[plugin.installationID] ?? [:]
            values[key] = value
            contents.options[plugin.installationID] = values.isEmpty ? nil : values
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
