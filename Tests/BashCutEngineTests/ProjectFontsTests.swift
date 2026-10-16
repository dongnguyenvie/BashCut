import CoreText
import Foundation
import Testing
@testable import BashCutEngine
import BashCutProject

@Suite("Project fonts (#415)", .serialized)
struct ProjectFontsTests {
    private static let systemFont = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Georgia Bold.ttf")

    @Test("Import copies a font into the project's fonts folder; list shows it first; other files are refused")
    func importAndList() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fonts-\(UUID().uuidString)")
        defer {
            ProjectFonts.activate(projectRoot: nil)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fonts = try ProjectFonts.importFont(from: Self.systemFont, projectRoot: root)
        #expect(fonts.map(\.postScriptName) == ["Georgia-Bold"])
        #expect(fonts.first?.covers("vi") == true)
        #expect(fonts.first?.covers("ja") == false)
        #expect(fonts.first?.covers("xx") == nil)
        #expect(fonts.first?.json(language: "vi").object["covers"] == .bool(true))
        #expect(fonts.first?.json().object["covers"] == nil)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("fonts/Georgia Bold.ttf").path))
        let own = ProjectFonts.list(projectRoot: root, installed: false)
        #expect(own.map(\.postScriptName) == ["Georgia-Bold"])
        #expect(own.first?.json().object["source"] == .string("project"))
        #expect(ProjectFonts.list(projectRoot: root).first?.postScriptName == "Georgia-Bold")
        #expect(ProjectFonts.activate(projectRoot: root).map(\.postScriptName) == ["Georgia-Bold"])

        let text = root.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: text)
        #expect(throws: ProjectFonts.FontError.self) { try ProjectFonts.importFont(from: text, projectRoot: root) }
        let fake = root.appendingPathComponent("fake.ttf")
        try Data("not a font".utf8).write(to: fake)
        #expect(throws: ProjectFonts.FontError.self) { try ProjectFonts.importFont(from: fake, projectRoot: root) }
    }

    @Test("A text preset saved to This Mac carries its project font file into another project")
    func presetFontTravels() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("preset-font-\(UUID().uuidString)")
        defer {
            ProjectFonts.activate(projectRoot: nil)
            try? FileManager.default.removeItem(at: scratch)
        }
        let first = scratch.appendingPathComponent("first"), second = scratch.appendingPathComponent("second")
        for folder in [first, second] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try ProjectFonts.importFont(from: Self.systemFont, projectRoot: first)
        let own = try #require(ProjectFonts.file(named: "Georgia-Bold", projectRoot: first))
        #expect(own.lastPathComponent == "Georgia Bold.ttf" && ProjectFonts.file(named: "Georgia", projectRoot: first) == nil)

        // Saved to the user library with the font file, as the app does for a preset naming a project font.
        let user = LibraryStore(root: scratch.appendingPathComponent("user"), scope: .user)
        let preset = LibraryItem(id: "serif-title", kind: .textPreset, name: "Serif title", params: [
            "textPreset": .string("bold-outline"), "textStyle": .object(["font": .string("Georgia-Bold")]),
        ])
        let saved = try user.add(preset, file: own)
        let stored = try #require(saved.file.map(user.url(of:)))
        #expect(FileManager.default.fileExists(atPath: stored.path))

        // Used in another project: copied into its fonts folder once.
        #expect(ProjectFonts.file(named: "Georgia-Bold", projectRoot: second) == nil)
        #expect(try ProjectFonts.adopt(stored, name: "Georgia-Bold", projectRoot: second).map(\.postScriptName) == ["Georgia-Bold"])
        #expect(ProjectFonts.file(named: "Georgia-Bold", projectRoot: second) != nil)
        #expect(try ProjectFonts.adopt(stored, name: "Georgia-Bold", projectRoot: second).isEmpty)
        // A preset whose font changed since it was saved does not bring the old file.
        let third = scratch.appendingPathComponent("third")
        try FileManager.default.createDirectory(at: third, withIntermediateDirectories: true)
        #expect(try ProjectFonts.adopt(stored, name: "Avenir-Black", projectRoot: third).isEmpty)
        #expect(ProjectFonts.files(projectRoot: third).isEmpty)
    }

    @Test("A name that resolves to the fallback is not available")
    func availability() {
        #expect(ProjectFonts.isAvailable("Arial-BoldMT"))
        #expect(!ProjectFonts.isAvailable("BashCutNoSuchFont-Bold"))
    }

    @Test("System- names draw with the Mac's system font at that width and weight, and cover Vietnamese")
    func systemFonts() {
        #expect(ProjectFonts.isAvailable("System-CondensedBlack") && !ProjectFonts.isAvailable("System-Wide"))
        let font = ProjectFonts.font("System-CondensedBlack", size: 40)
        #expect((CTFontCopyFullName(font) as String).contains("Condensed Black"))
        #expect(ProjectFonts.covers("System-CondensedBlack", language: "vi") == true)
        #expect(ProjectFonts.missingCharacters("System-Black", text: "BẮT HEO RỪNG Ở").isEmpty)
        // Emoji draw in Apple Color Emoji whatever the font: never missing glyphs of a text font.
        #expect(ProjectFonts.missingCharacters("ArialMT", text: "Party 🎉 ✨ ❤️ 1️⃣").isEmpty)
        #expect(ProjectFonts.missingCharacters("ArialMT", text: "1 # *").isEmpty)
        #expect(ProjectFonts.missingCharacters("ArialMT", text: "漢字") == "漢字")
        #expect(ProjectFonts.installed.first?.postScriptName == "System-Regular")
    }
}
