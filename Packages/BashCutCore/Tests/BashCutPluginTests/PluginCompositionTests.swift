import BashCutPlugin
import BashCutProject
import Foundation
import Testing

/// Plugin API 8 (#391, #393, #394): container, views, requires, uses, features and view trees.
@Suite("Plugin composition and views")
struct PluginCompositionTests {
    private func manifest(_ extra: String, apiVersion: Int = 8, transport: String = "session") throws -> PluginManifest {
        try JSONDecoder().decode(PluginManifest.self, from: Data("""
            {"schema": "bashcut.plugin/1", "id": "example.views", "name": "Example Views", "version": "1.0.0",
             "apiVersion": \(apiVersion), "entrypoint": "bin/provider", "capabilities": [], "transport": "\(transport)"\(extra)}
            """.utf8))
    }

    private static let panel = #", "contributes": {"container": {"icon": "wand.and.stars", "title": "Views"}, "#
        + #""views": [{"id": "main", "title": {"en": "Main", "vi": "Chính"}}]}"#

    @Test("A container with views validates and needs API 8 and the session transport")
    func containerAndViews() throws {
        let plugin = try manifest(Self.panel)
        try plugin.validate()
        #expect(plugin.container?.icon == "wand.and.stars")
        #expect(plugin.views.map(\.id) == ["main"])
        #expect(plugin.containerTitle == "Views")
        #expect(PluginAPI.current >= 8)
        #expect(throws: PluginError.self) { try manifest(Self.panel, apiVersion: 7).validate() }
        #expect(throws: PluginError.self) { try manifest(Self.panel, transport: "oneshot").validate() }
        // Views need a container; a container alone (a panel of tools and skills) is fine.
        #expect(throws: PluginError.self) {
            try manifest(#", "contributes": {"views": [{"id": "main", "title": "Main"}]}"#).validate()
        }
        try manifest(#", "contributes": {"container": {"icon": "star"}}"#, transport: "oneshot").validate()
        #expect(throws: PluginError.self) {
            try manifest(#", "contributes": {"container": {"icon": "Not A Symbol!"}}"#).validate()
        }
    }

    @Test("Views live in the panel, the dock or a sheet; only panel views need a container")
    func locations() throws {
        let plugin = try manifest(#", "contributes": {"views": [{"id": "voice", "title": "Voice", "location": "dock", "#
            + #""icon": "waveform"}, {"id": "form", "title": "Form", "location": "sheet"}]}"#)
        try plugin.validate()
        #expect(plugin.views.map(\.place) == [.dock, .sheet])
        #expect(plugin.container == nil)
        #expect(throws: PluginError.self) {
            try manifest(#", "contributes": {"views": [{"id": "a", "title": "A", "location": "panel"}]}"#).validate()
        }
        #expect(throws: (any Error).self) {
            try manifest(#", "contributes": {"views": [{"id": "a", "title": "A", "location": "window"}]}"#).validate()
        }
        #expect(throws: PluginError.self) {
            try manifest(#", "contributes": {"views": [{"id": "a", "title": "A", "location": "dock", "icon": "Bad!"}]}"#)
                .validate()
        }
        #expect(PluginFeature.all.contains("location.sheet"))
        let tree = try PluginViewTree(parsing: .object(["body": .array([]), "close": .bool(true)]))
        #expect(tree.close)
    }

    @Test("Requirements, uses and features validate")
    func compositionFields() throws {
        let plugin = try manifest(
            #", "contributes": {"container": {"icon": "star"}}, "requires": [{"id": "example.base", "version": "^1.2.0"}], "#
                + #""uses": ["voice.synthesize"], "features": ["views"]"#
        )
        try plugin.validate()
        #expect(plugin.requirements.map(\.id) == ["example.base"])
        #expect(plugin.usedCapabilities == ["voice.synthesize"])
        #expect(plugin.incompatibility == nil)
        #expect(throws: PluginError.self) {
            try manifest(#", "contributes": {"container": {"icon": "star"}}, "requires": [{"id": "example.views"}]"#).validate()
        }
        #expect(throws: PluginError.self) {
            try manifest(#", "contributes": {"container": {"icon": "star"}}, "requires": [{"id": "example.base", "version": "lots"}]"#)
                .validate()
        }
        #expect(throws: PluginError.self) {
            try manifest(#", "contributes": {"container": {"icon": "star"}}, "uses": ["agent.chat"]"#).validate()
        }
        #expect(throws: PluginError.self) {
            try manifest(#", "contributes": {"container": {"icon": "star"}}, "uses": ["voice.synthesize"]"#, apiVersion: 7)
                .validate()
        }
    }

    @Test("A plugin needing a feature this host lacks is outdated")
    func missingFeature() throws {
        let plugin = try manifest(#", "contributes": {"container": {"icon": "star"}}, "features": ["views.hologram"]"#)
        try plugin.validate()
        #expect(plugin.incompatibility?.contains("views.hologram") == true)
        #expect(PluginFeature.all.contains("views.list"))
    }

    @Test("Version ranges", arguments: [
        ("*", "0.0.1", true), (">=0.2.0", "0.2.0", true), (">=0.2.0", "0.1.9", false), ("^1.2.0", "1.9.3", true),
        ("^1.2.0", "2.0.0", false), ("^0.2.1", "0.2.9", true), ("^0.2.1", "0.3.0", false), ("~1.2.0", "1.2.5", true),
        ("~1.2.0", "1.3.0", false), ("1.2.3", "1.2.3", true), ("1.2.3", "1.2.4", false), (">=1.0.0 <2.0.0", "1.5.0", true),
        (">=1.0.0 <2.0.0", "2.0.0", false), (">1.0.0", "1.0.0-beta.1", false),
    ])
    func ranges(_ range: String, _ version: String, _ expected: Bool) throws {
        #expect(try PluginVersionRange(range).contains(version) == expected)
    }

    private func installed(_ id: String, version: String = "1.0.0", requires: [PluginRequirement]? = nil) -> InstalledPlugin {
        InstalledPlugin(
            manifest: PluginManifest(
                id: id, name: LocalizedText(["en": id]), version: version, apiVersion: 8, entrypoint: "bin/provider",
                capabilities: ["x.y"], requires: requires),
            directory: URL(fileURLWithPath: "/tmp/\(id)"))
    }

    @Test("Requirement problems: missing, out of range, not ready, chained and looping")
    func requirementProblems() {
        let base = installed("example.base", version: "1.4.0")
        let child = installed("example.child", requires: [PluginRequirement(id: "example.base", version: "^1.2.0")])
        let grandchild = installed("example.grand", requires: [PluginRequirement(id: "example.child")])
        let wantsNew = installed("example.new", requires: [PluginRequirement(id: "example.base", version: ">=2.0.0")])
        let missing = installed("example.lonely", requires: [PluginRequirement(id: "example.gone")])
        let loopA = installed("example.loop-a", requires: [PluginRequirement(id: "example.loop-b")])
        let loopB = installed("example.loop-b", requires: [PluginRequirement(id: "example.loop-a")])
        let all = [base, child, grandchild, wantsNew, missing, loopA, loopB]
        let problems = PluginRequirements.problems(all) { _ in true }
        #expect(problems["example.base"] == nil)
        #expect(problems["example.child"] == nil)
        #expect(problems["example.grand"] == nil)
        #expect(problems["example.new"]?.contains("1.4.0") == true)
        #expect(problems["example.lonely"]?.contains("example.gone") == true)
        #expect(problems["example.loop-a"] != nil)
        #expect(problems["example.loop-b"] != nil)
        // The base turned off: its dependents and theirs stop.
        let off = PluginRequirements.problems(all) { $0.id != "example.base" }
        #expect(off["example.child"]?.contains("not ready") == true)
        #expect(off["example.grand"] != nil)
        #expect(PluginRequirements.missing(missing, installed: all).map(\.id) == ["example.gone"])
        #expect(PluginRequirements.missing(child, installed: all).isEmpty)
    }

    @Test("A view tree parses, keeps ids, values and unknown components")
    func viewTree() throws {
        let tree = try PluginViewTree(parsing: .object([
            "title": .string("Voices"), "state": .object(["page": .integer(2)]), "refreshSeconds": .integer(1),
            "body": .array([
                .object(["type": .string("section"), "title": .string("Find"), "children": .array([
                    .object(["type": .string("textField"), "id": .string("query"), "value": .string("warm"),
                             "search": .bool(true)]),
                    .object(["type": .string("toggle"), "id": .string("cloned")]),
                    .object(["type": .string("hologram"), "text": .string("future")]),
                ])]),
                .object(["type": .string("list"), "id": .string("voices"), "items": .array([
                    .object(["id": .string("v1"), "title": .string("Anna")]),
                ])]),
            ]),
        ]))
        #expect(tree.title == "Voices")
        #expect(tree.refreshSeconds == 2)
        #expect(tree.state == .object(["page": .integer(2)]))
        #expect(tree.nodes.count == 5)
        #expect(tree.node("query")?.kind == .textField)
        #expect(tree.node("_0.2")?.kind == nil)
        #expect(tree.inputValues == ["query": .string("warm"), "cloned": .bool(false)])
        #expect(tree.json.object["body"]?.array.first?.object["children"]?.array.count == 3)
    }

    @Test("Bad view trees are refused", arguments: [
        #"{"title": "no body"}"#,
        #"{"body": [{"text": "no type"}]}"#,
        #"{"body": [{"type": "button", "title": "No id"}]}"#,
        #"{"body": [{"type": "button", "id": "a"}, {"type": "toggle", "id": "a"}]}"#,
        #"{"body": [{"type": "list", "id": "l", "items": [{"title": "no id"}]}]}"#,
    ])
    func badTrees(_ json: String) throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(throws: PluginError.self) { try PluginViewTree(parsing: value) }
    }

    @Test("View trees are capped in size and depth")
    func caps() {
        let many = JSONValue.object(["body": .array(Array(
            repeating: .object(["type": .string("divider")]), count: PluginViewTree.maximumNodes + 1))])
        #expect(throws: PluginError.self) { try PluginViewTree(parsing: many) }
        var deep = JSONValue.object(["type": .string("text"), "text": .string("leaf")])
        for _ in 0..<PluginViewTree.maximumDepth {
            deep = .object(["type": .string("section"), "children": .array([deep])])
        }
        #expect(throws: PluginError.self) { try PluginViewTree(parsing: .object(["body": .array([deep])])) }
    }

    @Test("Typing replaces a waiting change of the same input; clicks never do")
    func coalescing() {
        let typing = PluginViewEvent(node: "query", kind: .change, value: .string("wa"))
        #expect(PluginViewEvent(node: "query", kind: .change, value: .string("war")).supersedes(typing))
        #expect(!PluginViewEvent(node: "other", kind: .change).supersedes(typing))
        #expect(!PluginViewEvent(node: "go", kind: .click).supersedes(PluginViewEvent(node: "go", kind: .click)))
    }
}
