import BashCutPlugin
import BashCutProject
import Foundation
import Testing

@Suite("Plugin API 2: options, actions, hooks")
struct PluginContributionsTests {
    private func manifest(_ json: String) throws -> PluginManifest {
        try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
    }

    private func base(_ extra: String, apiVersion: Int = 2, capabilities: String = "[]") -> String {
        """
        {"schema": "bashcut.plugin/1", "id": "example.toolkit", "name": "Toolkit", "version": "1.0.0",
         "apiVersion": \(apiVersion), "entrypoint": "bin/provider", "capabilities": \(capabilities)\(extra)}
        """
    }

    @Test("A contribution-only plugin decodes and validates")
    func validManifest() throws {
        let plugin = try manifest(base("""
            , "transport": "session",
            "options": [{"id": "strength", "title": "Strength", "type": "number", "minimum": 0, "maximum": 1,
                         "default": 0.5, "scope": "project"}],
            "contributes": {
              "actions": [{"id": "example.toolkit.grade", "title": {"en": "Auto Grade", "vi": "Tự chỉnh màu"},
                           "placements": ["menu.plugins", "clip.context", "panel.filters", "inspector.color"],
                           "when": "selection.kind == video && !playing",
                           "params": [{"id": "mode", "title": "Mode", "type": "enum", "choices": ["natural", "vivid"]}],
                           "shortcut": "cmd+shift+g", "context": ["timeline"]}],
              "hooks": ["media.imported", {"event": "edit.committed", "debounceMs": 800, "edits": true}]
            }
            """))
        try plugin.validate()
        #expect(plugin.transportKind == .session)
        #expect(plugin.actions.first?.title.text(for: "vi") == "Tự chỉnh màu")
        #expect(plugin.actions.first?.title.text(for: "fr") == "Auto Grade")
        #expect(plugin.options?.first?.title.text(for: "vi") == "Strength")
        #expect(plugin.hooks.map(\.event) == ["media.imported", "edit.committed"])
        #expect(plugin.hooks.last?.proposesEdits == true)
        #expect(plugin.hooks.first?.proposesEdits == false)
        #expect(plugin.options?.first?.effectiveScope == .project)
        #expect(plugin.incompatibility == nil)
    }

    @Test("Invalid contributions are rejected", arguments: [
        // Action IDs live under the plugin ID.
        """
        , "contributes": {"actions": [{"id": "other.grade", "title": "Grade", "placements": ["toolbar"]}]}
        """,
        // Placements come from the app's fixed list.
        """
        , "contributes": {"actions": [{"id": "example.toolkit.a", "title": "A", "placements": ["sidebar"]}]}
        """,
        // `when` keys are known facts only.
        """
        , "contributes": {"actions": [{"id": "example.toolkit.a", "title": "A", "placements": ["toolbar"],
                                       "when": "clipboard.full"}]}
        """,
        // Frequent events need the session transport.
        """
        , "contributes": {"hooks": ["selection.changed"]}
        """,
        // Unknown events.
        """
        , "contributes": {"hooks": ["app.exploded"]}
        """,
        // An enum option needs choices; a default must fit.
        """
        , "options": [{"id": "mode", "title": "Mode", "type": "enum"}]
        """,
        """
        , "options": [{"id": "n", "title": "N", "type": "integer", "minimum": 1, "maximum": 3, "default": 9}]
        """,
    ])
    func invalid(_ extra: String) throws {
        let plugin = try manifest(base(extra))
        #expect(throws: PluginError.self) { try plugin.validate() }
    }

