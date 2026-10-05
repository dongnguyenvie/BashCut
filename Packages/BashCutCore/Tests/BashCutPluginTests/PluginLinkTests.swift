@testable import BashCutPlugin
import Foundation
import Testing

/// Serves canned responses per URL, so link installs are tested without the network. Each test uses its own host.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        var status = 200
        var body = Data()
        var redirect: URL?
    }

    nonisolated(unsafe) static var stubs: [String: Stub] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    static func set(_ url: String, _ stub: Stub) {
        lock.withLock { stubs[url] = stub }
    }

    static func seen(host: String) -> [URLRequest] {
        lock.withLock { requests.filter { $0.url?.host == host } }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let stub = Self.lock.withLock {
            Self.requests.append(request)
            return Self.stubs[url.absoluteString]
        }
        guard let stub else {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if let redirect = stub.redirect {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": redirect.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: redirect), redirectResponse: response)
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct PluginLinkTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("link-plugins-\(UUID().uuidString)")
    let tag = UUID().uuidString.prefix(8).lowercased()
    var api: String { "https://api-\(tag).test" }
    var files: String { "https://files-\(tag).test" }

    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func resolver(token: String? = nil) -> PluginLinkResolver {
        PluginLinkResolver(session: session, githubAPI: URL(string: api)!) { _ in token }
    }

    /// A zip holding `top/<subfolder>/` with a valid plugin.
    private func zip(top: String, subfolder: String? = nil) throws -> Data {
        let base = root.appendingPathComponent("src/\(UUID().uuidString)/\(top)")
        let folder = subfolder.map { base.appendingPathComponent($0) } ?? base
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let manifest = PluginManifest(
            id: "nolan.linked-demo", name: "Linked demo", version: "0.2.0", entrypoint: "bin/provider",
            capabilities: ["audio.beats"])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("plugin.json"))
        let entrypoint = folder.appendingPathComponent("bin/provider")
        try Data("#!/bin/sh\n".utf8).write(to: entrypoint)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entrypoint.path)
        let zip = root.appendingPathComponent("\(UUID().uuidString).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", base.path, zip.path]
        try process.run()
        process.waitUntilExit()
        return try Data(contentsOf: zip)
    }

    @Test("Links parse into an archive, a repo folder or a release, with ref and sha256 from the fragment")
    func parsing() throws {
        let hash = String(repeating: "ab", count: 32)
        #expect(try PluginLink(parsing: "https://example.com/p/demo.zip#sha256=\(hash.uppercased())").sha256 == hash)
        #expect(try PluginLink(parsing: "https://example.com/p/demo.zip").target == .archive(URL(string: "https://example.com/p/demo.zip")!))
        #expect(try PluginLink(parsing: "https://example.com/p/demo.zip").tokenHost == "example.com")
        #expect(try PluginLink(parsing: "https://github.com/nolan/plugs").target
            == .githubRepo(owner: "nolan", repo: "plugs", ref: nil, path: nil))
        #expect(try PluginLink(parsing: "https://www.github.com/nolan/plugs.git#v1.2").target
            == .githubRepo(owner: "nolan", repo: "plugs", ref: "v1.2", path: nil))
        #expect(try PluginLink(parsing: "https://github.com/nolan/plugs/tree/main/plugins/hello").target
            == .githubRepo(owner: "nolan", repo: "plugs", ref: "main", path: "plugins/hello"))
        #expect(try PluginLink(parsing: "https://github.com/nolan/plugs/tree/main/plugins/hello", ref: "dev").target
            == .githubRepo(owner: "nolan", repo: "plugs", ref: "dev", path: "plugins/hello"))
        #expect(try PluginLink(parsing: "https://github.com/nolan/plugs/blob/v2/hello/plugin.json").target
            == .githubRepo(owner: "nolan", repo: "plugs", ref: "v2", path: "hello"))
        #expect(try PluginLink(parsing: "https://raw.githubusercontent.com/nolan/plugs/v2/plugin.json").target
            == .githubRepo(owner: "nolan", repo: "plugs", ref: "v2", path: nil))
        #expect(try PluginLink(parsing: "https://github.com/nolan/plugs/releases/tag/hello-v1").target
            == .githubRelease(owner: "nolan", repo: "plugs", tag: "hello-v1"))
        #expect(try PluginLink(parsing: "https://github.com/nolan/plugs/releases/latest").target
            == .githubRelease(owner: "nolan", repo: "plugs", tag: nil))
        let asset = "https://github.com/nolan/plugs/releases/download/v1/hello.zip"
        #expect(try PluginLink(parsing: asset).target == .archive(URL(string: asset)!))
        #expect(try PluginLink(parsing: asset).tokenHost == "github.com")
        for bad in ["http://example.com/p.zip", "ftp://x/p.zip", "not a link", "https://example.com/p/plugin.json",
                    "https://example.com/page", "https://github.com/nolan", "https://github.com/nolan/plugs/issues/3",
                    "https://example.com/p.zip#sha256=123"] {
            #expect(throws: PluginError.self) { try PluginLink(parsing: bad) }
        }
    }

    @Test("A repo link is pinned to its commit; the folder inside the repo is staged; the token goes to GitHub only")
    func repo() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let commit = String(repeating: "c", count: 40)
        StubURLProtocol.set("\(api)/repos/nolan/plugs/commits/main", .init(body: Data(commit.utf8)))
        StubURLProtocol.set("\(api)/repos/nolan/plugs/zipball/\(commit)", .init(redirect: URL(string: "\(files)/zip/\(commit)")!))
        let archive = try zip(top: "nolan-plugs-ccccccc", subfolder: "plugins/hello")
        StubURLProtocol.set("\(files)/zip/\(commit)", .init(body: archive))
        let link = try PluginLink(parsing: "https://github.com/nolan/plugs/tree/main/plugins/hello")
        let staged = try await resolver(token: "secret-token").stage(link, stagingParent: root.appendingPathComponent("Plugins"))
        #expect(staged.plugin.id == "nolan.linked-demo" && staged.kind == .archive)
        #expect(staged.origin?.resolved == commit)
        #expect(staged.origin?.url == "https://github.com/nolan/plugs/tree/main/plugins/hello")
        #expect(staged.sha256 == staged.origin?.sha256 && staged.sha256 != nil)
        _ = try staged.plugin.entrypointURL()
        staged.discard()
        let apiCalls = StubURLProtocol.seen(host: "api-\(tag).test")
        #expect(!apiCalls.isEmpty && apiCalls.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token" })
        // The redirect to another host does not carry the token.
        let fileCalls = StubURLProtocol.seen(host: "files-\(tag).test")
        #expect(!fileCalls.isEmpty && fileCalls.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })

        let missing = try PluginLink(parsing: "https://github.com/nolan/plugs/tree/main/plugins/nope")
        await #expect(throws: PluginError.self) { try await resolver().stage(missing, stagingParent: root) }
        let unknown = try PluginLink(parsing: "https://github.com/nolan/other")
        let report = await resolver().validate(unknown)
        #expect(report.problems.first?.hasPrefix("No GitHub repo nolan/other") == true)
    }

    @Test("A release uses its one plugin archive; a wrong sha256 or a denied download is refused")
    func release() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try zip(top: "hello")
        let release = """
            {"tag_name": "hello-v0.2.0", "assets": [
              {"name": "notes.txt", "url": "\(api)/assets/1"},
              {"name": "hello.zip", "url": "\(api)/assets/2"}]}
            """
        StubURLProtocol.set("\(api)/repos/nolan/plugs/releases/latest", .init(body: Data(release.utf8)))
        StubURLProtocol.set("\(api)/assets/2", .init(body: archive))
        let link = try PluginLink(parsing: "https://github.com/nolan/plugs/releases/latest")
        let report = await resolver().validate(link)
        #expect(report.isValid && report.origin?.resolved == "hello-v0.2.0")
        let sha = try #require(report.sha256)
        #expect(StubURLProtocol.seen(host: "api-\(tag).test").last?.value(forHTTPHeaderField: "Accept") == "application/octet-stream")
        let pinned = try PluginLink(parsing: "https://github.com/nolan/plugs/releases/latest", sha256: sha)
        #expect(await resolver().validate(pinned).isValid)
        let wrong = try PluginLink(parsing: "https://github.com/nolan/plugs/releases/latest", sha256: String(repeating: "0", count: 64))
        #expect(await resolver().validate(wrong).problems.first?.hasPrefix("The download does not match") == true)

        let several = """
            {"tag_name": "v2", "assets": [{"name": "a.zip", "url": "\(api)/assets/3"}, {"name": "b.zip", "url": "\(api)/assets/4"}]}
            """
        StubURLProtocol.set("\(api)/repos/nolan/plugs/releases/tags/v2", .init(body: Data(several.utf8)))
        let ambiguous = await resolver().validate(try PluginLink(parsing: "https://github.com/nolan/plugs/releases/tag/v2"))
        #expect(ambiguous.problems.first?.contains("several archives (a.zip, b.zip)") == true)

        StubURLProtocol.set("\(files)/private.zip", .init(status: 403))
        let denied = await resolver().validate(try PluginLink(parsing: "\(files)/private.zip"))
        #expect(denied.problems.first?.hasPrefix("Access denied (HTTP 403)") == true)
        StubURLProtocol.set("\(files)/demo.zip", .init(body: archive))
        let direct = await resolver(token: "t").validate(try PluginLink(parsing: "\(files)/demo.zip"))
        #expect(direct.isValid && direct.origin?.resolved == nil)
        #expect(StubURLProtocol.seen(host: "files-\(tag).test").last?.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }
}
