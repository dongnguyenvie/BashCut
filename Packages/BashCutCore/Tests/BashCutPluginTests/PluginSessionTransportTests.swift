import BashCutPlugin
import BashCutProject
import Darwin
import Foundation
import Testing

/// A shell plugin that speaks the session protocol: it answers the handshake, then handles each request line
/// by its `method` (`fixture.echo`, `fixture.fail`, `fixture.crash`, `fixture.hang`, `fixture.slow` reports
/// progress every 0.2 s for 1.2 s, `fixture.quiet` answers after 1 s without progress).
private let sessionScript = #"""
#!/bin/sh
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
  case "$line" in
    *'"type":"hello"'*) echo '{"type":"hello","apiVersion":2}' ;;
    *'"type":"shutdown"'*) exit 0 ;;
    *'"type":"cancel"'*) ;;
    *'fixture.echo'*)
      echo "{\"type\":\"progress\",\"id\":\"$id\",\"progress\":0.5,\"message\":\"half\"}"
      echo "{\"id\":\"$id\",\"result\":{\"pid\":$$}}" ;;
    *'fixture.fail'*) echo "{\"id\":\"$id\",\"error\":{\"code\":\"bad_input\",\"message\":\"nope\"}}" ;;
    *'fixture.crash'*) echo 'boom' >&2; exit 4 ;;
    *'fixture.hang'*) ;;
    *'fixture.slow'*)
      for step in 1 2 3 4 5 6; do sleep 0.2; echo "{\"type\":\"progress\",\"id\":\"$id\"}"; done
      echo "{\"id\":\"$id\",\"result\":{}}" ;;
    *'fixture.quiet'*) sleep 1; echo "{\"id\":\"$id\",\"result\":{}}" ;;
  esac
