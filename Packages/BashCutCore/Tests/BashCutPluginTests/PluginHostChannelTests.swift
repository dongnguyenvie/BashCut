import BashCutPlugin
import BashCutProject
import Foundation
import Testing

/// A session plugin (Python standard library) for the API 4 host channel: `fixture.agent` sends two events, calls
/// `timeline.get` and answers with the call's reply; `fixture.slowcall` makes one call and answers when it returns.
private let hostScript = #"""
#!/usr/bin/env python3
import json, sys

def send(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()

def wait_for(call_id):
    for line in sys.stdin:
        message = json.loads(line)
        if message.get("type") == "callResult" and message.get("callId") == call_id:
            return message

for line in sys.stdin:
    message = json.loads(line)
    kind = message.get("type")
    if kind == "hello":
        send({"type": "hello", "apiVersion": 4})
    elif kind == "shutdown":
        break
    elif kind == "request":
        rid, method = message["id"], message["method"]
        if method == "fixture.agent":
            send({"type": "event", "id": rid, "event": {"kind": "text", "delta": "a"}})
            send({"type": "event", "id": rid, "event": {"kind": "text", "delta": "b"}})
            send({"type": "call", "id": rid, "callId": "c1", "method": "timeline.get", "params": {"x": 1}})
            send({"type": "call", "id": rid, "callId": "c2", "method": "bad.command", "params": {}})
            first, second = wait_for("c1"), wait_for("c2")
            send({"id": rid, "result": {"first": first, "second": second}})
        elif method == "fixture.slowcall":
            send({"type": "call", "id": rid, "callId": "s1", "method": "export.start", "params": {}})
            send({"id": rid, "result": wait_for("s1")})
"""#

@Suite("Plugin host channel (API 4)")
struct PluginHostChannelTests {
    private func makePlugin() throws -> (InstalledPlugin, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("host")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("provider.py")
        try Data(hostScript.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let manifest = PluginManifest(
            id: "app.bashcut.host", name: "Host", version: "1.0.0", apiVersion: 4,
            entrypoint: "provider.py", capabilities: ["agent.chat"], transport: .session)
        return (InstalledPlugin(manifest: manifest, directory: directory), root)
    }

    private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [JSONValue] = []
        func add(_ value: JSONValue) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }
        var all: [JSONValue] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    @Test("Events arrive in order and calls get their results or errors")
    func eventsAndCalls() async throws {
        let (plugin, root) = try makePlugin()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PluginSessionTransport(requestTimeout: 10)
        let events = Events()
        let host = PluginHostChannel(event: { events.add($0) }, call: { method, params in
            method == "timeline.get"
                ? .success(.object(["echo": params]))
                : .failure(PluginCallFailure(code: -32601, message: "Unknown command: \(method)"))
        })
        let result = try await transport.call(
            plugin: plugin, method: "fixture.agent", provider: nil, params: .object([:]), progress: nil, host: host)
        #expect(events.all.map { $0.object["delta"]?.string } == ["a", "b"])
        #expect(result.object["first"]?.object["result"]?.object["echo"]?.object["x"]?.int == 1)
        #expect(result.object["second"]?.object["error"]?.object["message"]?.string == "Unknown command: bad.command")
        await transport.stopAll()
    }

    @Test("A request without a host channel cannot call the app")
    func noHost() async throws {
        let (plugin, root) = try makePlugin()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PluginSessionTransport(requestTimeout: 10)
        let result = try await transport.call(
            plugin: plugin, method: "fixture.slowcall", provider: nil, params: .object([:]))
        #expect(result.object["error"]?.object["message"]?.string == "This request cannot call BashCut")
        await transport.stopAll()
    }

    @Test("A running call pauses the silence timeout")
    func callPausesTimeout() async throws {
        let (plugin, root) = try makePlugin()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PluginSessionTransport(requestTimeout: 0.4)
        let host = PluginHostChannel(event: { _ in }, call: { _, _ in
            try? await Task.sleep(for: .milliseconds(1_500))
            return .success(.object(["done": .bool(true)]))
        })
        let result = try await transport.call(
            plugin: plugin, method: "fixture.slowcall", provider: nil, params: .object([:]), progress: nil, host: host)
        #expect(result.object["result"]?.object["done"] == .bool(true))
        await transport.stopAll()
    }

    @Test("Secret options need API 4, user scope and no default; agent.chat needs a session")
    func manifestRules() throws {
        let secret = PluginOption(id: "apiKey", title: "API key", type: .secret)
        let valid = PluginManifest(
            id: "app.bashcut.agent", name: "Agent", version: "1.0.0", apiVersion: 4, entrypoint: "bin/provider",
            capabilities: ["agent.chat"], transport: .session, options: [secret])
        try valid.validate()
        let old = PluginManifest(
            id: "app.bashcut.agent", name: "Agent", version: "1.0.0", apiVersion: 3, entrypoint: "bin/provider",
            capabilities: ["audio.beats"], transport: .session, options: [secret])
        #expect(throws: PluginError.self) { try old.validate() }
        let oneShot = PluginManifest(
            id: "app.bashcut.agent", name: "Agent", version: "1.0.0", apiVersion: 4, entrypoint: "bin/provider",
            capabilities: ["agent.chat"])
        #expect(throws: PluginError.self) { try oneShot.validate() }
        let projectSecret = PluginOption(
            id: "apiKey", title: "API key", type: .secret, scope: .project)
        let scoped = PluginManifest(
            id: "app.bashcut.agent", name: "Agent", version: "1.0.0", apiVersion: 4, entrypoint: "bin/provider",
            capabilities: ["agent.chat"], transport: .session, options: [projectSecret])
        #expect(throws: PluginError.self) { try scoped.validate() }
        #expect(try secret.parse("sk-test") == .string("sk-test"))
    }
}

@Test("A provider without priority decodes with priority 0")
func providerPriorityDefault() throws {
    let data = Data(#"{"id":"a.b.c","capability":"agent.chat","name":"C"}"#.utf8)
    let provider = try JSONDecoder().decode(PluginProvider.self, from: data)
    #expect(provider.priority == 0 && provider.timeoutSeconds == nil)
}
