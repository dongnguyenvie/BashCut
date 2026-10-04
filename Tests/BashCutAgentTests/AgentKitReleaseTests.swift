import BashCutPlugin
import CryptoKit
import Foundation
import Testing

@testable import BashCutAgent

@Suite("Agent kit releases")
struct AgentKitReleaseTests {
    private let key = Curve25519.Signing.PrivateKey()
    private var publicKey: String { "ed25519:" + key.publicKey.rawRepresentation.base64EncodedString() }

    private func temporaryFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    private func makeKit(at root: URL, version: String) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
        try Data(#"{"name":"bashcut","version":"\#(version)"}"#.utf8).write(to: root.appendingPathComponent(".claude-plugin/plugin.json"))
        let skill = root.appendingPathComponent("skills/bashcut-one", isDirectory: true)
        try manager.createDirectory(at: skill, withIntermediateDirectories: true)
        try Data("---\nname: bashcut-one\n---\n".utf8).write(to: skill.appendingPathComponent("SKILL.md"))
        return root
    }

    /// A zipped `bashcut-agent-kit/` folder and its release entry, signed with `signer` (nil: unsigned).
    private func publish(
        _ version: String, in root: URL, archiveVersion: String? = nil, signer: Curve25519.Signing.PrivateKey?,
        prepare: (URL) throws -> Void = { _ in }
    ) throws -> AgentKitRelease {
        let staged = root.appendingPathComponent("stage-\(UUID().uuidString)/bashcut-agent-kit")
        try makeKit(at: staged, version: archiveVersion ?? version)
        try prepare(staged)
        let archive = root.appendingPathComponent("kit-\(version)-\(UUID().uuidString).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", staged.path, archive.path]
        try process.run()
        process.waitUntilExit()
        let digest = try PluginArchiveInstaller.sha256(of: archive)
        let signature = try signer.map { try PluginSignature.sign(digest: digest, privateKey: $0.rawRepresentation) }
        return AgentKitRelease(version: version, url: archive.absoluteString, sha256: digest, signature: signature,
                               size: (try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int))
    }

    private func updater(_ support: URL) -> AgentKitUpdater {
        AgentKitUpdater(support: support, catalogURL: support.appendingPathComponent("releases.json"),
                        firstPartyKeys: [publicKey], allowFileURLs: true)
    }

    @Test("The newest compatible, non-withdrawn release newer than the current kit is offered")
    func selection() {
        func release(_ version: String, min: String = "0.0.1", yanked: String? = nil) -> AgentKitRelease {
            AgentKitRelease(version: version, minAppVersion: min, url: "https://github.com/x", sha256: "", signature: nil, yanked: yanked)
        }
        let catalog = AgentKitReleaseCatalog(versions: [
            release("0.0.5", min: "9.0.0"), release("0.0.4", yanked: "broken"), release("0.0.3"), release("0.0.2"),
        ])
        #expect(catalog.update(from: "0.0.2", appVersion: "1.0.0")?.version == "0.0.3")
        #expect(catalog.update(from: "0.0.3", appVersion: "1.0.0") == nil)
        #expect(catalog.update(from: "0.0.2", appVersion: "")?.version == "0.0.5") // development build
    }

