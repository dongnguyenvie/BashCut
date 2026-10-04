import BashCutPlugin
import Foundation

/// `releases.json` on bashcut-agent-kit's main branch: signed kit archives BashCut can install between app releases.
public struct AgentKitReleaseCatalog: Codable, Sendable, Equatable {
    public static let supportedSchema = 1

    public let schemaVersion: Int
    public let kit: String
    public let versions: [AgentKitRelease]

    public init(schemaVersion: Int = supportedSchema, kit: String = "bashcut", versions: [AgentKitRelease]) {
        self.schemaVersion = schemaVersion
        self.kit = kit
        self.versions = versions
    }

    /// The newest release this app can use that is newer than `current`; nil when the kit is up to date.
    /// Development builds without a real version accept every `minAppVersion`, as the plugin registry does.
    public func update(from current: String, appVersion: String) -> AgentKitRelease? {
        let app = SemanticVersion(appVersion)
        let installed = SemanticVersion(current) ?? .zero
        return versions
            .filter { release in
                guard release.yanked == nil else { return false }
                guard let app, let minimum = SemanticVersion(release.minAppVersion) else { return true }
                return app >= minimum
            }
            .compactMap { release in SemanticVersion(release.version).map { (release, $0) } }
            .filter { $0.1 > installed }
            .max { $0.1 < $1.1 }?.0
    }
}

public struct AgentKitRelease: Codable, Sendable, Equatable {
    public let version: String
    public let minAppVersion: String
    public let url: String
    public let sha256: String
    public let signature: String?
    public let size: Int?
    public let releasedAt: String?
    /// Short release notes by language code (`en`, `vi`).
    public let notes: [String: String]?
    /// Why a release was withdrawn; withdrawn releases are never offered.
    public let yanked: String?

    public init(
        version: String, minAppVersion: String = "0.0.1", url: String, sha256: String, signature: String?,
        size: Int? = nil, releasedAt: String? = nil, notes: [String: String]? = nil, yanked: String? = nil
    ) {
        self.version = version
        self.minAppVersion = minAppVersion
        self.url = url
        self.sha256 = sha256
        self.signature = signature
        self.size = size
        self.releasedAt = releasedAt
        self.notes = notes
        self.yanked = yanked
    }
}

/// Checks `releases.json` and installs a release into `agent-kits/<version>` in BashCut's support folder.
///
/// Nothing from an archive is used before: 1. HTTPS from GitHub; 2. a first-party ed25519 signature of the
/// catalog's SHA-256 (checked before downloading; unsigned releases are refused); 3. size and SHA-256 of the bytes;
/// 4. one kit folder with no link leaving it, whose plugin.json names the catalog's version.
public struct AgentKitUpdater: Sendable {
    public static let catalogURL = URL(
        string: "https://raw.githubusercontent.com/dongnguyenvie/bashcut-agent-kit/main/releases.json")!
    static let allowedHosts: Set<String> = [
        "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com",
        "raw.githubusercontent.com",
    ]
    static let maximumArchiveBytes = 64 * 1024 * 1024

    /// `~/Library/Application Support/BashCut`.
    public let support: URL
    let catalogURL: URL
    let firstPartyKeys: [String]
    /// Tests install from `file://` URLs; the app never sets this.
    let allowFileURLs: Bool
    private let session: URLSession

    public init(support: URL, catalogURL: URL = catalogURL, session: URLSession = .shared) {
        self.init(support: support, catalogURL: catalogURL, firstPartyKeys: PluginSignature.firstPartyKeys,
                  allowFileURLs: false, session: session)
    }

    init(support: URL, catalogURL: URL, firstPartyKeys: [String], allowFileURLs: Bool, session: URLSession = .shared) {
        self.support = support
        self.catalogURL = catalogURL
        self.firstPartyKeys = firstPartyKeys
        self.allowFileURLs = allowFileURLs
        self.session = session
    }

    public var releasesFolder: URL { support.appendingPathComponent("agent-kits", isDirectory: true) }

