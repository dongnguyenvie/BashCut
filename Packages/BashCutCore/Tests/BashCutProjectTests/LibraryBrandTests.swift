import Foundation
import Testing

@testable import BashCutProject

@Suite("Brand kits restyle text tied to roles (#453)")
struct LibraryBrandTests {
    private let warm: [String: JSONValue] = [
        "palette": .object(["accent": .string("#FFB000"), "text": .string("#1A1A1A"), "background": .string("#F4E9D8")]),
        "fonts": .object(["heading": .string("BeVietnamPro-Black")]),
        "logo": .string("acme-logo"), "mascot": .object(["wave": .string("project:owl-wave")]),
        "voice": .object(["provider": .string("bashcut.vieneu-tts.speak"), "voice": .string("ngoc")]),
        "disclosure": .string("Ảnh tạo bằng AI"),
    ]
    private let cool: [String: JSONValue] = [
        "palette": .object(["accent": .string("#00C2FF"), "text": .string("#FFFFFF")]),
    ]

    /// A chip tied to roles, and a plain title that is not.
    private func project() throws -> Project {
        let base = Project(name: "Brand", fps: FrameRate(30, 1))
        let captions = try base.requireTrack(role: TrackRole.captions).id
        var chip = Item(id: "chip", at: 0, duration: 60)
        chip["text"] = .string("1/6")
        chip["textStyle"] = .object([
            "fill": .string("#000000"), "size": .number(0.04),
            "background": .object(["color": .string("#FFFFFF"), "opacity": .number(0.9)]),
            "accentBars": .array([.object(["side": .string("left"), "color": .string("#FF0000")])]),
        ])
        chip["brandRoles"] = .object([
            "fill": .string("text"), "background.color": .string("accent"), "accentBars.color": .string("text"),
            "font": .string("heading"),
        ])
        var plain = Item(id: "plain", at: 60, duration: 60)
        plain["text"] = .string("Hello")
        plain["textStyle"] = .object(["fill": .string("#123456")])
        return try base.applying(.group(label: "Text", author: .user, ops: [
            .insert(track: captions, item: chip), .insert(track: captions, item: plain),
        ])).project
    }

    private func style(_ project: Project, _ id: String) -> [String: JSONValue] {
        project.tracks.flatMap(\.items).first { $0.id == id }?["textStyle"]?.object ?? [:]
    }

