import BashCutPlugin
import BashCutProject
import Foundation
import Testing

/// The `colorPicker` and `fontPicker` view components (`views.colorPicker`, `views.fontPicker`).
@Suite("Plugin view colour and font pickers")
struct PluginViewPickerTests {
    private func tree(_ json: String) throws -> PluginViewTree {
        try PluginViewTree(parsing: JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    @Test("Both pickers are inputs with ids, values and host features")
    func inputs() throws {
        let tree = try tree("""
            {"body": [{"type": "colorPicker", "id": "fill", "label": "Fill", "value": "#ff8800"},
                      {"type": "colorPicker", "id": "shade", "alpha": true, "value": "#00000080"},
                      {"type": "colorPicker", "id": "plain"},
                      {"type": "fontPicker", "id": "font", "value": "Inter-Bold"},
                      {"type": "fontPicker", "id": "family", "by": "family"}]}
            """)
        #expect(tree.inputValues == [
            "fill": .string("#FF8800"), "shade": .string("#00000080"), "plain": .string("#FFFFFF"),
            "font": .string("Inter-Bold"), "family": .string(""),
        ])
        #expect(PluginViewNode.Kind.colorPicker.isInteractive && PluginViewNode.Kind.fontPicker.isInput)
        #expect(PluginFeature.all.contains("views.colorPicker"))
        #expect(PluginFeature.all.contains("views.fontPicker"))
        #expect(PluginFeature.all.contains("options.set"))
    }

    @Test("Pickers without an id, a colour that is not hex or an unknown by are refused", arguments: [
        #"{"body": [{"type": "colorPicker"}]}"#,
        #"{"body": [{"type": "fontPicker"}]}"#,
        #"{"body": [{"type": "colorPicker", "id": "c", "value": "red"}]}"#,
        ##"{"body": [{"type": "colorPicker", "id": "c", "value": "#12345"}]}"##,
        #"{"body": [{"type": "fontPicker", "id": "f", "by": "weight"}]}"#,
    ])
    func refused(_ json: String) {
        #expect(throws: PluginError.self) { try tree(json) }
    }

    @Test("Hex colours normalize, with and without alpha")
    func hex() {
        #expect(PluginViewColor.normalized("#abc") == "#AABBCC")
        #expect(PluginViewColor.normalized("#abc", alpha: true) == "#AABBCCFF")
        #expect(PluginViewColor.normalized("#11223344") == "#112233")
        #expect(PluginViewColor.normalized("#11223344", alpha: true) == "#11223344")
        #expect(PluginViewColor.normalized("112233") == nil)
        #expect(PluginViewColor.normalized("#GG0000") == nil)
        let parts = PluginViewColor.components("#FF000080")
        #expect(parts?.red == 1 && parts?.green == 0 && abs((parts?.alpha ?? 0) - 128.0 / 255) < 0.0001)
        #expect(PluginViewColor.hex(red: 1, green: 0.5, blue: 0) == "#FF8000")
        #expect(PluginViewColor.hex(red: 2, green: -1, blue: .nan, alpha: 0.5, includeAlpha: true) == "#FF000080")
    }
}
