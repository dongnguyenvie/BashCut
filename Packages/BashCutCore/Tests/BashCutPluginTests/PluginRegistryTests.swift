import BashCutPlugin
import Foundation
import Testing

@Suite("Plugin registry")
struct PluginRegistryTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("registry-\(UUID().uuidString)")

    private func version(
        _ value: String, api: Int = 2, minApp: String? = nil, platforms: [String]? = nil, url: String = "https://github.com/x.zip",
        sha256: String = "00"
    ) -> PluginRegistryVersion {
        PluginRegistryVersion(
            version: value, apiVersion: api, minAppVersion: minApp, platforms: platforms, url: url, sha256: sha256)
    }

    @Test("Registry JSON decodes localized names and rejects newer schemas")
    func decode() throws {
        let json = #"""
            {"schemaVersion": 1, "publishers": {"bashcut": {"name": "BashCut", "keys": [], "verified": true}},
             "plugins": [{"id": "bashcut.silence-markers", "name": {"en": "Silence Markers", "vi": "Đánh dấu im lặng"},
               "summary": "Marks pauses", "versions": [{"version": "0.2.0", "apiVersion": 2,
               "url": "https://github.com/a.zip", "sha256": "ab", "signature": null}]}]}
            """#
        let document = try PluginRegistryClient.decode(Data(json.utf8))
        let entry = try #require(document.entry("bashcut.silence-markers"))
        #expect(entry.name.text(for: "vi") == "Đánh dấu im lặng")
        #expect(entry.summary?.text(for: "vi") == "Marks pauses")
        #expect(entry.matches("im lặng") && entry.matches("SILENCE") && !entry.matches("whisper"))
        #expect(throws: PluginError.self) {
            try PluginRegistryClient.decode(Data(#"{"schemaVersion": 9, "plugins": []}"#.utf8))
        }
    }

    @Test("The newest compatible version wins; reasons explain when none fits")
    func resolution() throws {
        let entry = PluginRegistryEntry(id: "a.b", name: "A", versions: [
            version("0.9.0"), version("1.0.0", minApp: "0.2.0"), version("1.1.0", api: PluginAPI.current + 1), version("0.10.0"),
        ])
        #expect(try entry.resolve(appVersion: "0.2.0").get().version == "1.0.0")
        #expect(try entry.resolve(appVersion: "0.1.0").get().version == "0.10.0")
        // Development builds have no version and accept any minAppVersion.
        #expect(try entry.resolve(appVersion: "$(MARKETING_VERSION)").get().version == "1.0.0")
        let futureOnly = PluginRegistryEntry(id: "a.b", name: "A", versions: [version("1.0.0", api: PluginAPI.current + 1)])
        #expect(throws: PluginError.self) { try futureOnly.resolve(appVersion: "1.0.0").get() }
        let intelOnly = PluginRegistryEntry(id: "a.b", name: "A", versions: [version("1.0.0", platforms: ["macos-x86_64"])])
        #expect(throws: PluginError.self) { try intelOnly.resolve(appVersion: "1.0.0", platform: "macos-arm64").get() }
        let universal = PluginRegistryEntry(id: "a.b", name: "A", versions: [version("1.0.0", platforms: ["macos-universal"])])
        #expect(try universal.resolve(appVersion: "1.0.0", platform: "macos-arm64").get().version == "1.0.0")
    }

    @Test("Semantic versions compare numerically with prereleases first")
    func semver() throws {
        let order = ["0.9.0", "0.10.0-beta.1", "0.10.0", "1.0", "1.0.1"].compactMap(SemanticVersion.init)
        #expect(order.count == 5)
        #expect(order == order.sorted())
        #expect(SemanticVersion("x.y") == nil)
    }

    @Test("A forced refresh adds a cache-busting query; file URLs and normal fetches stay as they are")
    func forceURL() throws {
        let remote = try #require(URL(string: "https://raw.githubusercontent.com/o/r/main/registry.json"))
        #expect(PluginRegistryClient.requestURL(remote, force: false) == remote)
        let forced = PluginRegistryClient.requestURL(remote, force: true)
        #expect(forced.path == remote.path)
        #expect(URLComponents(url: forced, resolvingAgainstBaseURL: false)?.queryItems?.first?.name == "t")
        let local = URL(fileURLWithPath: "/tmp/registry.json")
        #expect(PluginRegistryClient.requestURL(local, force: true) == local)
    }

    @Test("The client caches the last good copy and falls back to it")
    func clientCache() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("registry.json")
        try Data(#"{"schemaVersion": 1, "publishers": {}, "plugins": []}"#.utf8).write(to: file)
        let client = PluginRegistryClient(url: file, cacheDirectory: root.appendingPathComponent("cache"), maximumAge: 0)
        let first = try await client.snapshot()
        #expect(first.document.plugins.isEmpty && first.staleReason == nil)
        try FileManager.default.removeItem(at: file)
        let second = try await client.snapshot(force: true)
        #expect(second.staleReason != nil)
        #expect(second.document == first.document)
    }

    // MARK: Archives

    private func archive(id: String = "bashcut.demo", version: String = "1.0.0", extraLink: Bool = false) throws -> (URL, String) {
        let source = root.appendingPathComponent("src/\(UUID().uuidString)/demo")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let manifest = PluginManifest(
            id: id, name: "Demo", version: version, entrypoint: "bin/provider", capabilities: ["audio.beats"])
        try JSONEncoder().encode(manifest).write(to: source.appendingPathComponent("plugin.json"))
        let entrypoint = source.appendingPathComponent("bin/provider")
        try Data("#!/bin/sh\n".utf8).write(to: entrypoint)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entrypoint.path)
        if extraLink {
            try FileManager.default.createSymbolicLink(
                at: source.appendingPathComponent("secrets"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        }
        let zip = root.appendingPathComponent("\(UUID().uuidString).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", source.path, zip.path]
        try process.run()
        process.waitUntilExit()
        return (zip, try PluginArchiveInstaller.sha256(of: zip))
    }

    private func installer() -> PluginArchiveInstaller {
        PluginArchiveInstaller(stagingParent: root.appendingPathComponent("Plugins"), allowFileURLs: true)
    }

    @Test("A matching archive is staged under the plugin id without running anything")
    func stage() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (zip, sha) = try archive()
        let entry = PluginRegistryEntry(id: "bashcut.demo", name: "Demo", versions: [])
        let staged = try await installer().stage(entry, version: version("1.0.0", url: zip.absoluteString, sha256: sha))
        #expect(staged.plugin.id == "bashcut.demo")
        #expect(staged.plugin.directory.lastPathComponent == "bashcut.demo")
        #expect(FileManager.default.isExecutableFile(atPath: staged.plugin.directory.appendingPathComponent("bin/provider").path))
        staged.discard()
        #expect(!FileManager.default.fileExists(atPath: staged.stagingRoot.path))
    }

    @Test("Wrong checksum, id, version, links or source are refused")
    func refusals() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = PluginRegistryEntry(id: "bashcut.demo", name: "Demo", versions: [])
        let (zip, sha) = try archive()
        await #expect(throws: PluginError.self) {
            try await installer().stage(entry, version: version("1.0.0", url: zip.absoluteString, sha256: "deadbeef"))
        }
        await #expect(throws: PluginError.self) {
            try await installer().stage(entry, version: version("2.0.0", url: zip.absoluteString, sha256: sha))
        }
        let other = PluginRegistryEntry(id: "bashcut.other", name: "Other", versions: [])
        await #expect(throws: PluginError.self) {
            try await installer().stage(other, version: version("1.0.0", url: zip.absoluteString, sha256: sha))
        }
        let (linked, linkedSHA) = try archive(extraLink: true)
        await #expect(throws: PluginError.self) {
            try await installer().stage(entry, version: version("1.0.0", url: linked.absoluteString, sha256: linkedSHA))
        }
        let strict = PluginArchiveInstaller(stagingParent: root)
        await #expect(throws: PluginError.self) {
            try await strict.stage(entry, version: version("1.0.0", url: "http://github.com/a.zip", sha256: sha))
        }
        await #expect(throws: PluginError.self) {
            try await strict.stage(entry, version: version("1.0.0", url: "https://evil.example/a.zip", sha256: sha))
        }
        // Nothing is left behind in the plugin root.
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Plugins").path)) ?? []
        #expect(leftovers.isEmpty)
    }
}
