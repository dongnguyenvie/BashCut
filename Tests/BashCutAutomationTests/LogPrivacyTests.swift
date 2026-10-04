import BashCutProject
import Foundation
import Testing

@testable import BashCutAutomation

struct LogPrivacyTests {
    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ line: String) { lock.withLock { lines.append(line) } }
        var text: String { lock.withLock { lines.joined(separator: "\n") } }
    }

    @Test("RPC success and failure logs omit echoed secrets and user conversation content")
    @MainActor func registryLogs() async {
        let capture = Capture()
        let registry = CommandRegistry(logger: { _, message in capture.append(message) })
        let canary = "secret-canary-never-persist"
        registry.register("plugins.option") { _, _ in throw RPCFailure(-32602, canary) }
        registry.register("chat.send") { _, _ in .string(canary) }
        registry.register("chat.transcript") { _, _ in .string(canary) }
        let token = registry.issueToken(author: .codex)
        let failed = await registry.handle(RPCRequest(method: "plugins.option", params: [
            "plugin": .string("example"), "option": .string("apiKey"), "value": .string(canary)
        ], token: token))
        #expect(failed.error?.message == canary)
        let sent = await registry.handle(RPCRequest(method: "chat.send", params: ["text": .string(canary)], token: token))
        #expect(sent.result == .string(canary))
        let transcript = await registry.handle(RPCRequest(method: "chat.transcript", params: [:]))
        #expect(transcript.result == .string(canary))
        _ = await registry.handle(RPCRequest(method: canary, params: ["unknown": .string(canary)]))
        #expect(capture.text.contains("FAILED"))
        #expect(capture.text.contains("chat.send"))
        #expect(capture.text.contains("[redacted]"))
        #expect(!capture.text.contains(canary))
    }

    @Test("Secret options, chat text, batch operations and unknown fields never enter parameter logs")
    func parameters() throws {
        for (method, field) in [("plugins.option", "value"), ("chat.send", "text"), ("chat.command", "line"),
                                ("timeline.apply", "ops"), ("plugins.run", "params"), ("voice.speak", "text")] {
            let spec = try #require(CommandCatalog.spec(named: method))
            let redacted = spec.logParameters([field: .string("secret-canary"), "unknown": .string("another-secret")])
            #expect(redacted[field] == .string("[redacted]"))
            #expect(redacted["unknown"] == .string("[redacted]"))
        }
        let seek = try #require(CommandCatalog.spec(named: "ui.seek"))
        #expect(seek.logParameters(["frame": .integer(10)])["frame"] == .integer(10))
    }

    @Test("Logs and rotated logs stay owner-only, including a legacy world-readable file")
    func permissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("debug.log")
        DebugLogWriter(url: url, maximumBytes: 10).append("first\n")
        #expect(try mode(url) == 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        DebugLogWriter(url: url, maximumBytes: 10).append("second\n")
        #expect(try mode(url) == 0o600)
        DebugLogWriter(url: url, maximumBytes: 10).append("third\n")
        #expect(try mode(root.appendingPathComponent("debug.1.log")) == 0o600)
        #expect(try String(contentsOf: url, encoding: .utf8) == "third\n")
        try FileManager.default.removeItem(at: url)
        let outside = root.appendingPathComponent("outside")
        try Data("unchanged".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
        DebugLogWriter(url: url, maximumBytes: 10).append("do not write")
        #expect(try String(contentsOf: outside, encoding: .utf8) == "unchanged")
    }

    private func mode(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }
}
