import BashCutAutomation
import BashCutProject
import Testing

@Suite("Plugin action MCP tools")
struct PluginActionToolsTests {
    @Test("Each plugin action becomes a tool with its parameter schema")
    func tools() {
        let schema: JSONValue = .object(["type": .string("object"), "properties": .object([
            "paddingMs": .object(["type": .string("integer"), "default": .integer(100)]),
        ])])
        let actions: JSONValue = .array([
            .object([
                "id": .string("bashcut.silence-markers.remove"), "title": .string("Remove silences in clip…"),
                "plugin": .string("bashcut.silence-markers"), "when": .string("selection && media"),
                "params": schema, "enabled": .bool(false),
            ]),
            .object(["title": .string("No id")]),
        ])
        let tools = PluginActionTools.tools(from: actions)
        #expect(tools.count == 1)
        #expect(tools[0].name == "bashcut_action_bashcut_silence-markers_remove")
        #expect(tools[0].actionID == "bashcut.silence-markers.remove")
        #expect(tools[0].inputSchema == schema)
        #expect(tools[0].description.contains("selection && media"))
        #expect(tools[0].description.contains("Not available"))
    }

    @Test("Tool names stay within MCP's 64 safe characters and remain distinct")
    func longNames() {
        let first = PluginActionTools.name(for: "com.example.a-very-long-plugin-identifier.with.many.parts.action-one")
        let second = PluginActionTools.name(for: "com.example.a-very-long-plugin-identifier.with.many.parts.action-two")
        #expect(first.count <= 64 && second.count <= 64 && first != second)
        #expect(first.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        #expect(PluginActionTools.name(for: "ví.dụ") == "bashcut_action_v__d_")
    }

    @Test("A thousand actions list at most the budget, available and recently run first")
    func budget() {
        let actions: JSONValue = .array((0..<1000).map { index in
            .object([
                "id": .string("example.plugin\(index / 4).action\(index)"), "plugin": .string("example.plugin\(index / 4)"),
                "enabled": .bool(index % 3 != 0),
                "lastRun": index == 999 ? .string("2026-10-05T10:00:00Z") : index == 3 ? .string("2026-10-05T09:00:00Z") : .null,
            ])
        })
        #expect(PluginActionTools.tools(from: actions).count == 1000)
        let listed = PluginActionTools.listed(from: actions)
        #expect(listed.count == PluginActionTools.budget)
        #expect(Set(listed.map(\.name)).count == listed.count)
        // 999 is not available now (999 % 3 == 0), so it waits behind every available action.
        #expect(listed.map(\.actionID).prefix(3) == ["example.plugin0.action1", "example.plugin0.action2", "example.plugin1.action4"])
        #expect(!listed.contains { $0.actionID == "example.plugin249.action999" })
        let few = PluginActionTools.listed(from: actions, budget: 2000)
        #expect(few.count == 1000 && few.first?.actionID == "example.plugin0.action0")
    }

    @Test("Recently run available actions come before other available ones")
    func recentFirst() {
        let actions: JSONValue = .array([
            .object(["id": .string("a.one"), "enabled": .bool(true)]),
            .object(["id": .string("a.two"), "enabled": .bool(true), "lastRun": .string("2026-10-05T09:00:00Z")]),
            .object(["id": .string("a.three"), "enabled": .bool(true), "lastRun": .string("2026-10-05T10:00:00Z")]),
            .object(["id": .string("a.four"), "enabled": .bool(false), "lastRun": .string("2026-10-05T11:00:00Z")]),
        ])
        #expect(PluginActionTools.listed(from: actions, budget: 3).map(\.actionID) == ["a.three", "a.two", "a.one"])
    }

    @Test("Action search matches ID, title or plugin, ignoring case and accents")
    func search() {
        let texts = ["bashcut.silence-markers.remove", "Xoá khoảng lặng", "bashcut.silence-markers", "Silence Markers"]
        #expect(PluginActionTools.matches(nil, texts) && PluginActionTools.matches("  ", texts))
        #expect(PluginActionTools.matches("SILENCE", texts) && PluginActionTools.matches("khoang lang", texts))
        #expect(!PluginActionTools.matches("captions", texts))
    }

    @Test("Agent instructions explain discovering and running plugin actions")
    func instructions() {
        let text = CommandCatalog.instructions
        #expect(text.contains("plugins actions") && text.contains("plugins run") && text.contains("jobs status"))
        #expect(text.contains(PluginActionTools.prefix))
        #expect(text.contains("at most \(PluginActionTools.budget)"))
        #expect(CommandCatalog.spec(named: "plugins.actions")?.summary.contains("plugins run") == true)
    }
}
