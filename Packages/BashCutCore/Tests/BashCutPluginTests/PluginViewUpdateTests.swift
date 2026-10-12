import BashCutPlugin
import BashCutProject
import Foundation
import Testing

/// A session plugin that pushes view updates outside a request (#409) when asked by `fixture.push`: 30 updates of
/// view `main`, one of a view it does not declare and one too large, then answers.
private let pushScript = #"""
#!/usr/bin/env python3
import json, sys

def send(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()

for line in sys.stdin:
    message = json.loads(line)
    kind = message.get("type")
    if kind == "hello":
        send({"type": "hello", "apiVersion": 8})
    elif kind == "shutdown":
        break
    elif kind == "request":
        for index in range(30):
            send({"type": "viewUpdate", "view": "main", "body": [{"type": "text", "text": f"tick {index}"}]})
        send({"type": "viewUpdate", "view": "other", "body": []})
        send({"type": "viewUpdate", "view": "main", "body": [{"type": "text", "text": "x" * 600000}]})
        send({"id": message["id"], "result": {"ok": True}})
"""#

@Suite("Plugin view updates outside a request")
struct PluginViewUpdateTests {
    private final class Received: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [PluginViewUpdate] = []
        func add(_ value: PluginViewUpdate) { lock.withLock { values.append(value) } }
        var all: [PluginViewUpdate] { lock.withLock { values } }
    }

    @Test("Updates of declared views go to subscribers within the burst; others, oversized and extra ones are dropped")
    func pushes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("push")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("provider.py")
        try Data(pushScript.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let manifest = PluginManifest(
            id: "app.bashcut.push", name: "Push", version: "1.0.0", apiVersion: 8, entrypoint: "provider.py",
            capabilities: [], transport: .session,
            contributes: PluginContributions(views: [PluginViewContribution(id: "main", title: "Main", location: .dock)]))
        let plugin = InstalledPlugin(manifest: manifest, directory: directory)
        let center = PluginViewUpdates()
        let received = Received()
        let subscription = center.subscribe { received.add($0) }
        let transport = PluginSessionTransport(requestTimeout: 10, viewUpdates: center)
        _ = try await transport.call(plugin: plugin, method: "fixture.push", provider: nil, params: .object([:]))
        await transport.stopAll()
        let updates = received.all
        #expect(updates.count == Int(PluginViewUpdateLimiter.burst))
        #expect(updates.allSatisfy { $0.pluginID == "app.bashcut.push" && $0.view == "main" })
        #expect(updates.first?.answer.object["body"]?.array.first?.object["text"]?.string == "tick 0")
        #expect(updates.first?.answer.object["type"] == nil)
        #expect(try PluginViewTree(parsing: #require(updates.first?.answer)).body.count == 1)
        withExtendedLifetime(subscription) {}
    }

    @Test("The limiter refills over time and refuses oversized updates")
    func limiter() {
        var limiter = PluginViewUpdateLimiter()
        let burst = Int(PluginViewUpdateLimiter.burst)
        var allowed = 0
        for _ in 0..<burst where limiter.allow(bytes: 100, now: 0) { allowed += 1 }
        #expect(allowed == burst)
        let empty = limiter.allow(bytes: 100, now: 0)
        let refilled = limiter.allow(bytes: 100, now: 0.1 + 1 / PluginViewUpdateLimiter.perSecond)
        let oversized = limiter.allow(bytes: PluginViewUpdateLimiter.maximumBytes + 1, now: 100)
        #expect(!empty && refilled && !oversized)
        #expect(limiter.dropped == 2)
    }

    @Test("Dropping the subscription stops delivery")
    func unsubscribe() {
        let center = PluginViewUpdates()
        let received = Received()
        var subscription: PluginViewUpdates.Subscription? = center.subscribe { received.add($0) }
        let update = PluginViewUpdate(pluginID: "a.b", view: "main", answer: .object(["body": .array([])]))
        center.post(update)
        #expect(received.all.count == 1 && subscription != nil)
        subscription = nil
        center.post(update)
        #expect(received.all.count == 1)
        #expect(PluginFeature.all.contains("viewUpdate"))
    }
}