    @Test("A kit needs one known field; colours are #RRGGBB, references library ids, roles known")
    func validation() throws {
        let kit = try LibraryBrand(params: warm)
        #expect(kit.value(of: "accent") == "#FFB000" && kit.value(of: "heading") == "BeVietnamPro-Black")
        try LibraryItem(id: "warm", kind: .brand, name: "Warm", params: warm).validate()
        for bad: [String: JSONValue] in [
            [:],
            ["palette": .object(["accent": .string("orange")])],
            ["palette": .object(["glow": .string("#FFFFFF")])],
            ["fonts": .object(["heading": .string("")])],
            ["logo": .string("../logo.png")],
            ["mascot": .object(["wave": .integer(1)])],
            ["voice": .object(["speed": .string("1.2")])],
            ["disclosure": .string(String(repeating: "x", count: 201))],
        ] {
            #expect(throws: ProjectError.self) { try LibraryBrand(params: bad) }
        }
        #expect(throws: ProjectError.self) {
            try LibraryBrand.validateRoles(.object(["size": .string("accent")]), label: "roles")
        }
        #expect(throws: ProjectError.self) {
            try LibraryBrand.validateRoles(.object(["font": .string("accent")]), label: "roles")
        }
    }

    @Test("Applying a kit sets brand and restyles only tied paths; a second kit restyles again; undo restores")
    func applying() throws {
        var project = try project()
        let warmEdit = try project.applying(.group(
            label: "Brand", author: .user,
            ops: try project.brandOperations(warm, reference: "project:warm", name: "Warm")))
        let before = project
        project = warmEdit.project
        let chip = style(project, "chip")
        #expect(chip["fill"] == .string("#1A1A1A") && chip["font"] == .string("BeVietnamPro-Black"))
        #expect(chip["background"]?.object["color"] == .string("#FFB000"))
        #expect(chip["background"]?.object["opacity"] == .number(0.9))
        #expect(chip["accentBars"]?.array.first?.object["color"] == .string("#1A1A1A"))
        #expect(chip["size"] == .number(0.04))
        #expect(style(project, "plain") == ["fill": .string("#123456")])
        #expect(project.brand?.value(of: "accent") == "#FFB000")
        #expect(project["brand"]?.object["library"] == .string("project:warm"))
        try project.validate()

        // The cool kit leaves the font unset: the chip keeps the warm font and takes the new colours.
        project = try project.applying(.group(
            label: "Brand", author: .user,
            ops: try project.brandOperations(cool, reference: "project:cool", name: "Cool"))).project
        #expect(style(project, "chip")["fill"] == .string("#FFFFFF"))
        #expect(style(project, "chip")["font"] == .string("BeVietnamPro-Black"))
        #expect(style(project, "chip")["background"]?.object["color"] == .string("#00C2FF"))

        let undone = try warmEdit.project.applying(warmEdit.inverse).project
        #expect(style(undone, "chip") == style(before, "chip") && undone["brand"] == nil)
    }

    @Test("A text preset with brand roles takes the project's kit when placed and keeps the roles")
    func presetFollowsKit() throws {
        var project = try project()
        project = try project.applying(.group(
            label: "Brand", author: .user,
            ops: try project.brandOperations(warm, reference: "project:warm", name: "Warm"))).project
        let preset = try LibraryTextPreset(params: [
            "textPreset": .string("bold-outline"), "textStyle": .object(["fill": .string("#000000")]),
            "brandRoles": .object(["fill": .string("accent"), "highlight": .string("text")]),
        ])
        var target = Item(id: "new", at: 0, duration: 30)
        target["text"] = .string("Hi")
        let patch = try preset.patch(for: target, project: project)
        #expect(patch["brandRoles"]?.object["fill"] == .string("accent"))
        #expect(patch["textStyle"]?.object["fill"] == .string("#FFB000"))
        #expect(patch["textStyle"]?.object["highlight"] == .string("#1A1A1A"))
        #expect(preset.params()["brandRoles"] != nil)
        #expect(throws: ProjectError.self) {
            try LibraryTextPreset(params: ["textPreset": .string("x"), "brandRoles": .object(["fill": .string("heading")])])
        }
    }

    @Test("A plan.cut title with brandRoles in its style takes the project's kit")
    func planTitleFollowsKit() throws {
        var project = try project()
        project = try project.applying(.group(
            label: "Brand", author: .user,
            ops: try project.brandOperations(warm, reference: "project:warm", name: "Warm"))).project
        let patch = try PlanCut.look(
            for: Item(id: "t", at: 0, duration: 30),
            ("bold-outline", ["brandRoles": .object(["fill": .string("accent")])], ["fill": .string("#000000")]),
            textPresets: [:], project: project)
        #expect(patch["textStyle"]?.object["fill"] == .string("#FFB000"))
        #expect(patch["brandRoles"]?.object["fill"] == .string("accent"))
    }

    @Test("Validation rejects a broken brand property or item roles")
    func projectValidation() throws {
        var project = try project()
        project["brand"] = .object(["palette": .object(["accent": .string("#12345")])])
        #expect(throws: ProjectError.self) { try project.validate() }
        #expect(throws: ProjectError.self) {
            try self.project().applying(.setProperties(item: "chip", patch: ["brandRoles": .object(["fill": .string("glow")])]))
        }
        let cleared = try self.project().applying(.setProperties(item: "chip", patch: ["brandRoles": .null])).project
        #expect(cleared.tracks.flatMap(\.items).first { $0.id == "chip" }?["brandRoles"] == nil)
    }
}