    @Test("Options, actions and sessions need plugin API 2")
    func needsAPI2() throws {
        let plugin = try manifest(base(
            #", "contributes": {"hooks": ["export.finished"]}"#, apiVersion: 1))
        #expect(throws: PluginError.self) { try plugin.validate() }
        // Version 1 providers stay valid.
        try manifest(base("", apiVersion: 1, capabilities: #"["audio.beats"]"#)).validate()
    }

    @Test("review.check needs apiVersion 9 (#451)")
    func reviewCheckVersion() throws {
        #expect(PluginAPI.current >= 9)
        #expect(throws: PluginError.self) {
            try manifest(base("", apiVersion: 8, capabilities: #"["review.check"]"#)).validate()
        }
        try manifest(base("", apiVersion: 9, capabilities: #"["review.check"]"#)).validate()
    }

    @Test("The API window reports plugins this BashCut cannot run")
    func apiWindow() throws {
        let future = try manifest(base("", apiVersion: PluginAPI.current + 1, capabilities: #"["audio.beats"]"#))
        try future.validate()
        #expect(future.incompatibility?.contains("Update BashCut") == true)
        let legacy = try manifest(base(
            #", "minApiVersion": 1, "maxApiVersion": 1"#, apiVersion: 1, capabilities: #"["audio.beats"]"#))
        #expect(legacy.incompatibility == nil)
    }

    @Test("Localized text takes a string or a language map")
    func localizedText() throws {
        let decode = { (json: String) in try JSONDecoder().decode(LocalizedText.self, from: Data(json.utf8)) }
        let plain = try decode(#""Grade""#)
        #expect(plain.values == ["en": "Grade"])
        let map = try decode(#"{"en": "Color", "pt": "Cor", "vi": "Màu"}"#)
        #expect(map.text(for: "vi") == "Màu")
        #expect(map.text(for: "pt-BR") == "Cor")
        #expect(map.text(for: "ja") == "Color")
        #expect(String(data: try JSONEncoder().encode(plain), encoding: .utf8) == #""Grade""#)
        // Several languages need English; empty values are rejected.
        for bad in [#"{"vi": "Màu", "pt": "Cor"}"#, #"{"en": " "}"#] {
            let plugin = try manifest(base(
                #", "contributes": {"actions": [{"id": "example.toolkit.a", "placements": ["toolbar"], "title": "#
                    + bad + "}]}"))
            #expect(throws: PluginError.self) { try plugin.validate() }
        }
    }

    @Test("Dependency commands may leave out arguments")
    func commandArguments() throws {
        let plugin = try manifest(base(
            #", "dependencies": [{"id": "m", "name": "Model", "kind": "python", "probe": {"executable": "bin/check"}}]"#,
            capabilities: #"["audio.beats"]"#))
        try plugin.validate()
        #expect(plugin.dependencies.first?.probe.arguments == [])
    }

    @Test("When expressions test app facts")
    func when() throws {
        let condition = try PluginWhen(parsing: "selection && selection.kind == video|audio && !playing")
        #expect(condition.evaluate(["selection": "true", "selection.kind": "audio"]))
        #expect(!condition.evaluate(["selection": "true", "selection.kind": "text"]))
        #expect(!condition.evaluate(["selection": "true", "selection.kind": "video", "playing": "true"]))
        #expect(try PluginWhen(parsing: "media.kind != audio").evaluate(["media.kind": "video"]))
        #expect(throws: PluginError.self) { try PluginWhen(parsing: "selection &&") }
        #expect(throws: PluginError.self) { try PluginWhen(parsing: "track.kind ==") }
    }

    @Test("Options check, parse and fill defaults")
    func options() throws {
        let options = [
            PluginOption(id: "mode", title: "Mode", type: .enumeration, choices: ["a", "b"]),
            PluginOption(id: "count", title: "Count", type: .integer, default: .integer(2), minimum: 1, maximum: 5),
            PluginOption(id: "gain", title: "Gain", type: .number, minimum: -1, maximum: 1),
            PluginOption(id: "loud", title: "Loud", type: .bool),
        ]
        let resolved = try options.resolve(["count": .number(3), "loud": .bool(true)])
        #expect(resolved == ["mode": .string("a"), "count": .integer(3), "gain": .number(-1), "loud": .bool(true)])
        #expect(throws: PluginError.self) { try options.resolve(["count": .integer(9)]) }
        #expect(throws: PluginError.self) { try options.resolve(["mode": .string("c")]) }
        #expect(throws: PluginError.self) { try options.resolve(["extra": .bool(true)]) }
        #expect(try options[3].parse("on") == .bool(true))
        #expect(try options[2].parse("0.25") == .number(0.25))
        #expect(throws: PluginError.self) { try options[1].parse("many") }
        #expect(options[0].jsonSchema.object["enum"] == .array([.string("a"), .string("b")]))
    }
}
