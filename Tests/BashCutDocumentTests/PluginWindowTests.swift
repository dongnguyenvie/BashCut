import BashCutDocument
import CoreGraphics
import Foundation
import Testing

/// Plugin views in windows (plugin API 11 `location: window`, #589).
@MainActor
struct PluginWindowTests {
    @Test("A new window is 75% of the editor, at least 900×600")
    func defaultSize() {
        #expect(PluginWindowLayout.defaultSize(editor: CGSize(width: 1920, height: 1055)) == CGSize(width: 1440, height: 791))
        #expect(PluginWindowLayout.defaultSize(editor: CGSize(width: 1280, height: 800)) == CGSize(width: 960, height: 600))
        #expect(PluginWindowLayout.defaultSize(editor: CGSize(width: 1000, height: 700)) == PluginWindowLayout.minimum)
        #expect(PluginWindowLayout.defaultSize(editor: nil) == PluginWindowLayout.fallback)
    }

    @Test("A non-modal window is listed with a window flag, never blocks, and is answered by its dialog id")
    func nonModalWindow() throws {
        let center = ModalCenter()
        var answers: [String] = []
        var settingsOpen = false
        center.sheets = {
            var sheets = [ModalSheet(
                name: "plugin-window", title: "Online resources",
                options: [ModalOption("dock", "Dock"), ModalOption("close", "Close")], window: true, id: "plugin-window:a.b/browse"
            ) { answers.append($0) }]
            if settingsOpen {
                sheets.append(ModalSheet(name: "settings", title: "Settings", options: [ModalOption("close", "Close")]) { _ in
                    settingsOpen = false
                })
            }
            return sheets
        }
        #expect(center.open.count == 1)
        #expect(center.open.first?.json.object["window"] == .bool(true))
        #expect(center.open.first?.id == "sheet:plugin-window:a.b/browse")
        #expect(center.current == nil)
        #expect(throws: ModalError.self) { try center.respond(option: "close", path: nil) }
        try center.respond(option: "dock", path: nil, dialog: "sheet:plugin-window:a.b/browse")
        #expect(answers == ["dock"])
        // A modal sheet over it is the current dialog and is answered without naming it.
        settingsOpen = true
        #expect(center.current?.name == "settings")
        try center.respond(option: "close", path: nil)
        #expect(!settingsOpen)
        #expect(answers == ["dock"])
    }
}
