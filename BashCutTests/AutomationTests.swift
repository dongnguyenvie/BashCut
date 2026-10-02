import BashCutProject
import Darwin
import Foundation
import Testing

@testable import BashCutAutomation

@MainActor struct AutomationTests {
    @Test("Roll and slip wire commands preserve frame semantics")
    func advancedTrims() throws {
        let data = Data(
            #"[{"op":"roll","item":"c","edge":"end","toFrame":45},{"op":"slip","item":"c","sourceIn":90}]"#.utf8)
        let edits = try WireOperations.decode(JSONDecoder().decode(JSONValue.self, from: data))
        #expect(edits == [.roll(item: "c", edge: .end, toFrame: 45), .slip(item: "c", sourceIn: 90)])
    }

    @Test("Edit tokens are required, attribute authors, and stop working after revocation")
    func authorization() throws {
        let registry = CommandRegistry()
        var calls = 0
        registry.register("timeline.apply") { _, author in
            #expect(author == .codex)
            calls += 1
            return .integer(1)
        }
        #expect(registry.handle(RPCRequest(method: "timeline.apply")).error?.code == -32001)
        #expect(calls == 0)
        let token = registry.issueToken(author: .codex)
        #expect(
            registry.handle(RPCRequest(method: "timeline.apply", token: token)).result == .integer(1))
        registry.revoke(token)
        #expect(
            registry.handle(RPCRequest(method: "timeline.apply", token: token)).error?.code == -32001)
        #expect(calls == 1)
    }
    @Test("Privileged approval decisions are recorded without command arguments")
    func approvalAudit() {
        let events = EventBox()
        let registry = CommandRegistry { events.append($0) }
        registry.recordApproval(method: "export.start", author: .codex, approved: false)
        registry.recordApproval(method: "export.start", author: .claude, approved: true)
        let recorded = events.value
        #expect(recorded.map(\.method) == ["export.start.denied", "export.start.approved"])
        #expect(recorded.map(\.succeeded) == [false, true])
        #expect(recorded.map(\.author) == [.codex, .claude])
    }
    @Test("Wire operations preserve frame integers and reject malformed edits")
    func wire() throws {
        let data = Data(#"[{"op":"trim","item":"c","edge":"end","toFrame":61,"ripple":true}]"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(
            try WireOperations.decode(value) == [.trim(item: "c", edge: .end, toFrame: 61, ripple: true)])
        #expect(throws: RPCFailure.self) {
            try WireOperations.decode(.array([.object(["op": .string("restore")])]))
        }
    }
    @Test("Project audio settings decode through the agent wire format")
    func projectPropertiesWire() throws {
        let data = Data(
            #"[{"op":"setProjectProperties","patch":{"audio":{"targetLUFS":-14,"normalizeEnabled":true}}}]"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(
            try WireOperations.decode(value) == [
                .setProjectProperties(patch: [
                    "audio": .object(["targetLUFS": .integer(-14), "normalizeEnabled": .bool(true)])
                ])
            ])
    }
    @Test("Beat grids decode through the agent wire format")
    func beatGridWire() throws {
        let data = Data(
            #"[{"op":"setBeatGrid","media":"music","bpm":120.5,"frames":[0,15,30]}]"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(
            try WireOperations.decode(value) == [
                .setBeatGrid(media: "music", bpm: 120.5, frames: [0, 15, 30], provenance: nil)
            ])
    }
    @Test("Section edits decode through the agent wire format")
    func sectionWire() throws {
        let data = Data(
            #"[{"op":"upsertSection","id":"hook","label":"Hook","atFrame":0},{"op":"deleteSection","id":"old"}]"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(
            try WireOperations.decode(value) == [
                .upsertSection(id: "hook", label: "Hook", atFrame: 0),
                .deleteSection(id: "old"),
            ])
    }
    @Test("Linked audio can be assigned or removed through the agent wire format")
    func linkedAudioWire() throws {
        let data = Data(
            #"[{"op":"setLinkedAudio","video":"v","audio":"a"},{"op":"setLinkedAudio","video":"v"}]"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(
            try WireOperations.decode(value) == [
                .setLinkedAudio(video: "v", audio: "a"), .setLinkedAudio(video: "v", audio: nil),
            ])
    }
    @Test("Magnetic reorder decodes an item target or end position")
    func reorderWire() throws {
        let data = Data(
            #"[{"op":"reorder","item":"b","before":"a"},{"op":"reorder","item":"a"}]"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(
            try WireOperations.decode(value) == [
                .reorder(item: "b", before: "a"), .reorder(item: "a", before: nil),
            ])
    }
    @Test("Registered read and UI commands need no token; unknown commands fail")
    func modes() {
        let registry = CommandRegistry()
        for method in [
            "context.get", "project.get", "timeline.get", "media.list", "review.run", "captions.export", "export.status", "ui.select",
            "ui.seek", "ui.notify",
        ] {
            registry.register(method) { _, _ in .bool(true) }
            #expect(registry.handle(RPCRequest(method: method)).result == .bool(true))
        }
        for method in ["timeline.undo", "timeline.redo", "captions.import"] {
            registry.register(method) { _, _ in .bool(true) }
            #expect(registry.handle(RPCRequest(method: method)).error?.code == -32001)
        }
        registry.register("export.start") { _, _ in .bool(true) }
        #expect(registry.handle(RPCRequest(method: "export.start")).error?.code == -32001)
        let token = registry.issueToken(author: .claude)
        #expect(registry.handle(RPCRequest(method: "export.start", token: token)).result == .bool(true))
        #expect(registry.handle(RPCRequest(method: "missing")).error?.code == -32601)
    }
    @Test("Unix socket roundtrip uses mode 0600 and removes the socket at shutdown")
    func socketRoundtrip() async throws {
        // Keep under Darwin's sockaddr_un path limit even on machines with long TMPDIR values.
        let directory = URL(fileURLWithPath: "/tmp/bashcut-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("a.sock").path
        let server = UnixRPCServer()
        try await server.start(path: path) { request in
            RPCResponse(id: request.id, result: .string(request.method))
        }
        do {
            let response = try await Task.detached {
                try UnixRPCClient.call(RPCRequest(method: "context.get"), path: path)
            }.value
            #expect(response.result == .string("context.get"))
            let permissions = try #require(
                FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
            #expect(permissions & 0o777 == 0o600)
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("An idle client does not delay other automation clients")
    func idleClientDoesNotBlock() async throws {
        let directory = URL(fileURLWithPath: "/tmp/bashcut-idle-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("a.sock").path
        let server = UnixRPCServer()
        try await server.start(path: path) { request in
            RPCResponse(id: request.id, result: .string(request.method))
        }
        let idle = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        defer { Darwin.close(idle) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(idle, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(connected == 0)
        try await Task.sleep(for: .milliseconds(200))
        let started = Date()
        let response = try await Task.detached {
            try UnixRPCClient.call(RPCRequest(method: "context.get"), path: path)
        }.value
        #expect(response.result == .string("context.get"))
        #expect(Date().timeIntervalSince(started) < 2)
        await server.stop()
    }

    @Test("MCP bridge forwards structured arguments and the live session token")
    func mcpBridge() async throws {
        let directory = URL(fileURLWithPath: "/tmp/bashcut-mcp-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("a.sock").path
        let server = UnixRPCServer()
        try await server.start(path: path) { request in
            #expect(request.method == "timeline.get")
            #expect(request.params["format"] == .string("text"))
            #expect(request.token == "session-token")
            return RPCResponse(
                id: request.id, result: .object(["revision": .integer(7), "ready": .bool(true)]))
        }
        do {
            let response = try await Task.detached {
                try MCPBridgeClient.call(
                    method: "timeline.get", arguments: Data(#"{"format":"text"}"#.utf8),
                    token: "session-token", path: path)
            }.value
            let value = try JSONDecoder().decode(JSONValue.self, from: response.data)
            #expect(value.object["revision"] == .integer(7))
            #expect(response.text.contains("revision"))
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }
}

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AuditEvent] = []
    func append(_ event: AuditEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }
    var value: [AuditEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
