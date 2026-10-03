import BashCutPlugin
import BashCutProject
import Foundation
import Testing

@testable import BashCutPlugins

/// An `agent.chat` session plugin (Python standard library): a turn streams a text event, calls `timeline.get`,
/// and answers with the option values and the call's reply it received.
private let chatScript = #"""
#!/usr/bin/env python3
import json, sys

def send(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()

for line in sys.stdin:
    message = json.loads(line)
    kind = message.get("type")
    if kind == "hello":
        send({"type": "hello", "apiVersion": 4})
    elif kind == "shutdown":
        break
    elif kind == "request":
        rid, params = message["id"], message["params"]
        if params.get("op") == "turn":
            send({"type": "event", "id": rid, "event": {"kind": "text", "delta": "Looking"}})
            send({"type": "call", "id": rid, "callId": "c1", "method": "timeline.get", "params": {}})
            for reply in sys.stdin:
                answer = json.loads(reply)
                if answer.get("type") == "callResult":
                    break
            send({"id": rid, "result": {"stopReason": "end", "options": params.get("options"), "call": answer}})
        else:
            send({"id": rid, "result": {"op": params.get("op")}})
"""#

@Suite("agent.chat capability")
struct AgentChatCapabilityTests {
    @Test("A chat turn carries options, streams events and gets command results back")
    func turn() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("user/app.bashcut.chat", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entrypoint = directory.appendingPathComponent("provider.py")
        try Data(chatScript.utf8).write(to: entrypoint)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entrypoint.path)
        let manifest = PluginManifest(
            id: "app.bashcut.chat", name: "Chat", version: "1.0.0", apiVersion: 4, entrypoint: "provider.py",
            capabilities: ["agent.chat"],
            providers: [PluginProvider(id: "app.bashcut.chat.agent", capability: "agent.chat", name: "Chat")],
            transport: .session,
            options: [PluginOption(id: "apiKey", title: "API key", type: .secret)])
        try manifest.validate()
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))

        let secrets = PluginSecretStore(keychain: false)
        try secrets.write("sk-test", plugin: "app.bashcut.chat", option: "apiKey")
        var service = CapabilityService(
            roots: PluginRoots(user: root.appendingPathComponent("user"), bundled: nil),
            transport: PluginRouter(session: PluginSessionTransport(requestTimeout: 10)))
        service.optionValues = { plugin in ["apiKey": .string(secrets.read(plugin: plugin.id, option: "apiKey"))] }
        let resolved = try await service.resolve("agent.chat", preferredProvider: nil, projectRoot: nil)

        let events = Recorder()
        let host = PluginHostChannel(event: { events.add($0) }, call: { method, _ in
            .success(.object(["method": .string(method)]))
        })
        let result = try await service.chat(["op": .string("turn"), "text": .string("Hi")], using: resolved, host: host)
        #expect(result.object["stopReason"]?.string == "end")
        #expect(result.object["options"]?.object["apiKey"]?.string == "sk-test")
        #expect(result.object["call"]?.object["result"]?.object["method"]?.string == "timeline.get")
        #expect(events.all.first?.object["delta"]?.string == "Looking")

        let reset = try await service.chat(["op": .string("reset")], using: resolved, host: nil)
        #expect(reset.object["op"]?.string == "reset")
        await PluginSessionTransport.shared.stopAll()
    }

    @Test("Secrets are kept per plugin and option; empty deletes")
    func secrets() throws {
        let store = PluginSecretStore(keychain: false)
        #expect(store.read(plugin: "a.b", option: "key").isEmpty)
        try store.write("one", plugin: "a.b", option: "key")
        try store.write("two", plugin: "a.c", option: "key")
        #expect(store.read(plugin: "a.b", option: "key") == "one")
        #expect(store.read(plugin: "a.c", option: "key") == "two")
        try store.write("", plugin: "a.b", option: "key")
        #expect(store.read(plugin: "a.b", option: "key").isEmpty)
    }

    private final class Recorder: @unchecked Sendable {
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
}
