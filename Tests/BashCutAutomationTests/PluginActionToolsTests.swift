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

    @Test("Agent instructions explain discovering and running plugin actions")
    func instructions() {
        let text = CommandCatalog.instructions
        #expect(text.contains("plugins actions") && text.contains("plugins run") && text.contains("jobs status"))
        #expect(text.contains(PluginActionTools.prefix))
    }
}
