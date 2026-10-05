import Foundation

/// Downloads a `PluginLink` and hands the plugin folder to `PluginLocalSource`, which checks and stages it like a
/// folder from this Mac. Repo links are pinned to the commit their ref points at; an access token, when the app
/// has one for the link's host, is sent only to that host (and GitHub's API), never across a redirect.
public struct PluginLinkResolver: Sendable {
    /// The access token for a host (`github.com` for every GitHub link), or nil.
    public typealias TokenProvider = @Sendable (String) -> String?

    public let session: URLSession
    public let token: TokenProvider
    public let githubAPI: URL

    public init(
        session: URLSession = .shared, githubAPI: URL = URL(string: "https://api.github.com")!,
        token: @escaping TokenProvider = { _ in nil }
    ) {
        self.session = session
        self.githubAPI = githubAPI
        self.token = token
    }

    /// Downloads, checks and stages the plugin under `stagingParent`, waiting for the user's approval.
    public func stage(_ link: PluginLink, stagingParent: URL) async throws -> StagedLocalPlugin {
        let work = Self.workFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let (folder, origin) = try await fetch(link, into: work)
        let staged = try PluginLocalSource.stage(folder, stagingParent: stagingParent)
        return StagedLocalPlugin(
            plugin: staged.plugin, source: link.url, kind: .archive, sha256: origin.sha256, warnings: staged.warnings,
            stagingRoot: staged.stagingRoot, origin: origin)
    }

