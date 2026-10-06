import BashCutPlugin
import BashCutProject
import Foundation
import Testing

@testable import BashCutPlugins

/// A session plugin (Python standard library) with a view and a capability: `view.render` streams a render event,
/// calls `voice.speak` on the host and answers with a tree that echoes what it received; `image.test` writes a file
/// into its `outputDirectory`; `plugin.action` calls the host too.
private let viewScript = #"""
#!/usr/bin/env python3
import json, os, sys

def send(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()

def call(rid, method, params):
    send({"type": "call", "id": rid, "callId": "c-" + rid, "method": method, "params": params})
    for reply in sys.stdin:
        answer = json.loads(reply)
        if answer.get("type") == "callResult":
            return answer

for line in sys.stdin:
    message = json.loads(line)
    kind = message.get("type")
    if kind == "hello":
        send({"type": "hello", "apiVersion": 8, "features": message.get("features")})
    elif kind == "shutdown":
        break
    elif kind == "request":
        rid, method, params = message["id"], message["method"], message["params"]
        if method in ("view.render", "view.event"):
            send({"type": "event", "id": rid, "event": {"kind": "render", "body": [{"type": "progress", "label": "Working"}]}})
            answer = call(rid, "voice.speak", {"text": "Xin chao", "keepTakes": True})
            event = params.get("event") or {}
            send({"id": rid, "result": {
                "title": params["view"], "state": {"count": ((params.get("state") or {}).get("count") or 0) + 1},
                "body": [
                    {"type": "text", "text": json.dumps({"method": method, "event": event, "values": params.get("values"),
                                                         "host": answer.get("result")})},
                    {"type": "textField", "id": "query", "value": "warm"},
                    {"type": "button", "id": "go", "title": "Go"},
                ]}})
        elif method == "image.test":
            folder = params["outputDirectory"]
            with open(os.path.join(folder, "out.txt"), "w") as handle:
                handle.write("done")
            send({"id": rid, "result": {"path": os.path.join(folder, "out.txt"), "options": params.get("options")}})
        elif method == "plugin.action":
            answer = call(rid, "timeline.get", {})
            send({"id": rid, "result": {"message": "ok", "data": {"host": answer.get("result")}}})
        else:
            send({"id": rid, "error": {"code": "unknown", "message": method}})
"""#

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func add(_ value: String) { lock.withLock { values.append(value) } }
    var all: [String] { lock.withLock { values } }
}

@Suite("Plugin views and invoke (API 8)")
struct PluginViewServiceTests {
    private struct Fixture {
        let root: URL
        let service: CapabilityService
    }

    /// The views plugin, plus optionally a plugin that requires a missing one.
    private func fixture(requiresMissing: Bool = false) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("views-\(UUID().uuidString)")
        func install(_ manifest: PluginManifest) throws {
            let directory = root.appendingPathComponent("user/\(manifest.id)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let entrypoint = directory.appendingPathComponent("provider.py")
            try Data(viewScript.utf8).write(to: entrypoint)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entrypoint.path)
            try manifest.validate()
            try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))
        }
        try install(PluginManifest(
            id: "app.bashcut.views", name: "Views", version: "1.0.0", apiVersion: 8, entrypoint: "provider.py",
            capabilities: ["image.test"],
            providers: [PluginProvider(id: "app.bashcut.views.image", capability: "image.test", name: "Image")],
            transport: .session,
            contributes: PluginContributions(
                container: PluginContainerContribution(icon: "star"),
                views: [PluginViewContribution(id: "main", title: "Main")]),
            uses: ["voice.synthesize"]))
        if requiresMissing {
            try install(PluginManifest(
                id: "app.bashcut.needy", name: "Needy", version: "1.0.0", apiVersion: 8, entrypoint: "provider.py",
                capabilities: ["image.test"],
                providers: [PluginProvider(id: "app.bashcut.needy.image", capability: "image.test", name: "Needy", priority: 50)],
                transport: .session, requires: [PluginRequirement(id: "app.bashcut.gone", version: ">=1.0.0")]))
        }
        var service = CapabilityService(
            roots: PluginRoots(user: root.appendingPathComponent("user"), bundled: nil),
            transport: PluginRouter(session: PluginSessionTransport(requestTimeout: 10)))
        service.optionValues = { _ in ["mode": .string("test")] }
        return Fixture(root: root, service: service)
    }

    private func plugin(_ fixture: Fixture, _ id: String = "app.bashcut.views") throws -> InstalledPlugin {
        try #require(fixture.service.catalog(projectRoot: nil).plugins.first { $0.id == id })
    }

    @Test("A view request streams renders, calls the host and returns a tree with state")
    func render() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let calls = Recorder()
        let events = Recorder()
        let host = PluginHostChannel(event: { events.add($0.object["kind"]?.string ?? "") }, call: { method, params in
            calls.add(method)
            return .success(.object(["takes": .integer(params.object["text"] == nil ? 0 : 1)]))
        })
        let result = try await fixture.service.view(
            "view.event",
            params: ["view": .string("main"), "state": .object(["count": .integer(2)]),
                     "values": .object(["query": .string("cold")]),
                     "event": PluginViewEvent(node: "go", kind: .click).json],
            plugin: try plugin(fixture), host: host)
        let tree = try PluginViewTree(parsing: result)
        #expect(tree.title == "main")
        #expect(tree.state == .object(["count": .integer(3)]))
        #expect(tree.node("go")?.kind == .button)
        let echoed = try JSONDecoder().decode(JSONValue.self, from: Data((tree.body.first?.string("text") ?? "").utf8))
        #expect(echoed.object["method"]?.string == "view.event")
        #expect(echoed.object["event"]?.object["node"]?.string == "go")
        #expect(echoed.object["values"]?.object["query"]?.string == "cold")
        #expect(echoed.object["host"]?.object["takes"]?.int == 1)
        #expect(calls.all == ["voice.speak"])
        #expect(events.all == ["render"])
        await PluginSessionTransport.shared.stopAll()
    }

    @Test("Invoke runs a capability raw, with options and a fresh output folder")
    func invoke() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("out", isDirectory: true)
        let result = try await fixture.service.invoke(
            "image.test", provider: nil, params: ["text": .string("x")], projectRoot: nil, outputRoot: output)
        #expect(result.object["plugin"]?.string == "app.bashcut.views")
        let inner = result.object["result"]?.object ?? [:]
        #expect(inner["options"]?.object["mode"]?.string == "test")
        let path = try #require(inner["path"]?.string)
        #expect(path.hasPrefix(output.path + "/"))
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "done")
        await #expect(throws: (any Error).self) {
            try await fixture.service.invoke(
                "agent.chat", provider: nil, params: [:], projectRoot: nil, outputRoot: output)
        }
        await PluginSessionTransport.shared.stopAll()
    }

    @Test("A provider whose requirements fail is never chosen")
    func requirementsGateProviders() async throws {
        let fixture = try fixture(requiresMissing: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        // The needy provider has the higher priority but needs a plugin that is not installed.
        let resolved = try await fixture.service.resolve("image.test", preferredProvider: nil, projectRoot: nil)
        #expect(resolved.plugin.id == "app.bashcut.views")
        let preferred = try? await fixture.service.resolve(
            "image.test", preferredProvider: "app.bashcut.needy.image", projectRoot: nil)
        #expect(preferred?.plugin.id != "app.bashcut.needy")
        await PluginSessionTransport.shared.stopAll()
    }

    @Test("Session actions of API 8 plugins get the host channel")
    func actionHost() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let calls = Recorder()
        let host = PluginHostChannel(event: { _ in }, call: { method, _ in
            calls.add(method)
            return .success(.object(["rev": .integer(4)]))
        })
        let adapter = PluginActionCapability(
            action: "app.bashcut.views.go", params: [:], options: [:], context: .object([:]), projectRoot: nil,
            outputRoot: nil)
        let proposal = try await fixture.service.runContribution(
            adapter, plugin: try plugin(fixture), contributionID: "app.bashcut.views.go", host: host)
        #expect(calls.all == ["timeline.get"])
        #expect(proposal.result.object["host"]?.object["rev"]?.int == 4)
        await PluginSessionTransport.shared.stopAll()
    }
}
