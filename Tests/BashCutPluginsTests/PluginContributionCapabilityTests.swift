import BashCutPlugin
import BashCutProject
import Foundation
import Testing

@testable import BashCutPlugins

/// Answers every call with `result` and records the request.
private actor ScriptedTransport: PluginTransport {
    let result: JSONValue
    private(set) var calls: [(method: String, provider: String?, params: JSONValue)] = []

    init(result: JSONValue) { self.result = result }

    func call(plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue) async throws -> JSONValue {
        calls.append((method, provider, params))
        return result
    }

    nonisolated func health(plugin: InstalledPlugin) async -> PluginHealth {
        PluginHealth(pluginID: plugin.id, state: .ready, dependencies: [])
    }
}

@Suite("Plugin actions and hooks")
struct PluginContributionCapabilityTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("contrib-\(UUID().uuidString)")

    private func plugin(_ id: String = "example.toolkit") throws -> InstalledPlugin {
        let directory = root.appendingPathComponent("user/\(id)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entrypoint = directory.appendingPathComponent("provider.sh")
        try Data("#!/bin/sh\n".utf8).write(to: entrypoint)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entrypoint.path)
        let manifest = PluginManifest(
            id: id, name: "Toolkit", version: "1.2.0", apiVersion: 2, entrypoint: "provider.sh",
            capabilities: ["audio.beats"],
            providers: [PluginProvider(id: "\(id).beats", capability: "audio.beats", name: "Beats")],
            contributes: PluginContributions(actions: [
                PluginActionContribution(id: "\(id).grade", title: "Grade", placements: ["menu.plugins"]),
            ]))
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))
        return InstalledPlugin(manifest: manifest, directory: directory)
    }

    private func service(_ transport: some PluginTransport, trust: PluginTrustStore? = nil) -> CapabilityService {
        CapabilityService(
            roots: PluginRoots(user: root.appendingPathComponent("user"), bundled: nil), transport: transport,
            healthTransport: transport, trust: trust)
    }

    @Test("An action sends its parameters and context and returns validated proposed operations")
    func action() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let plugin = try plugin()
        let project = root.appendingPathComponent("project")
        let transport = ScriptedTransport(result: .object([
            "message": .string("Graded 1 clip"), "label": .string("Auto grade"), "baseRev": .integer(7),
            "operations": .array([
                .object(["op": .string("setProperties"), "item": .string("c1"),
                         "patch": .object(["opacity": .number(0.5)])]),
                .object(["op": .string("addMedia"), "media": .object([
                    "id": .string("m9"), "path": .string(project.path + "/generated/plugins/x/out.wav"),
                    "kind": .string("audio"),
                ])]),
            ]),
            "ui": .object(["select": .string("c1"), "seek": .integer(30), "panel": .string("filters")]),
            "data": .object(["score": .number(0.9)]),
        ]))
        let adapter = PluginActionCapability(
            action: "example.toolkit.grade", params: ["mode": .string("vivid")], options: ["strength": .number(1)],
            context: .object(["playhead": .integer(30)]), projectRoot: project, outputRoot: nil)
        let proposal = try await service(transport).runContribution(
            adapter, plugin: plugin, contributionID: "example.toolkit.grade")
        #expect(proposal.label == "Auto grade")
        #expect(proposal.baseRevision == 7)
        #expect(proposal.operations.count == 2)
        // Absolute paths inside the project become project-relative media paths.
        guard case .addMedia(let media) = proposal.operations[1] else { Issue.record("expected addMedia"); return }
        #expect(media.path == "generated/plugins/x/out.wav")
        #expect(proposal.ui.select == "c1")
        #expect(proposal.ui.seek == 30)
        #expect(proposal.ui.panel == "filters")
        #expect(proposal.result == .object(["score": .number(0.9)]))
        #expect(proposal.provenance.providerID == "example.toolkit.grade")
        let call = try #require(await transport.calls.first)
        #expect(call.method == "plugin.action")
        #expect(call.provider == nil)
        #expect(call.params.object["params"] == .object(["mode": .string("vivid")]))
        #expect(call.params.object["options"] == .object(["strength": .number(1)]))
        #expect(call.params.object["context"]?.object["playhead"] == .integer(30))
    }

    @Test("Internal and malformed operations, and files outside the request folder, are rejected")
    func rejects() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let plugin = try plugin()
        for result: JSONValue in [
            .object(["operations": .array([.object(["op": .string("restore"), "project": .object([:])])])]),
            .object(["operations": .array([.object(["op": .string("split")])])]),
            .object(["operations": .string("all")]),
            .object(["files": .array([.string("/etc/hosts")])]),
        ] {
            let adapter = PluginHookCapability(
                event: "export.finished", payload: .object([:]), options: [:], context: .object([:]),
                projectRoot: nil, outputRoot: root.appendingPathComponent("out"))
            await #expect(throws: PluginError.self) {
                try await service(ScriptedTransport(result: result)).runContribution(
                    adapter, plugin: plugin, contributionID: "hook.export.finished")
            }
        }
    }

    @Test("Hooks send the event, payload and an output folder")
    func hook() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let plugin = try plugin()
        let transport = ScriptedTransport(result: .object(["message": .string("noted")]))
        let adapter = PluginHookCapability(
            event: "media.imported", payload: .object(["media": .array([])]), options: [:], context: .object([:]),
            projectRoot: nil, outputRoot: root.appendingPathComponent("out"))
        let proposal = try await service(transport).runContribution(
            adapter, plugin: plugin, contributionID: "hook.media.imported")
        #expect(proposal.message == "noted")
        #expect(!proposal.hasEdits)
        let call = try #require(await transport.calls.first)
        #expect(call.method == "plugin.hook")
        #expect(call.params.object["event"] == .string("media.imported"))
        #expect(call.params.object["outputDirectory"]?.string?.hasPrefix(root.path) == true)
    }

    @Test("pluginData counts as an edit and is size-limited")
    func pluginData() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let plugin = try plugin()
        let adapter = PluginHookCapability(
            event: "export.finished", payload: .object([:]), options: [:], context: .object([:]), projectRoot: nil,
            outputRoot: nil)
        let stored = try await service(ScriptedTransport(result: .object(["pluginData": .object(["exports": .integer(2)])])))
            .runContribution(adapter, plugin: plugin, contributionID: "hook.export.finished")
        #expect(stored.hasEdits)
        #expect(stored.pluginData == .object(["exports": .integer(2)]))
        let huge = JSONValue.string(String(repeating: "x", count: 300 * 1024))
        await #expect(throws: PluginError.self) {
            try await service(ScriptedTransport(result: .object(["pluginData": huge])))
                .runContribution(adapter, plugin: plugin, contributionID: "hook.export.finished")
        }
    }

    @Test("Untrusted or disabled plugins neither provide capabilities nor run contributions")
    func trustGate() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let plugin = try plugin()
        let trust = PluginTrustStore(url: root.appendingPathComponent("trust.json"))
        let service = service(ScriptedTransport(result: .object([:])), trust: trust)
        #expect(service.availability(plugin) == .untrusted)
        let untrusted = await #expect(throws: CapabilityUnavailable.self) {
            try await service.resolve("audio.beats", preferredProvider: nil, projectRoot: nil)
        }
        #expect(untrusted?.report.reason == .notConfigured)
        let adapter = PluginActionCapability(
            action: "example.toolkit.grade", params: [:], options: [:], context: .object([:]), projectRoot: nil,
            outputRoot: nil)
        await #expect(throws: PluginError.self) {
            try await service.runContribution(adapter, plugin: plugin, contributionID: "example.toolkit.grade")
        }
        try trust.trust(plugin)
        #expect(try await service.resolve("audio.beats", preferredProvider: nil, projectRoot: nil).plugin.id == plugin.id)
        _ = try await service.runContribution(adapter, plugin: plugin, contributionID: "example.toolkit.grade")
        try trust.setEnabled(plugin, enabled: false)
        #expect(service.runnablePlugins(projectRoot: nil).isEmpty)
    }
}
