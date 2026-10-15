import BashCutPlugin
import BashCutProject
import Foundation
import Testing

/// Layout components `split` and `nav`, and grid tiles that download when dragged (API 11, #590).
@Suite("Plugin view split, nav and download drag")
struct PluginViewLayoutTests {
    private func tree(_ json: String) throws -> PluginViewTree {
        try PluginViewTree(parsing: JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    private static let column = #"{"type": "section", "children": [{"type": "text", "text": "x"}]}"#

    private func split(_ widths: String?, columns: Int) -> String {
        let children = Array(repeating: Self.column, count: columns).joined(separator: ",")
        let widthsField = widths.map { "\"widths\": \($0), " } ?? ""
        return "{\"body\": [{\"type\": \"split\", " + widthsField + "\"children\": [" + children + "]}]}"
    }

    @Test("A split has 2 or 3 columns and one width per column, in points or flex")
    func splitColumns() throws {
        let three = try tree(split(#"[200, "flex", 280]"#, columns: 3))
        #expect(three.body.first?.kind == .split)
        #expect(three.body.first?.children.count == 3)
        #expect(three.fillingSplit?.kind == .split)
        #expect(try tree(#"{"body": [{"type": "text", "text": "x"}]}"#).fillingSplit == nil)
        _ = try tree(split(nil, columns: 2))
        let bad: [(String?, Int)] = [(nil, 1), (nil, 4), (#"[200, "flex"]"#, 3), (#"[20, "flex"]"#, 2), (#"["wide", "flex"]"#, 2)]
        for (widths, columns) in bad {
            let json = split(widths, columns: columns)
            #expect(throws: PluginError.self) { try self.tree(json) }
        }
        #expect(PluginFeature.all.contains("views.split"))
    }

    @Test("A nav needs an id, entries with ids, and sends select")
    func nav() throws {
        let view = try tree(#"""
            {"body": [{"type": "nav", "id": "types", "value": "photos", "groups": [
              {"title": "Types", "items": [{"id": "photos", "title": "Photos", "icon": "photo", "count": 12},
                                           {"id": "video", "title": "Video", "icon": "film"}]},
              {"title": "Providers", "items": [{"id": "pexels", "title": "Pexels"}]}]}]}
            """#)
        let node = try #require(view.node("types"))
        #expect(node.kind?.isInteractive == true)
        #expect(node.kind?.isInput == false)
        #expect(node.array("groups").count == 2)
        #expect(throws: PluginError.self) {
            try self.tree(#"{"body": [{"type": "nav", "groups": [{"items": [{"id": "a"}]}]}]}"#)
        }
        #expect(throws: PluginError.self) {
            try self.tree(#"{"body": [{"type": "nav", "id": "n", "groups": [{"items": [{"title": "No id"}]}]}]}"#)
        }
        #expect(PluginFeature.all.contains("views.nav"))
        #expect(PluginViewEvent(node: "types", kind: .select, value: .string("video")).json.object["type"] == .string("select"))
    }

    @Test("A download drag round-trips through the pasteboard; a drag answer names a library item")
    func downloadDrag() throws {
        let tile = PluginViewDrag.Download(plugin: "bashcut.resources", view: "browse", node: "results", item: "pexels:123")
        let payload = try #require(PluginViewDrag.downloadPayload(tile))
        #expect(payload.hasPrefix(PluginViewDrag.downloadPrefix))
        #expect(PluginViewDrag.download(dropped: payload) == tile)
        #expect(tile.key == "bashcut.resources/browse")
        #expect(PluginViewDrag.download(dropped: "bashcut-library:project:abc") == nil)
        #expect(PluginViewDrag.download(dropped: PluginViewDrag.downloadPrefix + "{}") == nil)
        #expect(PluginViewDrag.downloadPayload(.init(plugin: "a.b", view: "v", node: "g", item: "")) == nil)
        let event = PluginViewEvent(node: "results", kind: .drag, value: .object(["item": .string("pexels:123")]))
        #expect(event.json.object["type"] == .string("drag"))
        let answer = try tree(#"{"body": [], "libraryItem": "project:abc123"}"#)
        #expect(answer.libraryItem == "project:abc123")
        #expect(answer.json.object["libraryItem"] == .string("project:abc123"))
        #expect(try tree(#"{"body": [], "libraryItem": "nowhere"}"#).libraryItem == nil)
    }
}
