import BashCutPlugin
import BashCutProject
import Foundation
import Testing

@testable import BashCutPlugins

/// A views plugin for timing (Python standard library): `size` components per answer, `calls` host calls first, and
/// `renders` streamed render events.
private let benchScript = #"""
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
        rid, params = message["id"], message["params"]
        bench = (params.get("state") or {})
        for index in range(bench.get("calls", 0)):
            send({"type": "call", "id": rid, "callId": f"c{index}", "method": "context.get", "params": {}})
            for reply in sys.stdin:
                if json.loads(reply).get("type") == "callResult":
                    break
        for index in range(bench.get("renders", 0)):
            send({"type": "event", "id": rid, "event": {"kind": "render", "body": [{"type": "progress", "value": index / 100}]}})
        size = bench.get("size", 10)
        items = [{"id": f"i{index}", "title": f"Item {index}", "subtitle": "Subtitle text"} for index in range(min(size // 2, 500))]
        body = [{"type": "text", "text": f"Line {index} " * 6} for index in range(size - len(items) // 1 - 1)] if size > len(items) + 1 else []
        body.append({"type": "list", "id": "list", "items": items})
        send({"id": rid, "result": {"body": body, "state": bench}})
"""#

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

/// Times view requests over the session transport (#390 bench). Runs only with BASHCUT_PERF=1.
@Suite("Plugin view session performance", .enabled(if: ProcessInfo.processInfo.environment["BASHCUT_PERF"] == "1"))
struct PluginViewSessionPerfTests {
    private static func percentile(_ samples: [Double], _ fraction: Double) -> Double {
        let sorted = samples.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
    }

    @Test("Round trips: small and largest views, host calls, streamed renders")
    func roundTrips() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("views-perf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("user/app.bashcut.bench", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entrypoint = directory.appendingPathComponent("provider.py")
        try Data(benchScript.utf8).write(to: entrypoint)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entrypoint.path)
        let manifest = PluginManifest(
            id: "app.bashcut.bench", name: "Bench", version: "1.0.0", apiVersion: 8, entrypoint: "provider.py",
            capabilities: [], transport: .session,
            contributes: PluginContributions(
                container: PluginContainerContribution(icon: "star"), views: [PluginViewContribution(id: "main", title: "Main")]))
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))
        let service = CapabilityService(
            roots: PluginRoots(user: root.appendingPathComponent("user"), bundled: nil),
            transport: PluginRouter(session: PluginSessionTransport(requestTimeout: 30)))
        let plugin = try #require(service.catalog(projectRoot: nil).plugins.first)
        let renders = Counter()
        let host = PluginHostChannel(event: { _ in renders.add() }, call: { _, _ in .success(.object(["rev": .integer(1)])) })

        func run(_ bench: [String: JSONValue], times: Int) async throws -> [Double] {
            var samples: [Double] = []
            for _ in 0..<times {
                let start = DispatchTime.now().uptimeNanoseconds
                let result = try await service.view(
                    "view.render", params: ["view": .string("main"), "state": .object(bench)], plugin: plugin, host: host)
                _ = try PluginViewTree(parsing: result)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            return samples
        }
        _ = try await run(["size": .integer(10)], times: 3)  // starts the process
        let small = try await run(["size": .integer(10)], times: 50)
        let large = try await run(["size": .integer(1999)], times: 20)
        let calls = try await run(["size": .integer(10), "calls": .integer(20)], times: 10)
        let streamed = try await run(["size": .integer(10), "renders": .integer(200)], times: 5)
        print(String(
            format: "[perf] view round trip: 10 components p50 %.1f ms p95 %.1f ms; 2000 components p50 %.1f ms p95 %.1f ms; "
                + "20 host calls p50 %.1f ms (%.2f ms per call); 200 streamed renders p50 %.1f ms (%d delivered)",
            Self.percentile(small, 0.5), Self.percentile(small, 0.95), Self.percentile(large, 0.5),
            Self.percentile(large, 0.95), Self.percentile(calls, 0.5),
            (Self.percentile(calls, 0.5) - Self.percentile(small, 0.5)) / 20, Self.percentile(streamed, 0.5),
            renders.count))
        #expect(Self.percentile(small, 0.5) < 20)
        #expect(Self.percentile(large, 0.5) < 150)
        await PluginSessionTransport.shared.stopAll()
    }
}
