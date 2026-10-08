import BashCutPlugin
import Foundation
import Testing

@Suite("Plugin registry")
struct PluginRegistryTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("registry-\(UUID().uuidString)")

    private func version(
        _ value: String, api: Int = 2, minApp: String? = nil, platforms: [String]? = nil, url: String = "https://github.com/x.zip",
        sha256: String = "00", signature: String? = nil, yanked: String? = nil
    ) -> PluginRegistryVersion {
        PluginRegistryVersion(
            version: value, apiVersion: api, minAppVersion: minApp, platforms: platforms, url: url, sha256: sha256,
            signature: signature, yanked: yanked)
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

    @Test("Bundles decode in order with their defaults; a malformed one never hides the catalog")
    func bundles() throws {
        let plugins = #""plugins": [{"id": "a.b", "name": "A", "versions": []}]"#
        let json = #"""
            {"schemaVersion": 1, "publishers": {}, \#(plugins), "bundles": [
              {"id": "starter", "name": {"en": "Recommended", "vi": "Gói đề xuất"}, "summary": "Most people need these",
               "plugins": [{"id": "a.b", "default": true}, {"id": "c.d", "default": false}, {"id": "e.f"}]}]}
            """#
        let document = try PluginRegistryClient.decode(Data(json.utf8))
        let bundle = try #require(document.bundle("starter"))
        #expect(bundle.name.text(for: "vi") == "Gói đề xuất")
        #expect(bundle.plugins.map(\.id) == ["a.b", "c.d", "e.f"])
        #expect(bundle.plugins.map(\.checkedByDefault) == [true, false, true])
        let older = try PluginRegistryClient.decode(Data(#"{"schemaVersion": 1, "publishers": {}, \#(plugins)}"#.utf8))
        #expect(older.bundles.isEmpty && older.entry("a.b") != nil)
        let broken = try PluginRegistryClient.decode(
            Data(#"{"schemaVersion": 1, "publishers": {}, \#(plugins), "bundles": [{"id": 3}]}"#.utf8))
        #expect(broken.bundles.isEmpty && broken.entry("a.b") != nil)
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

    @Test("Yanked versions are never offered")
    func yanked() throws {
        let entry = PluginRegistryEntry(id: "a.b", name: "A", versions: [
            version("0.0.1"), version("0.0.2", yanked: "Deletes clips"),
        ])
        #expect(try entry.resolve(appVersion: "1.0.0").get().version == "0.0.1")
        #expect(entry.version("0.0.2")?.yanked == "Deletes clips")
        let allYanked = PluginRegistryEntry(id: "a.b", name: "A", versions: [version("0.0.2", yanked: "Bad")])
        #expect(throws: PluginError.self) { try allYanked.resolve(appVersion: "1.0.0").get() }
    }

    @Test("Signatures: first-party key, a registry publisher key, unsigned, and forgeries")
    func signatures() throws {
        let bashcut = Data(repeating: 1, count: 32)
        let partner = Data(repeating: 2, count: 32)
        let firstParty = [try PluginSignature.publicKey(of: bashcut)]
        let partnerKeys = [try PluginSignature.publicKey(of: partner)]
        let digest = String(repeating: "ab", count: 32)
        let signed = try PluginSignature.sign(digest: digest, privateKey: bashcut)
        #expect(try PluginSignature.verify(
            digest: digest, signature: signed, publisher: "bashcut", registryKeys: [], firstPartyKeys: firstParty) == .firstParty)
        let partnerSigned = try PluginSignature.sign(digest: digest, privateKey: partner)
        #expect(try PluginSignature.verify(
            digest: digest, signature: partnerSigned, publisher: "acme", registryKeys: partnerKeys,
            firstPartyKeys: firstParty) == .verifiedPublisher("acme"))
        #expect(try PluginSignature.verify(
            digest: digest, signature: nil, publisher: "acme", registryKeys: [], firstPartyKeys: firstParty) == .unsigned)
        // A partner key cannot pass as first party, and a signature for another archive is refused.
        #expect(throws: PluginError.self) {
            try PluginSignature.verify(
                digest: digest, signature: partnerSigned, publisher: "bashcut", registryKeys: [], firstPartyKeys: firstParty)
        }
        #expect(throws: PluginError.self) {
            try PluginSignature.verify(
                digest: String(repeating: "cd", count: 32), signature: signed, publisher: "bashcut", registryKeys: [],
                firstPartyKeys: firstParty)
        }
        // The registry cannot list keys for bashcut.
        let document = PluginRegistryDocument(
            publishers: ["bashcut": PluginRegistryPublisher(name: "BashCut", keys: partnerKeys, verified: true)], plugins: [])
        #expect(document.keys(for: "bashcut").isEmpty)
        #expect(PluginSignature.firstPartyKeys.count == 1)
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
        #expect(staged.publisherTrust == .unsigned)
        staged.discard()
        #expect(!FileManager.default.fileExists(atPath: staged.stagingRoot.path))
        let key = Data(repeating: 7, count: 32)
        let signature = try PluginSignature.sign(digest: sha, privateKey: key)
        let signedEntry = PluginRegistryEntry(id: "bashcut.demo", name: "Demo", publisher: "bashcut", versions: [])
        let signed = try await installer().stage(
            signedEntry, version: version("1.0.0", url: zip.absoluteString, sha256: sha, signature: signature),
            firstPartyKeys: [try PluginSignature.publicKey(of: key)])
        #expect(signed.publisherTrust == .firstParty)
        signed.discard()
        await #expect(throws: PluginError.self) {
            try await installer().stage(
                signedEntry, version: version("1.0.0", url: zip.absoluteString, sha256: sha, signature: signature))
        }
        await #expect(throws: PluginError.self) {
            try await installer().stage(
                entry, version: version("1.0.0", url: zip.absoluteString, sha256: sha, yanked: "Broken"))
        }
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

    @Test("The registry cache moves out of Application Support once; a newer copy in Caches wins")
    func migrateLegacyCache() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("Support/Registry"), caches = root.appendingPathComponent("Caches/Registry")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appendingPathComponent("registry.json"))
        try Data("old-meta".utf8).write(to: legacy.appendingPathComponent("registry.meta.json"))
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data("new-meta".utf8).write(to: caches.appendingPathComponent("registry.meta.json"))

        PluginRegistryClient.migrateCache(from: legacy, to: caches)
        #expect(try String(contentsOf: caches.appendingPathComponent("registry.json"), encoding: .utf8) == "old")
        #expect(try String(contentsOf: caches.appendingPathComponent("registry.meta.json"), encoding: .utf8) == "new-meta")
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        // Same folder (tests, custom roots): nothing is removed.
        PluginRegistryClient.migrateCache(from: caches, to: caches)
        #expect(FileManager.default.fileExists(atPath: caches.appendingPathComponent("registry.json").path))
    }
}
