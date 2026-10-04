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
}
