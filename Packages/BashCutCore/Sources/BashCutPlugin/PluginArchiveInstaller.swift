import Crypto
import Foundation

/// A downloaded, verified and unpacked plugin waiting for the user's approval. Nothing from it has run.
public struct StagedPluginArchive: Sendable {
    public let plugin: InstalledPlugin
    public let entry: PluginRegistryEntry
    public let version: PluginRegistryVersion
    /// Who signed the archive.
    public let publisherTrust: PluginPublisherTrust
    /// Folder that holds the unpacked plugin; remove it with `discard()` once installed or cancelled.
    public let stagingRoot: URL

    public func discard() { try? FileManager.default.removeItem(at: stagingRoot) }
}

/// Downloads a registry archive and checks it before anything in it can run:
///
/// 1. HTTPS on an allowed host; 2. size; 3. SHA-256 from the registry, and its ed25519 signature when there is
/// one (a wrong signature is refused); 4. unpack with `ditto` into a staging
/// folder; 5. exactly one plugin folder, no links leaving it; 6. manifest valid, with the registry's id and
/// version; 7. quarantine removed. Moving it into place, dependency recipes and trust stay with the app, after
/// the user approves.
public struct PluginArchiveInstaller: Sendable {
    public static let defaultHosts: Set<String> = [
        "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com",
        "raw.githubusercontent.com", "cdn.jsdelivr.net",
    ]
    public static let maximumArchiveBytes = 512 * 1024 * 1024

    /// Parent of the staging folders; the user plugin root, so the final move stays on one volume.
    public let stagingParent: URL
    public let allowedHosts: Set<String>
    /// Tests install from `file://` URLs; the app never sets this.
    public let allowFileURLs: Bool
    private let session: URLSession

    public init(
        stagingParent: URL, allowedHosts: Set<String> = defaultHosts, allowFileURLs: Bool = false,
        session: URLSession = .shared
    ) {
        self.stagingParent = stagingParent
        self.allowedHosts = allowedHosts
        self.allowFileURLs = allowFileURLs
        self.session = session
    }

    /// `publisherKeys` are the registry's keys for the entry's publisher (`PluginRegistryDocument.keys(for:)`).
    public func stage(
        _ entry: PluginRegistryEntry, version: PluginRegistryVersion, publisherKeys: [String] = [],
        firstPartyKeys: [String] = PluginSignature.firstPartyKeys
    ) async throws -> StagedPluginArchive {
        guard let url = URL(string: version.url) else { throw PluginError.invalid("Invalid archive URL") }
        if let reason = version.yanked { throw PluginError.invalid("Version \(version.version) was withdrawn: \(reason)") }
        try checkSource(url)
        // Before downloading: a bad signature means the registry entry itself is wrong.
        let publisherTrust = try PluginSignature.verify(
            digest: version.sha256.lowercased(), signature: version.signature, publisher: entry.publisher,
            registryKeys: publisherKeys, firstPartyKeys: firstPartyKeys)
        if publisherTrust == .firstParty, entry.publisher != "bashcut" {
            throw PluginError.invalid("\(entry.id) is signed with the BashCut key but names another publisher")
        }
        let archive = try await download(url, expectedSize: version.size)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard try Self.sha256(of: archive) == version.sha256.lowercased() else {
            throw PluginError.invalid("The downloaded archive does not match the registry checksum")
        }
        let manager = FileManager.default
        try manager.createDirectory(at: stagingParent, withIntermediateDirectories: true)
        let stagingRoot = stagingParent.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let plugin = try unpack(archive, into: stagingRoot, entry: entry, version: version)
            return StagedPluginArchive(
                plugin: plugin, entry: entry, version: version, publisherTrust: publisherTrust, stagingRoot: stagingRoot)
        } catch {
            try? manager.removeItem(at: stagingRoot)
            throw error
        }
    }

    func checkSource(_ url: URL) throws {
        if url.isFileURL, allowFileURLs { return }
        guard url.scheme == "https", let host = url.host?.lowercased(), allowedHosts.contains(host) else {
            throw PluginError.invalid("Plugin archives must come over HTTPS from an allowed host (\(url.host ?? "none"))")
        }
    }

    private func download(_ url: URL, expectedSize: Int?) async throws -> URL {
        let limit = min(Self.maximumArchiveBytes, expectedSize.map { $0 + $0 / 10 + 1_048_576 } ?? Self.maximumArchiveBytes)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("bashcut-plugin-\(UUID().uuidString).zip")
        if url.isFileURL {
            try FileManager.default.copyItem(at: url, to: temporary)
        } else {
            let (location, response) = try await session.download(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard (200..<300).contains(status) else {
                try? FileManager.default.removeItem(at: location)
                throw PluginError.invalid("Download failed with HTTP \(status)")
            }
            try FileManager.default.moveItem(at: location, to: temporary)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= limit else {
            try? FileManager.default.removeItem(at: temporary)
            throw PluginError.invalid("The plugin archive is larger than the registry says")
        }
        return temporary
    }

    private func unpack(
        _ archive: URL, into stagingRoot: URL, entry: PluginRegistryEntry, version: PluginRegistryVersion
    ) throws -> InstalledPlugin {
        let unpacked = stagingRoot.appendingPathComponent("unpacked", isDirectory: true)
        let folder = try Self.unpackSingleFolder(archive, into: unpacked)
        let manager = FileManager.default
        let manifest: PluginManifest
        do {
            manifest = try JSONDecoder().decode(
                PluginManifest.self, from: Data(contentsOf: folder.appendingPathComponent("plugin.json")))
        } catch { throw PluginError.invalid("The archive has no valid plugin.json") }
        try manifest.validate()
        guard manifest.id == entry.id else {
            throw PluginError.invalid("The archive holds \(manifest.id), not \(entry.id)")
        }
        guard manifest.version == version.version else {
            throw PluginError.invalid("The archive is version \(manifest.version), the registry says \(version.version)")
        }
        // Name the folder after the plugin id, as installs are.
        let named = stagingRoot.appendingPathComponent(manifest.id, isDirectory: true)
        try manager.moveItem(at: folder, to: named)
        try? manager.removeItem(at: unpacked)
        try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", named.path])
        let plugin = InstalledPlugin(manifest: manifest, directory: named)
        _ = try plugin.entrypointURL()
        return plugin
    }

    /// Unpacks a zip into `unpacked` and returns its one plugin folder, after checking it has no links leaving it.
    static func unpackSingleFolder(_ archive: URL, into unpacked: URL) throws -> URL {
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        let items = try FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
        guard items.count == 1, let folder = items.first,
            (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { throw PluginError.invalid("The archive must contain exactly one plugin folder") }
        try checkLinks(in: folder)
        return folder
    }

    /// Rejects symbolic links that point outside the plugin folder.
    static func checkLinks(in folder: URL) throws {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let item = enumerator?.nextObject() as? URL {
            guard (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else { continue }
            let target = item.resolvingSymlinksInPath().standardizedFileURL.path
            guard target.hasPrefix(root) else {
                throw PluginError.invalid("The plugin links outside its folder: \(item.lastPathComponent)")
            }
        }
    }

    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PluginError.invalid("Cannot unpack the plugin archive: \(detail.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
