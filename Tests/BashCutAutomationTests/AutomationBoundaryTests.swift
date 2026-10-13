import BashCutProject
import Foundation
import Testing

@testable import BashCutAutomation

@MainActor struct AutomationBoundaryTests {
    @Test("Every non-read command rejects missing, invalid and revoked tokens before calling its handler")
    func tokenBoundary() async {
        let registry = CommandRegistry()
        var calls = 0
        for spec in CommandCatalog.specs { registry.register(spec.name) { _, _ in calls += 1; return .null } }
        let revoked = registry.issueToken(author: .external)
        registry.revoke(revoked)
        for spec in CommandCatalog.specs where spec.mode != .read {
            for token in [nil, "invalid", revoked] {
                let response = await registry.handle(RPCRequest(method: spec.name, token: token))
                #expect(response.error?.code == -32001, "\(spec.name) must require a live token")
            }
        }
        #expect(calls == 0)
    }

    @Test("UI responses cannot cross the project-switch read gate")
    func projectGate() async {
        let registry = CommandRegistry()
        var calls = 0
        registry.register("ui.respond") { _, author in
            #expect(author == .external)
            calls += 1
            return .bool(true)
        }
        registry.register("context.get") { _, _ in .null }
        let token = registry.issueToken(author: .external)
        let request = RPCRequest(method: "ui.respond", params: ["option": .string("undo")], token: token)
        registry.projectSwitched(to: "New project")
        #expect(await registry.handle(request).error?.code == -32002)
        #expect(calls == 0)
        _ = await registry.handle(RPCRequest(method: "context.get", token: token))
        #expect(await registry.handle(request).result == .bool(true))
        #expect(calls == 1)
    }

    @Test("Transcript exports reject traversal, sibling prefixes and symlink escapes")
    func outputPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        let outside = root.appendingPathComponent("project-other")
        for folder in [project, outside] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("escape"), withDestinationURL: outside)
        let expected = project.appendingPathComponent("chat.md").resolvingSymlinksInPath()
        #expect(try AutomationOutputPath.resolve("chat.md", projectRoot: project) == expected)
        for path in ["../outside.md", outside.appendingPathComponent("chat.md").path, "escape/chat.md", ""] {
            #expect(throws: RPCFailure.self) { try AutomationOutputPath.resolve(path, projectRoot: project) }
        }
        #expect(throws: RPCFailure.self) { try AutomationOutputPath.resolve("chat.md", projectRoot: nil) }
    }

    @Test("A track argument may name the layer by its short label; IDs and unknown values pass through")
    func trackLabels() async {
        let registry = CommandRegistry()
        let project = Project(name: "Labels")
        registry.resolveTrack = { project.resolveTrackReference($0) }
        var tracks: [String] = []
        registry.register("layers.set") { arguments, _ in
            tracks.append(try arguments.string("track"))
            return .null
        }
        let token = registry.issueToken(author: .agent)
        for track in ["A1", "v2", "t1", "V9"] {
            let request = RPCRequest(
                method: "layers.set", params: ["track": .string(track), "locked": .bool(true), "baseRev": .integer(0)],
                token: token)
            #expect(await registry.handle(request).error == nil)
        }
        #expect(tracks == ["a1", "v2", "t1", "V9"])
        let labels = TimelineSummary.json(project).object["tracks"]?.array.compactMap { $0.object["label"]?.string }
        #expect(labels == ["V1", "V2", "V3", "A1", "A2", "A3", "A4"])
    }

    @Test("baseRev last is the revision as of the caller's last command; anyone else's edit since makes it stale")
    func lastRevision() async {
        let registry = CommandRegistry()
        var revision = 4
        registry.currentRevision = { revision }
        var seen: [Int] = []
        registry.register("timeline.undo") { arguments, _ in
            let base = try arguments.int("baseRev")
            seen.append(base)
            guard base == revision else { throw RPCFailure(-32002, "stale") }
            revision += 1
            return .null
        }
        registry.register("context.get") { _, _ in .null }
        let token = registry.issueToken(author: .agent)
        let undo = RPCRequest(method: "timeline.undo", params: ["baseRev": .string("last")], token: token)
        #expect(await registry.handle(undo).error?.code == -32602, "nothing seen yet")
        _ = await registry.handle(RPCRequest(method: "context.get", token: token))
        #expect(await registry.handle(undo).error == nil)
        #expect(await registry.handle(undo).error == nil, "its own edit moved the revision it saw")
        revision += 1
        #expect(await registry.handle(undo).error?.code == -32002, "someone else edited since")
        #expect(seen == [4, 5, 6])
    }

    @Test("A background relink (converted footage) carries baseRev last forward for callers who had caught up")
    func lastRevisionAfterBackgroundBump() async {
        let registry = CommandRegistry()
        var revision = 4
        registry.currentRevision = { revision }
        registry.register("timeline.undo") { arguments, _ in
            guard try arguments.int("baseRev") == revision else { throw RPCFailure(-32002, "stale") }
            revision += 1
            return .null
        }
        registry.register("context.get") { _, _ in .null }
        let current = registry.issueToken(author: .agent), behind = registry.issueToken(author: .claude)
        _ = await registry.handle(RPCRequest(method: "context.get", token: behind))
        revision += 1
        _ = await registry.handle(RPCRequest(method: "context.get", token: current))
        registry.carrySeenRevisions(from: revision, to: revision + 1)
        revision += 1
        let undo = { token in RPCRequest(method: "timeline.undo", params: ["baseRev": .string("last")], token: token) }
        #expect(await registry.handle(undo(current)).error == nil, "the conversion bump is not an edit it missed")
        #expect(await registry.handle(undo(behind)).error?.code == -32002, "it missed a real edit before the bump")
    }
}
