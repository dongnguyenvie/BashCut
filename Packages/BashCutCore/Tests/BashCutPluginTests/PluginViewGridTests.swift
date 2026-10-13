import BashCutPlugin
import BashCutProject
import Foundation
import Testing

/// The `grid` view component (`views.grid`): tiles of list-style items for pickers such as online resources.
@Suite("Plugin view grid")
struct PluginViewGridTests {
    private func tree(_ json: String) throws -> PluginViewTree {
        try PluginViewTree(parsing: JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    @Test("A grid parses its items, keeps its fields and is an interactive host feature")
    func parses() throws {
        let tree = try tree("""
            {"body": [{"type": "grid", "id": "results", "cellWidth": 140, "aspect": 1.78, "selected": ["a", "b"],
                       "more": "Load more", "empty": "Nothing found",
                       "items": [{"id": "a", "image": "/tmp/a.jpg", "title": "Coffee", "badge": "CC0",
                                  "badgeColor": "green", "file": "/tmp/a.jpg",
                                  "actions": [{"id": "add", "title": "Add", "icon": "plus"}]},
                                 {"id": "b", "icon": "music.note", "audio": "/tmp/b.mp3", "libraryItem": "clip-1"}]}]}
            """)
        let grid = try #require(tree.node("results"))
        #expect(grid.kind == .grid)
        #expect(grid.array("items").count == 2)
        #expect(grid.double("cellWidth") == 140)
        #expect(grid.props["selected"] == .array([.string("a"), .string("b")]))
        #expect(grid.string("more") == "Load more")
        #expect(PluginViewNode.Kind.grid.isInteractive && !PluginViewNode.Kind.grid.isInput)
        #expect(PluginFeature.all.contains("views.grid"))
        #expect(grid.json.object["type"] == .string("grid"))
    }

    @Test("A grid without an id or an item without an id is refused", arguments: [
        #"{"body": [{"type": "grid", "items": []}]}"#,
        #"{"body": [{"type": "grid", "id": "g", "items": [{"title": "No id"}]}]}"#,
        #"{"body": [{"type": "grid", "id": "g", "items": [{"id": ""}]}]}"#,
    ])
    func refused(_ json: String) {
        #expect(throws: PluginError.self) { try tree(json) }
    }

    @Test("A grid shows at most the list item limit")
    func limit() throws {
        let items = (0...PluginViewTree.maximumListItems).map { #"{"id": "i\#($0)"}"# }.joined(separator: ",")
        #expect(throws: PluginError.self) { try tree(#"{"body": [{"type": "grid", "id": "g", "items": [\#(items)]}]}"#) }
        let fitting = (1...PluginViewTree.maximumListItems).map { #"{"id": "i\#($0)"}"# }.joined(separator: ",")
        #expect(try tree(#"{"body": [{"type": "grid", "id": "g", "items": [\#(fitting)]}]}"#).body.count == 1)
    }

    @Test("Grid events: select a cell, a cell button's action and the load-more click")
    func events() {
        let more = PluginViewEvent(node: "results", kind: .click, value: .string("more"))
        #expect(more.json == .object(["node": .string("results"), "type": .string("click"), "value": .string("more")]))
        let action = PluginViewEvent(node: "results", kind: .action, value: .object(["item": .string("a"), "action": .string("add")]))
        #expect(action.json.object["value"]?.object["action"] == .string("add"))
        #expect(!more.supersedes(PluginViewEvent(node: "results", kind: .click, value: .string("more"))))
    }
}
