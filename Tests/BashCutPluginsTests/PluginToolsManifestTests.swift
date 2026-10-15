import BashCutPlugin
import Foundation
import Testing

struct PluginToolsManifestTests {
    private func make(apiVersion: Int, contributes: String, transport: String = "session") throws -> PluginManifest {
        let json = """
            {"schema": "bashcut.plugin/1", "id": "a.b", "name": "A", "version": "1.0.0", "apiVersion": \(apiVersion),
             "entrypoint": "bin/run", "capabilities": [], "transport": "\(transport)", "contributes": \(contributes)}
            """
        return try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
    }

    private let toolAction = """
        {"actions": [{"id": "a.b.trim", "title": "Trim", "placements": ["tools"],
          "params": [{"id": "pad", "title": "Pad", "type": "integer"},
                     {"id": "mode", "title": "Mode", "type": "string", "advanced": true}]}]}
        """

    @Test("A tool action with an advanced option decodes and validates at API 10")
    func toolAction10() throws {
        let manifest = try make(apiVersion: 10, contributes: toolAction)
        try manifest.validate()
        let action = try #require(manifest.contributes?.actions?.first)
        #expect(action.isTool)
        #expect(action.params?.map(\.isAdvanced) == [false, true])
    }

    @Test("The tools placement and advanced options need API 10")
    func needsAPI10() throws {
        #expect(throws: PluginError.self) { try make(apiVersion: 9, contributes: toolAction).validate() }
        let advancedOnly = """
            {"actions": [{"id": "a.b.x", "title": "X", "placements": ["menu.plugins"],
              "params": [{"id": "p", "title": "P", "type": "string", "advanced": true}]}]}
            """
        #expect(throws: PluginError.self) { try make(apiVersion: 9, contributes: advancedOnly).validate() }
    }

    @Test("An old manifest decodes as before: panel views, no tool, nothing advanced")
    func oldManifest() throws {
        let old = """
            {"container": {"icon": "star"}, "views": [{"id": "main", "title": "Main"}],
             "actions": [{"id": "a.b.x", "title": "X", "placements": ["menu.plugins"],
               "params": [{"id": "p", "title": "P", "type": "string"}]}]}
            """
        let manifest = try make(apiVersion: 8, contributes: old)
        try manifest.validate()
        let view = try #require(manifest.contributes?.views?.first)
        #expect(view.kind == nil && view.effectiveKind == .panel && !view.isTool)
        #expect(manifest.contributes?.actions?.first?.isTool == false)
        #expect(manifest.contributes?.actions?.first?.params?.first?.isAdvanced == false)
    }

    @Test("A tool view needs no rail container, and only lives in the panel location")
    func toolView() throws {
        let tool = #"{"views": [{"id": "t", "title": "T", "kind": "tool"}]}"#
        let manifest = try make(apiVersion: 10, contributes: tool)
        try manifest.validate()
        #expect(manifest.contributes?.views?.first?.isTool == true)
        let panelNoContainer = #"{"views": [{"id": "t", "title": "T"}]}"#
        #expect(throws: PluginError.self) { try self.make(apiVersion: 10, contributes: panelNoContainer).validate() }
        let sheetTool = #"{"views": [{"id": "t", "title": "T", "kind": "tool", "location": "sheet"}]}"#
        #expect(throws: PluginError.self) { try self.make(apiVersion: 10, contributes: sheetTool).validate() }
        let apiNine = try make(apiVersion: 9, contributes: tool)
        #expect(throws: PluginError.self) { try apiNine.validate() }
    }

    @Test("The host serves API 10 and lists the tools feature")
    func hostFeature() {
        #expect(PluginAPI.current >= 10)
        #expect(PluginFeature.all.contains("tools"))
    }
}