    @Test("A signed release installs into agent-kits and replaces older downloads")
    func install() async throws {
        let support = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: support) }
        let updater = updater(support)
        let first = try await updater.install(try publish("0.0.2", in: support, signer: key))
        #expect(first.source == .downloaded && first.version == "0.0.2")
        let second = try await updater.install(try publish("0.0.3", in: support, signer: key))
        #expect(second.root.lastPathComponent == "0.0.3")
        #expect(AgentKitUpdater.downloaded(in: support).map(\.version) == ["0.0.3"])
    }

    @Test("Unsigned, wrongly signed, tampered, mislabelled and escaping archives are refused", arguments: [
        "unsigned", "other-key", "checksum", "version", "link",
    ])
    func refused(_ kind: String) async throws {
        let support = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: support) }
        var release: AgentKitRelease
        switch kind {
        case "unsigned": release = try publish("0.0.2", in: support, signer: nil)
        case "other-key": release = try publish("0.0.2", in: support, signer: Curve25519.Signing.PrivateKey())
        case "version": release = try publish("0.0.2", in: support, archiveVersion: "0.0.9", signer: key)
        case "link":
            release = try publish("0.0.2", in: support, signer: key) { folder in
                try FileManager.default.createSymbolicLink(
                    atPath: folder.appendingPathComponent("skills/outside").path, withDestinationPath: "/etc")
            }
        default:
            let valid = try publish("0.0.2", in: support, signer: key)
            let digest = String(repeating: "0", count: 64)
            release = AgentKitRelease(version: "0.0.2", url: valid.url, sha256: digest,
                                      signature: try PluginSignature.sign(digest: digest, privateKey: key.rawRepresentation))
        }
        await #expect(throws: (any Error).self) { _ = try await updater(support).install(release) }
        #expect(AgentKitUpdater.downloaded(in: support).isEmpty)
    }

    @Test("Archives come over HTTPS from GitHub only")
    func sources() throws {
        let updater = AgentKitUpdater(support: FileManager.default.temporaryDirectory)
        try updater.checkSource(URL(string: "https://github.com/dongnguyenvie/bashcut-agent-kit/releases/download/v1/a.zip")!)
        #expect(throws: (any Error).self) { try updater.checkSource(URL(string: "http://github.com/a.zip")!) }
        #expect(throws: (any Error).self) { try updater.checkSource(URL(string: "https://example.com/a.zip")!) }
        #expect(throws: (any Error).self) { try updater.checkSource(URL(fileURLWithPath: "/tmp/a.zip")) }
    }

    @Test("A newer download wins over the built-in kit, the built-in kit wins ties, a chosen folder wins over both")
    func locate() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Resources")
        try makeKit(at: resources.appendingPathComponent("AgentKit"), version: "0.0.2")
        let support = root.appendingPathComponent("Support")
        try makeKit(at: support.appendingPathComponent("agent-kits/0.0.2"), version: "0.0.2")
        #expect(AgentKit.locate(folder: nil, resources: resources, support: support)?.source == .bundled)
        try makeKit(at: support.appendingPathComponent("agent-kits/0.0.3"), version: "0.0.3")
        let newest = try #require(AgentKit.locate(folder: nil, resources: resources, support: support))
        #expect(newest.source == .downloaded && newest.version == "0.0.3")
        let folder = try makeKit(at: root.appendingPathComponent("checkout"), version: "0.0.1")
        #expect(AgentKit.locate(folder: folder, resources: resources, support: support)?.source == .folder)
        // Agents keep reading one stable copy, whichever kit it came from.
        let stable = try AgentKitInstall(support: support).stableRoot(for: newest)
        #expect(stable.root.lastPathComponent == "agent-kit" && stable.version == "0.0.3" && stable.source == .downloaded)
    }

    @Test("The release list decodes the published shape and refuses another schema")
    func catalog() async throws {
        let support = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: support) }
        let published = #"{"version":"0.0.2","minAppVersion":"0.0.1","url":"https://github.com/a.zip","sha256":"ab","#
            + #""signature":"ed25519:x","size":1,"releasedAt":"2026-10-04","notes":{"en":"Skills"}}"#
        try Data(#"{"schemaVersion":1,"kit":"bashcut","versions":[\#(published)]}"#.utf8)
            .write(to: support.appendingPathComponent("releases.json"))
        #expect(try await updater(support).catalog().versions.first?.notes?["en"] == "Skills")
        try Data(#"{"schemaVersion":2,"kit":"bashcut","versions":[]}"#.utf8).write(to: support.appendingPathComponent("releases.json"))
        await #expect(throws: (any Error).self) { _ = try await updater(support).catalog() }
    }
}
