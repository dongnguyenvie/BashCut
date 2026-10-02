import BashCutDocument
import BashCutProject
import Foundation
import Testing

@MainActor
struct ModalCenterTests {
    @Test("Sheets are listed topmost last and answered by option ID or title")
    func sheets() throws {
        let center = ModalCenter()
        var settingsOpen = true
        var conflict: String?
        center.sheets = {
            var sheets: [ModalSheet] = []
            if settingsOpen {
                sheets.append(ModalSheet(name: "settings", title: "Settings", options: [ModalOption("close", "Đóng")]) { _ in
                    settingsOpen = false
                })
            }
            if conflict == nil {
                sheets.append(ModalSheet(
                    name: "external-changes", title: "Changed",
                    options: [ModalOption("keep-app", "Giữ bản app"), ModalOption("load-disk", "Tải bản trên đĩa")]
                ) { conflict = $0 })
            }
            return sheets
        }
        #expect(center.open.map(\.name) == ["settings", "external-changes"])
        #expect(center.current?.json.object["kind"] == .string("sheet"))
        #expect(throws: ModalError.self) { try center.respond(option: "approve", path: nil) }
        #expect(throws: ModalError.self) { try center.respond(option: "close", path: nil, dialog: "sheet:settings") }
        try center.respond(option: "Tải bản trên đĩa", path: nil)
        #expect(conflict == "load-disk")
        try center.respond(option: "CLOSE", path: nil, dialog: "sheet:settings")
        #expect(!settingsOpen)
        #expect(center.current == nil)
        #expect(throws: ModalError.self) { try center.respond(option: "close", path: nil) }
    }
}