done
"""#

@Suite("Plugin session transport")
struct PluginSessionTransportTests {
    private func makePlugin(
        script: String = sessionScript, providers: [PluginProvider]? = nil
    ) throws -> (InstalledPlugin, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("provider.sh")
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let manifest = PluginManifest(
            id: "app.bashcut.session", name: "Session", version: "1.0.0", apiVersion: 2,
            entrypoint: "provider.sh", capabilities: ["audio.beats"], providers: providers, transport: .session)
        return (InstalledPlugin(manifest: manifest, directory: directory), root)
    }

    private final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(Double?, String?)] = []
        func add(_ fraction: Double?, _ message: String?) {
            lock.lock()
            values.append((fraction, message))
            lock.unlock()
        }
        var all: [(Double?, String?)] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    @Test("One process answers many requests and reports progress")
    func reuse() async throws {
        let (plugin, root) = try makePlugin()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PluginSessionTransport(requestTimeout: 5)
        let progress = Progress()
        let first = try await transport.call(
            plugin: plugin, method: "fixture.echo", provider: nil, params: .object([:]),
            progress: { progress.add($0, $1) })
        let second = try await transport.call(plugin: plugin, method: "fixture.echo", provider: nil, params: .object([:]))
        #expect(first.object["pid"] != nil)
        #expect(first == second)
        #expect(progress.all.first?.0 == 0.5)
        #expect(progress.all.first?.1 == "half")
        #expect(await transport.running() == ["app.bashcut.session"])
        await transport.stopAll()
        #expect(await transport.running().isEmpty)
    }

    @Test("Plugin errors surface their code and message")
    func errors() async throws {
        let (plugin, root) = try makePlugin()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PluginSessionTransport(requestTimeout: 5)
        await #expect(throws: PluginError.invalid("Plugin error bad_input: nope")) {
            try await transport.call(plugin: plugin, method: "fixture.fail", provider: nil, params: .object([:]))
        }
        await transport.stopAll()
    }

    @Test("A crash fails the request with stderr and the next call restarts the process")
    func crashRestart() async throws {
        let (plugin, root) = try makePlugin()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PluginSessionTransport(requestTimeout: 5)
        let before = try await transport.call(plugin: plugin, method: "fixture.echo", provider: nil, params: .object([:]))
        await #expect(throws: PluginError.invalid("Plugin session ended: boom")) {
            try await transport.call(plugin: plugin, method: "fixture.crash", provider: nil, params: .object([:]))
        }
        let after = try await transport.call(plugin: plugin, method: "fixture.echo", provider: nil, params: .object([:]))
        #expect(before != after)
        await transport.stopAll()
    }

    @Test("Cancelling and timeouts fail only that request")
    func cancelAndTimeout() async throws {
        let (plugin, root) = try makePlugin()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PluginSessionTransport(requestTimeout: 0.4)
        let started = Date()
        await #expect(throws: PluginError.invalid("Plugin request timed out (no progress for 1 s)")) {
            try await transport.call(plugin: plugin, method: "fixture.hang", provider: nil, params: .object([:]))
        }
        #expect(Date().timeIntervalSince(started) < 10)  // generous: process start-up is slow under parallel tests
        let call = Task {
            try await transport.call(plugin: plugin, method: "fixture.hang", provider: nil, params: .object([:]))
        }
        try await Task.sleep(for: .milliseconds(100))
        call.cancel()
        await #expect(throws: PluginError.invalid("Plugin request was cancelled")) { try await call.value }
        // The process survives and still answers.
        _ = try await transport.call(plugin: plugin, method: "fixture.echo", provider: nil, params: .object([:]))
        await transport.stopAll()
    }

    @Test("Progress keeps a request alive past the silence window, up to the total limit")
    func progressExtends() async throws {
        let (plugin, root) = try makePlugin()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PluginSessionTransport(requestTimeout: 0.5)
        _ = try await transport.call(plugin: plugin, method: "fixture.slow", provider: nil, params: .object([:]))
        await transport.stopAll()

        let capped = PluginSessionTransport(requestTimeout: 0.5, maximumRequestDuration: 0.6)
        await #expect(throws: PluginError.invalid("Plugin request ran past its time limit")) {
            try await capped.call(plugin: plugin, method: "fixture.slow", provider: nil, params: .object([:]))
        }
        await capped.stopAll()
    }

    @Test("A provider's timeoutSeconds replaces the silence window")
    func providerTimeout() async throws {
        let provider = PluginProvider(id: "app.bashcut.session.slow", capability: "audio.beats", name: "Slow",
                                      timeoutSeconds: 10)
        let (plugin, root) = try makePlugin(providers: [provider])
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PluginSessionTransport(requestTimeout: 0.4)
        await #expect(throws: PluginError.invalid("Plugin request timed out (no progress for 1 s)")) {
            try await transport.call(plugin: plugin, method: "fixture.quiet", provider: nil, params: .object([:]))
        }
        _ = try await transport.call(plugin: plugin, method: "fixture.quiet", provider: provider.id, params: .object([:]))
        await transport.stopAll()
    }

    @Test("A plugin that never answers the handshake is refused")
    func handshake() async throws {
        let (plugin, root) = try makePlugin(script: "#!/bin/sh\nsleep 30\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PluginSessionTransport(handshakeTimeout: 0.3)
        await #expect(throws: PluginError.invalid("Plugin session did not answer the handshake")) {
            try await transport.call(plugin: plugin, method: "fixture.echo", provider: nil, params: .object([:]))
        }
    }

    @Test("Idle sessions shut down")
    func idle() async throws {
        let (plugin, root) = try makePlugin()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PluginSessionTransport(requestTimeout: 5, idleTimeout: 0.3)
        _ = try await transport.call(plugin: plugin, method: "fixture.echo", provider: nil, params: .object([:]))
        for _ in 0..<100 where !(await transport.running().isEmpty) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(await transport.running().isEmpty)
    }

    @Test("The router sends session plugins over the session transport")
    func router() async throws {
        let (plugin, root) = try makePlugin()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = PluginSessionTransport(requestTimeout: 5)
        let router = PluginRouter(session: session)
        _ = try await router.call(plugin: plugin, method: "fixture.echo", provider: nil, params: .object([:]))
        #expect(await session.running() == ["app.bashcut.session"])
        await session.stopAll()
    }
}