    /// Downloads and checks the plugin without installing it (`plugins validate --url`).
    public func validate(_ link: PluginLink) async -> PluginValidation {
        let work = Self.workFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            let (folder, origin) = try await fetch(link, into: work)
            var report = PluginLocalSource.validate(folder)
            report.kind = .archive
            report.sha256 = origin.sha256
            report.origin = origin
            return report
        } catch {
            var report = PluginValidation()
            report.problems.append(error.localizedDescription)
            return report
        }
    }

    private static func workFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bashcut-link-\(UUID().uuidString)", isDirectory: true)
    }

    /// The plugin folder inside `work`, and where it came from.
    func fetch(_ link: PluginLink, into work: URL) async throws -> (URL, PluginLinkOrigin) {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let download: URL
        var resolved: String?
        var accept: String?
        var path: String?
        switch link.target {
        case .archive(let url):
            download = url
        case .githubRepo(let owner, let repo, let ref, let subfolder):
            let commit = try await commit(owner: owner, repo: repo, ref: ref)
            resolved = commit
            path = subfolder
            download = api("repos", owner, repo, "zipball", commit)
        case .githubRelease(let owner, let repo, let tag):
            let (asset, tagName) = try await releaseAsset(owner: owner, repo: repo, tag: tag)
            resolved = tagName
            download = asset
            accept = "application/octet-stream"
        }
        let archive = work.appendingPathComponent("download.zip")
        try await self.download(download, to: archive, host: link.tokenHost, accept: accept)
        let sha256 = try PluginArchiveInstaller.sha256(of: archive)
        if let expected = link.sha256, expected != sha256 {
            throw PluginError.invalid("The download does not match the expected SHA-256 (got \(sha256))")
        }
        let top = try PluginArchiveInstaller.unpackSingleFolder(archive, into: work.appendingPathComponent("unpacked"))
        var folder = top
        if let path {
            folder = top.appendingPathComponent(path, isDirectory: true).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard folder.path.hasPrefix(top.standardizedFileURL.path + "/"),
                FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue
            else { throw PluginError.invalid("The repo has no folder \(path) at \(resolved ?? "that ref")") }
        }
        let origin = PluginLinkOrigin(
            url: link.url.absoluteString, resolved: resolved, archiveURL: download.absoluteString, sha256: sha256)
        return (folder, origin)
    }

    private func api(_ components: String...) -> URL {
        components.reduce(githubAPI) { $0.appendingPathComponent($1) }
    }

    /// The commit `ref` (or the default branch) points at, so the install is exactly what was checked.
    private func commit(owner: String, repo: String, ref: String?) async throws -> String {
        let data = try await get(
            api("repos", owner, repo, "commits", ref ?? "HEAD"), host: "github.com", accept: "application/vnd.github.sha",
            notFound: "No GitHub repo \(owner)/\(repo)" + (ref.map { " with ref \($0)" } ?? "")
                + ". For a private repo, add an access token for github.com")
        let sha = (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard sha.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
            throw PluginError.invalid("GitHub did not return a commit for \(owner)/\(repo)")
        }
        return sha
    }

    /// The release's one plugin archive: its only `.zip` / `.bashcutplugin` asset, preferring `.bashcutplugin`.
    private func releaseAsset(owner: String, repo: String, tag: String?) async throws -> (URL, String) {
        let url = tag.map { api("repos", owner, repo, "releases", "tags", $0) } ?? api("repos", owner, repo, "releases", "latest")
        let data = try await get(
            url, host: "github.com", accept: "application/vnd.github+json",
            notFound: "No release " + (tag ?? "(latest)") + " in \(owner)/\(repo)")
        let release: GitHubRelease
        do { release = try JSONDecoder().decode(GitHubRelease.self, from: data) } catch {
            throw PluginError.invalid("GitHub returned an unexpected release for \(owner)/\(repo)")
        }
        let archives = release.assets.filter { PluginLink.isArchive(URL(fileURLWithPath: $0.name)) }
        let bundles = archives.filter { $0.name.lowercased().hasSuffix(".bashcutplugin") }
        let candidates = bundles.isEmpty ? archives : bundles
        guard candidates.count == 1, let asset = candidates.first else {
            let names = archives.map(\.name).joined(separator: ", ")
            throw PluginError.invalid(archives.isEmpty
                ? "Release \(release.tagName) has no .zip or .bashcutplugin asset"
                : "Release \(release.tagName) has several archives (\(names)); link the one to install")
        }
        return (asset.url, release.tagName)
    }

    private func request(_ url: URL, host: String, accept: String?) -> URLRequest {
        var request = URLRequest(url: url)
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        if sendsToken(to: url, host: host), let token = token(host), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// A token for `github.com` also goes to GitHub's API; any other token only to its own host.
    private func sendsToken(to url: URL, host: String) -> Bool {
        let target = PluginLink.normalizedHost(url.host ?? "")
        return target == host || (host == "github.com" && target == PluginLink.normalizedHost(githubAPI.host ?? ""))
    }

    private func get(_ url: URL, host: String, accept: String, notFound: String) async throws -> Data {
        let (data, response) = try await session.data(for: request(url, host: host, accept: accept), delegate: RedirectGuard())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 404 { throw PluginError.invalid(notFound) }
        try Self.check(status, url: url)
        return data
    }

    private func download(_ url: URL, to destination: URL, host: String, accept: String?) async throws {
        let (location, response) = try await session.download(for: request(url, host: host, accept: accept), delegate: RedirectGuard())
        defer { try? FileManager.default.removeItem(at: location) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 404 {
            throw PluginError.invalid("Nothing to download at \(url.absoluteString). For a private link, add an access token")
        }
        try Self.check(status, url: url)
        let size = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= PluginArchiveInstaller.maximumArchiveBytes else {
            throw PluginError.invalid("The plugin archive is larger than 512 MB")
        }
        try FileManager.default.moveItem(at: location, to: destination)
    }

    private static func check(_ status: Int, url: URL) throws {
        switch status {
        case 200..<300: return
        case 401, 403:
            throw PluginError.invalid(
                "Access denied (HTTP \(status)) for \(url.host ?? "the link"): add or update the access token for it")
        default:
            throw PluginError.invalid("Download failed with HTTP \(status) from \(url.host ?? "the link")")
        }
    }
}

/// The fields of a GitHub release that Add Plugin… uses.
private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubReleaseAsset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let url: URL
}

/// Drops the access token when a redirect leaves the host it was meant for (GitHub sends archives from signed URLs
/// on other hosts).
private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        var next = request
        if task.originalRequest?.url?.host?.lowercased() != request.url?.host?.lowercased() {
            next.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        guard next.url?.scheme == "https" else { return nil }
        return next
    }
}
