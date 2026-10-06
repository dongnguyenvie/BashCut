import Foundation
import Testing

@testable import BashCutProject

@Suite("Text preset items keep their text style (#380)")
struct LibraryTextPresetTests {
    /// A project with the text item `t` on the Captions layer.
    private func project(_ text: Item) throws -> Project {
        let base = Project(name: "Text", fps: FrameRate(30, 1))
        return try base.applying(.insert(track: base.requireTrack(role: TrackRole.captions).id, item: text)).project
    }

    private func text(_ style: [String: JSONValue]? = nil, preset: String = "hook-title") -> Item {
        var item = Item(id: "t", at: 0, duration: 60)
        item["text"] = .string("Hello")
        item["textPreset"] = .string(preset)
        if let style { item["textStyle"] = .object(style) }
        return item
    }

    private func item(_ project: Project, _ id: String = "t") throws -> Item {
        try #require(project.tracks.flatMap(\.items).first { $0.id == id })
    }

    @Test("Save selection keeps the declared textStyle fields and a motion preset; placing gives them back")
    func roundTrip() throws {
        var styled = text([
            "size": .number(0.0712345), "positionY": .number(0.4), "strokeWidth": .integer(6),
            "highlight": .string("#FF0000"),
        ])
        let base = try project(styled)
        styled["keyframes"] = try MotionPreset.motion(
            "pop-in", duration: 60, width: base.width, height: base.height, fps: base.fps
        ).json
        let params = try LibrarySelection.params(.textPreset, item: styled, project: base)
        #expect(params == [
            "textPreset": .string("hook-title"), "text": .string("Hello"), "animation": .string("pop-in"),
            "textStyle": .object(["size": .number(0.0712), "positionY": .number(0.4), "strokeWidth": .integer(6)]),
        ])
        try LibraryItem(id: "styled", kind: .textPreset, name: "Styled", params: params).validate()

        // Placed on another item: same style, and the animation fits its own length.
        var placed = Item(id: "p", at: 0, duration: 90)
        placed["text"] = .string("Other")
        let patch = try LibraryTextPreset(params: params).patch(for: placed, project: base)
        for (key, value) in patch { placed[key] = value }
        #expect(placed["textStyle"] == params["textStyle"])
        #expect(placed.motion == (try MotionPreset.motion(
            "pop-in", duration: 90, width: base.width, height: base.height, fps: base.fps)))
        #expect(LibraryTextPreset(item: placed, project: base).params() == params.merging(["text": .string("Other")]) { $1 })
    }

    @Test("Hand-made keys are not an animation; a preset at another length is not either")
    func keysThatAreNotAPreset() throws {
        var item = text()
        let base = try project(item)
        item["keyframes"] = ItemMotion(keys: ["opacity": [.init(frame: 0, value: 0.5)]]).json
        #expect(LibraryTextPreset(item: item, project: base).animation == nil)
        item["keyframes"] = try MotionPreset.motion(
            "fade-in-out", duration: 30, width: base.width, height: base.height, fps: base.fps).json
        #expect(LibraryTextPreset(item: item, project: base).animation == nil)
        #expect(LibraryTextPreset(item: item, project: nil).animation == nil)
    }

    @Test("Apply sets the preset, the stored style over the item's and the animation in one undoable edit")
    func applyIsOneStep() throws {
        let base = try project(text(["positionY": .number(0.2), "highlight": .string("#FF0000")], preset: "bold-outline"))
        let style = LibraryTextPreset(
            textPreset: "place-card", text: "Sample", textStyle: ["size": .number(0.08), "positionY": .number(0.7)],
            animation: "fade-in-out")
        let result = try base.applying(.setProperties(item: "t", patch: style.patch(for: item(base), project: base)))
        let applied = try item(result.project)
        #expect(applied.textPreset == "place-card")
        #expect(applied.text == "Hello")
        #expect(applied["textStyle"] == .object([
            "size": .number(0.08), "positionY": .number(0.7), "highlight": .string("#FF0000"),
        ]))
        #expect(applied.motion != nil)
        #expect(try result.project.applying(result.inverse).project.tracks == base.tracks)
    }

    @Test("Items without a style behave as before: only the preset changes")
    func oldItems() throws {
        let old = LibraryBuiltIns.textPresets[0]
        let style = try LibraryTextPreset(params: old.params)
        #expect(style.params(merging: old.params) == old.params)
        let base = try project(text(["size": .number(0.1)]))
        #expect(try style.patch(for: item(base), project: base) == ["textPreset": .string("bold-outline")])
        for item in LibraryBuiltIns.textPresets { try item.validate() }
    }

    @Test("textStyle and animation are checked with the item property ranges")
    func validation() throws {
        let bad: [[String: JSONValue]] = [
            ["textStyle": .string("big")],
            ["textStyle": .object(["size": .number(2)])],
            ["textStyle": .object(["strokeWidth": .number(-1)])],
            ["textStyle": .object(["positionY": .string("top")])],
            ["textStyle": .object(["font": .string("Arial")])],
            ["animation": .string("spin")],
            ["text": .integer(1)],
        ]
        for extra in bad {
            let params = ["textPreset": JSONValue.string("bold-outline")].merging(extra) { $1 }
            #expect(throws: ProjectError.self, "\(extra)") {
                try LibraryItem(id: "x", kind: .textPreset, name: "X", params: params).validate()
            }
        }
        let good = try LibraryTextPreset(params: [
            "textPreset": .string("chapter-card"), "textStyle": .object(["size": .number(1), "strokeWidth": .integer(0)]),
            "animation": .string("none"), "note": .string("kept"),
        ])
        #expect(good.animation == nil)
        #expect(good.params(merging: ["note": .string("kept")])["note"] == .string("kept"))
    }

    @Test("Duplicates are found by style: the same style twice is one group, another size is not")
    func duplicates() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("text-preset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalog = LibraryCatalog(
            builtIn: [], user: .user(applicationSupport: folder.appendingPathComponent("support")),
            project: .project(root: folder.appendingPathComponent("project")))
        func styled(_ id: String, size: Double) -> LibraryItem {
            LibraryItem(id: id, kind: .textPreset, name: id, params: LibraryTextPreset(
                textPreset: "hook-title", text: "Hi", textStyle: ["size": .number(size)]).params())
        }
        for item in [styled("a", size: 0.08), styled("b", size: 0.08), styled("c", size: 0.09)] {
            try catalog.add(item, into: .project)
        }
        #expect(try catalog.stats().object["duplicates"] == .array([.array([.string("project:a"), .string("project:b")])]))
    }
}
