import BashCutAutomation
import BashCutProject
import Testing

@MainActor struct ChatCommandSessionTests {
    @Test("Disabling edits revokes the live chat token; reads continue and re-enabling creates a new token")
    func preference() async {
        let registry = CommandRegistry()
        let session = ChatCommandSession()
        var edits = 0
        registry.register("timeline.undo") { _, _ in edits += 1; return .null }
        registry.register("context.get") { _, _ in .null }
        let params: [String: JSONValue] = ["baseRev": .integer(0)]
        #expect(await session.perform("timeline.undo", params: params, allowEdits: true, registry: registry).error == nil)
        #expect(await session.perform("timeline.undo", params: params, allowEdits: false, registry: registry).error?.code == -32001)
        #expect(edits == 1)
        #expect(await session.perform("context.get", params: [:], allowEdits: false, registry: registry).error == nil)
        #expect(await session.perform("timeline.undo", params: params, allowEdits: true, registry: registry).error == nil)
        registry.projectSwitched(to: "Other project")
        #expect(await session.perform("timeline.undo", params: params, allowEdits: true, registry: registry).error?.code == -32002)
        session.revoke(in: registry)
        #expect(await session.perform("timeline.undo", params: params, allowEdits: false, registry: registry).error?.code == -32001)
        #expect(edits == 2)
    }

    @Test("Every allowed method exists; plugin administration and generic UI escape routes stay unavailable")
    func allowList() async {
        let registry = CommandRegistry()
        let session = ChatCommandSession()
        for method in ChatCommandSession.allowedMethods {
            #expect(CommandCatalog.spec(named: method) != nil, "Unknown method: \(method)")
        }
        for method in ["plugins.option", "plugins.run", "plugins.set", "plugins.remove", "plugins.install",
                       "plugins.setup", "plugins.proposal", "knowledge.skill", "knowledge.approve",
                       "knowledge.reject", "knowledge.revert", "skills.save", "skills.enable", "skills.disable",
                       "skills.remove", "storage.clear", "project.open",
                       "project.create", "edl.import", "ui.action", "ui.respond", "ui.open", "chat.send", "future.command"] {
            #expect(await session.perform(method, params: [:], allowEdits: true, registry: registry).error?.code == -32601)
        }
    }
}
