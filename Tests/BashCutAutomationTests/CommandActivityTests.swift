import BashCutAutomation
import BashCutProject
import Testing

/// The agent button and run panel (#534) learn what an agent does from its requests, not from anything it reports.
@MainActor struct CommandActivityTests {
    @Test("An agent's requests are reported as they start and end, with the job a command started; anonymous reads are not")
    func reportsAgentRequests() async {
        let registry = CommandRegistry()
        var events: [CommandActivity] = []
        registry.onActivity = { events.append($0) }
        registry.register("context.get") { _, _ in .null }
        registry.register("voice.speak") { _, _ in .object(["job": .string("j1"), "state": .string("running")]) }
        registry.register("timeline.undo") { _, _ in throw RPCFailure(-32602, "Nothing to undo") }
        let token = registry.issueToken(author: .claude)
        _ = await registry.handle(RPCRequest(method: "context.get"))
        #expect(events.isEmpty)
        _ = await registry.handle(RPCRequest(method: "voice.speak", params: ["text": .string("Hi")], token: token))
        #expect(events.count == 2)
        #expect(events[0].finished == nil && events[0].method == "voice.speak" && events[0].author == .claude)
        #expect(events[1].finished == true && events[1].job == "j1" && events[1].id == events[0].id)
        _ = await registry.handle(RPCRequest(method: "timeline.undo", params: ["baseRev": .integer(0)], token: token))
        #expect(events.last?.finished == false && events.last?.error?.contains("Nothing to undo") == true)
        #expect(events.last?.mode == .edit)
    }

    @Test("The run panel's UI actions exist for ui action")
    func runActions() {
        for id in ["run.toggle", "run.stop", "run.follow"] { #expect(UIAction.matching(id).count == 1) }
    }
}