    public func catalog() async throws -> AgentKitReleaseCatalog {
        let data: Data
        if catalogURL.isFileURL, allowFileURLs {
            data = try Data(contentsOf: catalogURL)
        } else {
            // The query defeats raw.githubusercontent.com's five-minute cache, so a new release shows at once.
            let request = URLRequest(url: PluginRegistryClient.requestURL(catalogURL, force: true),
                                     cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            let (body, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            // No releases.json on main yet means nothing has been published, not a failure.
            if status == 404 { return AgentKitReleaseCatalog(versions: []) }
            guard (200..<300).contains(status) else { throw AgentKitError("Kit releases answered HTTP \(status)") }
            data = body
        }
        guard data.count <= 1_048_576 else { throw AgentKitError("The kit release list is too large") }
        let catalog: AgentKitReleaseCatalog
        do { catalog = try JSONDecoder().decode(AgentKitReleaseCatalog.self, from: data) } catch {
            throw AgentKitError("The kit release list is not valid: \(error.localizedDescription)")
        }
        guard catalog.schemaVersion == AgentKitReleaseCatalog.supportedSchema, catalog.kit == "bashcut" else {
            throw AgentKitError("The kit release list needs a newer BashCut (schema \(catalog.schemaVersion))")
        }
        return catalog
    }

    /// Downloads, verifies and unpacks `release`; returns the installed kit. Older downloaded versions are removed.
    public func install(_ release: AgentKitRelease) async throws -> AgentKit {
        guard let url = URL(string: release.url) else { throw AgentKitError("Invalid kit archive URL") }
        try checkSource(url)
        let digest = release.sha256.lowercased()
        let trust = try PluginSignature.verify(
            digest: digest, signature: release.signature, publisher: "bashcut", registryKeys: [],
            firstPartyKeys: firstPartyKeys)
        guard trust == .firstParty else { throw AgentKitError("Kit \(release.version) is not signed by BashCut") }
        let archive = try await download(url, expectedSize: release.size)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard try PluginArchiveInstaller.sha256(of: archive) == digest else {
            throw AgentKitError("The downloaded kit does not match its published checksum")
        }
        let manager = FileManager.default
        try manager.createDirectory(at: releasesFolder, withIntermediateDirectories: true)
        let staging = releasesFolder.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: staging) }
        let folder = try Self.unpack(archive, into: staging)
        guard let kit = AgentKit(root: folder, source: .downloaded), kit.version == release.version else {
            throw AgentKitError("The archive does not hold agent kit \(release.version)")
        }
        let destination = releasesFolder.appendingPathComponent(release.version, isDirectory: true)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: folder)
        } else {
            try manager.moveItem(at: folder, to: destination)
        }
        guard let installed = AgentKit(root: destination, source: .downloaded) else {
            throw AgentKitError("Agent kit \(release.version) could not be installed")
        }
        // Agents read the stable copy in agent-kit/, so earlier downloads are no longer used.
        for older in Self.downloaded(in: support) where older.version != installed.version {
            try? manager.removeItem(at: older.root)
        }
        return installed
    }

    /// Kits installed from releases, newest first.
    public static func downloaded(in support: URL) -> [AgentKit] {
        let folder = support.appendingPathComponent("agent-kits", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }
            .compactMap { AgentKit(root: folder.appendingPathComponent($0, isDirectory: true), source: .downloaded) }
            .sorted { (SemanticVersion($0.version) ?? .zero) > (SemanticVersion($1.version) ?? .zero) }
    }

    func checkSource(_ url: URL) throws {
        if url.isFileURL, allowFileURLs { return }
        guard url.scheme == "https", let host = url.host?.lowercased(), Self.allowedHosts.contains(host) else {
            throw AgentKitError("Kit archives must come over HTTPS from GitHub (\(url.host ?? "no host"))")
        }
    }

    private func download(_ url: URL, expectedSize: Int?) async throws -> URL {
        let limit = min(Self.maximumArchiveBytes, expectedSize.map { $0 + $0 / 10 + 1_048_576 } ?? Self.maximumArchiveBytes)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("bashcut-kit-\(UUID().uuidString).zip")
        if url.isFileURL {
            try FileManager.default.copyItem(at: url, to: temporary)
        } else {
            let (location, response) = try await session.download(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard (200..<300).contains(status) else {
                try? FileManager.default.removeItem(at: location)
                throw AgentKitError("Kit download failed with HTTP \(status)")
            }
            try FileManager.default.moveItem(at: location, to: temporary)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= limit else {
            try? FileManager.default.removeItem(at: temporary)
            throw AgentKitError("The kit archive is larger than its release says")
        }
        return temporary
    }

    /// The single kit folder inside `archive`, unpacked under `staging` with no link leaving it.
    private static func unpack(_ archive: URL, into staging: URL) throws -> URL {
        let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        let items = try FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
        guard items.count == 1, let folder = items.first,
            (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { throw AgentKitError("The kit archive must contain exactly one folder") }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let item = enumerator?.nextObject() as? URL {
            guard (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else { continue }
            guard item.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) else {
                throw AgentKitError("The kit archive links outside its folder: \(item.lastPathComponent)")
            }
        }
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", folder.path])
        return folder
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
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
            throw AgentKitError("Cannot unpack the kit archive: \(detail.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
