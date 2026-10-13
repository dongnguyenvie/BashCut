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
        // ui.action only points at media or a library panel (formerly ui.source and ui.panel); plugins may also notify.
        for action in ["open", "notify", "timeline.split", "cmd+b"] {
            let params: [String: JSONValue] = ["action": .string(action), "target": .string("x")]
            #expect(await session.perform("ui.action", params: params, allowEdits: true, registry: registry).error?.code == -32601)
        }
        #expect(ChatCommandSession.allows("ui.action", params: ["action": .string("panel")],
                                          methods: ChatCommandSession.allowedMethods, actions: ChatCommandSession.allowedUIActions))
        #expect(ChatCommandSession.allows("ui.action", params: ["action": .string("notify")],
                                          methods: PluginCommandSession.allowedMethods, actions: PluginCommandSession.allowedUIActions))
    }

    @Test("Plugins set and show only their own options and views; the caller answers plugins.option (#411)")
    @MainActor func ownPluginCalls() async {
        let mine: [String: JSONValue] = ["plugin": .string("example.voice"), "option": .string("voice")]
        let theirs: [String: JSONValue] = ["plugin": .string("other.plugin"), "option": .string("voice")]
        #expect(PluginCommandSession.allowedMethods.contains("plugins.option"))
        // A view's provider picker lists a capability's providers (views-example Voice tab).
        #expect(PluginCommandSession.allowedMethods.contains("capabilities.get"))
        #expect(PluginCommandSession.ownPluginRefusal("plugins.option", params: mine, caller: "example.voice") == nil)
        #expect(PluginCommandSession.ownPluginRefusal("plugins.option", params: theirs, caller: "example.voice") != nil)
        #expect(PluginCommandSession.ownPluginRefusal("plugins.option", params: [:], caller: "example.voice") != nil)
        #expect(PluginCommandSession.ownPluginRefusal("plugins.show-view", params: theirs, caller: "example.voice") != nil)
        #expect(PluginCommandSession.ownPluginRefusal("plugins.set-overlays", params: theirs, caller: "example.voice") != nil)
        #expect(PluginCommandSession.ownPluginRefusal("plugins.set-overlays", params: mine, caller: "example.voice") == nil)
        #expect(PluginCommandSession.ownPluginRefusal("timeline.get", params: theirs, caller: "example.voice") == nil)
        // The session itself never runs it with its plugin token: the generic handler cannot tell which plugin calls.
        let registry = CommandRegistry()
        let session = PluginCommandSession()
        #expect(await session.perform("plugins.option", params: mine, registry: registry).error?.code == -32601)
        #expect(await session.perform("plugins.invoke", params: [:], registry: registry).error?.code == -32601)
    }
}
