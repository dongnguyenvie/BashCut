import Foundation
import Testing
@testable import BashCutEngine

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
        #expect(fonts.first?.vietnamese == true)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("fonts/Georgia Bold.ttf").path))
        let own = ProjectFonts.list(projectRoot: root, installed: false)
        #expect(own.map(\.postScriptName) == ["Georgia-Bold"])
        #expect(own.first?.json.object["source"] == .string("project"))
        #expect(ProjectFonts.list(projectRoot: root).first?.postScriptName == "Georgia-Bold")
        #expect(ProjectFonts.activate(projectRoot: root).map(\.postScriptName) == ["Georgia-Bold"])

        let text = root.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: text)
        #expect(throws: ProjectFonts.FontError.self) { try ProjectFonts.importFont(from: text, projectRoot: root) }
        let fake = root.appendingPathComponent("fake.ttf")
        try Data("not a font".utf8).write(to: fake)
        #expect(throws: ProjectFonts.FontError.self) { try ProjectFonts.importFont(from: fake, projectRoot: root) }
    }

    @Test("A name that resolves to the fallback is not available")
    func availability() {
        #expect(ProjectFonts.isAvailable("Arial-BoldMT"))
        #expect(!ProjectFonts.isAvailable("BashCutNoSuchFont-Bold"))
    }
}
