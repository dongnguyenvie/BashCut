import BashCutDocument
import Testing

@Suite("Settings search")
struct SettingsSearchTests {
    private let scope = ["Edits outside the attached clips", "Sửa ngoài các clip đã gửi", "scope", "guard"]

    @Test("Every word must match a term, ignoring case and accents, in either language")
    func matching() {
        #expect(SettingsSearch.matches("", scope))
        #expect(SettingsSearch.matches("SCOPE", scope))
        #expect(SettingsSearch.matches("attached clips", scope))
        #expect(SettingsSearch.matches("đã gửi", scope))
        #expect(SettingsSearch.matches("clip da gui", scope))
        #expect(!SettingsSearch.matches("scope token", scope))
        #expect(!SettingsSearch.matches("kit", scope))
    }
}
