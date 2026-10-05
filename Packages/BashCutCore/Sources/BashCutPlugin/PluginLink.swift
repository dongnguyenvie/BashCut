import Foundation

/// A link to a plugin that is not in the registry (#83), as the plugin's author shares it:
///
/// - a direct archive: `https://example.com/my-plugin.zip` (or `.bashcutplugin`);
/// - a GitHub repo: `https://github.com/user/repo`, optionally `#<tag|branch|commit>` or
///   `/tree/<ref>/<subfolder>`; the plugin folder is the repo root or the subfolder;
/// - a GitHub release: `https://github.com/user/repo/releases/tag/<tag>` (or `/releases/latest`), using its one
///   `.zip` / `.bashcutplugin` asset;
/// - a GitHub `plugin.json`: `…/blob/<ref>/<folder>/plugin.json` or the `raw.githubusercontent.com` link; the
///   folder is fetched from the same repo and ref.
///
/// `#sha256=<hex>` (also `#<ref>&sha256=<hex>`) pins the downloaded archive.
public struct PluginLink: Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        case archive(URL)
        /// `ref` nil = the default branch; `path` nil = the repo root.
        case githubRepo(owner: String, repo: String, ref: String?, path: String?)
        /// `tag` nil = the latest release.
        case githubRelease(owner: String, repo: String, tag: String?)
    }

    /// The link as given, without the fragment.
    public let url: URL
    public let target: Target
    /// Expected SHA-256 of the downloaded archive (lowercase hex).
    public let sha256: String?

    /// The host whose access token is sent: `github.com` for every GitHub link.
    public var tokenHost: String {
        switch target {
        case .githubRepo, .githubRelease: "github.com"
        case .archive(let url): Self.normalizedHost(url.host ?? "")
        }
    }

    /// `ref` overrides a ref or release tag in the link; `sha256` overrides one in its fragment.
    public init(parsing text: String, ref: String? = nil, sha256: String? = nil) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), components.scheme?.lowercased() == "https",
            let rawHost = components.host, !rawHost.isEmpty
        else { throw PluginError.invalid("Paste an https:// link to a plugin zip, a GitHub repo or a GitHub release") }
        let (fragmentRef, fragmentHash) = Self.fragment(components.fragment)
        components.fragment = nil
        guard let url = components.url else { throw PluginError.invalid("This link is not a valid URL") }
        self.url = url
        self.sha256 = try Self.checkedHash(sha256?.isEmpty == false ? sha256 : fragmentHash)
        let ref = ref?.isEmpty == false ? ref : fragmentRef
        let host = Self.normalizedHost(rawHost)
        let parts = url.path.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }
        switch host {
        case "github.com": target = try Self.github(parts, url: url, ref: ref)
        case "raw.githubusercontent.com": target = try Self.raw(parts, url: url, ref: ref)
        default:
            if Self.isArchive(url) {
                target = .archive(url)
            } else if url.lastPathComponent == "plugin.json" {
                throw PluginError.invalid(
                    "A plugin.json link only works on GitHub; link the plugin's .zip instead")
            } else {
                throw PluginError.invalid(
                    "Link a .zip or .bashcutplugin file, a GitHub repo or a GitHub release (\(url.absoluteString))")
            }
        }
    }

    /// `#<ref>`, `#sha256=<hex>` or both, joined by `&`.
    private static func fragment(_ fragment: String?) -> (ref: String?, sha256: String?) {
        var ref: String?
        var hash: String?
        for part in (fragment ?? "").split(separator: "&").map(String.init) where !part.isEmpty {
            if part.lowercased().hasPrefix("sha256=") {
                hash = String(part.dropFirst("sha256=".count))
            } else {
                ref = part.removingPercentEncoding ?? part
            }
        }
        return (ref, hash)
    }

    private static func checkedHash(_ hash: String?) throws -> String? {
        guard let hash = hash?.lowercased() else { return nil }
        guard hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw PluginError.invalid("sha256 must be 64 hexadecimal characters")
        }
        return hash
    }

    static func normalizedHost(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    static func isArchive(_ url: URL) -> Bool { PluginLocalSource.archiveExtensions.contains(url.pathExtension.lowercased()) }

    private static func github(_ parts: [String], url: URL, ref: String?) throws -> Target {
        guard parts.count >= 2 else { throw PluginError.invalid("Link a GitHub repo as https://github.com/<owner>/<repo>") }
        let owner = parts[0]
        let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        let rest = Array(parts.dropFirst(2))
        func folder(_ items: ArraySlice<String>) -> String? { items.isEmpty ? nil : items.joined(separator: "/") }
        switch rest.first {
        case nil:
            return .githubRepo(owner: owner, repo: repo, ref: ref, path: nil)
        case "tree" where rest.count >= 2:
            return .githubRepo(owner: owner, repo: repo, ref: ref ?? rest[1], path: folder(rest.dropFirst(2)))
        case "blob" where rest.count >= 3 && rest.last == "plugin.json":
            return .githubRepo(owner: owner, repo: repo, ref: ref ?? rest[1], path: folder(rest.dropFirst(2).dropLast()))
        case "releases":
            if rest.count >= 4, rest[1] == "download", isArchive(url) { return .archive(url) }
            if rest.count >= 3, rest[1] == "tag" { return .githubRelease(owner: owner, repo: repo, tag: ref ?? rest[2]) }
            if rest.count <= 2, rest.count == 1 || rest[1] == "latest" {
                return .githubRelease(owner: owner, repo: repo, tag: ref)
            }
        case "archive" where isArchive(url):
            return .archive(url)
        default:
            break
        }
        throw PluginError.invalid(
            "Link the repo, a folder in it (/tree/<ref>/<folder>), its plugin.json, or a release (\(url.absoluteString))")
    }

    private static func raw(_ parts: [String], url: URL, ref: String?) throws -> Target {
        guard parts.count >= 4 else { throw PluginError.invalid("This raw.githubusercontent.com link names no file") }
        if isArchive(url) { return .archive(url) }
        guard parts.last == "plugin.json" else {
            throw PluginError.invalid("Link the plugin's plugin.json or a .zip file")
        }
        let folder = parts.dropFirst(3).dropLast()
        return .githubRepo(
            owner: parts[0], repo: parts[1], ref: ref ?? parts[2], path: folder.isEmpty ? nil : folder.joined(separator: "/"))
    }
}

/// Where a plugin installed from a link came from; kept with the install so its source can be shown and checked
/// for updates.
public struct PluginLinkOrigin: Codable, Sendable, Equatable {
    /// The link as given, without a token or fragment.
    public var url: String
    /// The commit (repo links) or release tag the link resolved to.
    public var resolved: String?
    /// The archive that was downloaded.
    public var archiveURL: String
    public var sha256: String
    public var installedAt: Date?

    public init(url: String, resolved: String?, archiveURL: String, sha256: String, installedAt: Date? = nil) {
        self.url = url
        self.resolved = resolved
        self.archiveURL = archiveURL
        self.sha256 = sha256
        self.installedAt = installedAt
    }
}
