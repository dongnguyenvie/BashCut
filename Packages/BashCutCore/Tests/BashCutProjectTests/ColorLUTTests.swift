import Testing
@testable import BashCutProject

@Test("LUT catalog entries and clip references validate and undo exactly")
func colorLUTCatalog() throws {
    let media = Media(fields: [
        "id": .string("m"), "path": .string("a.mov"), "fps": FrameRate(30, 1).json,
        "frames": .integer(120),
    ])
    var project = Project(name: "LUT", fps: FrameRate(30, 1))
    project = try project.applying(.group(label: "fixture", author: .user, ops: [
        .addMedia(media), .addColorLUT(ColorLUT(id: "look", name: "Look", path: "luts/look.cube", size: 2)),
        .insert(track: "v1", item: Item(id: "clip", media: "m", at: 0, duration: 60)),
        .setProperties(
            item: "clip", patch: ["color": .object(["lut": .string("look"), "lutStrength": .number(0.5)])]),
    ])).project
    let deleted = try project.applying(.deleteColorLUT(id: "look"))
    #expect(deleted.project.colorLUTs.isEmpty)
    #expect(deleted.project.tracks[0].items[0]["color"]?.object["lut"] == nil)
    let restored = try deleted.project.applying(deleted.inverse).project
    #expect(restored.colorLUTs.first?.id == "look")
    #expect(restored.tracks[0].items[0]["color"]?.object["lut"] == .string("look"))
    // The reference must be the catalog ID, not a copy of the entry.
    #expect(throws: ProjectError.self) {
        try project.applying(.setProperties(
            item: "clip", patch: ["color": .object(["lut": .object(["id": .string("look")])])]))
    }
}

@Test("LUT paths are confined to the project LUT directory")
func rejectsUnsafeColorLUT() {
    let project = Project(name: "LUT")
    #expect(throws: ProjectError.self) {
        try project.applying(
            .addColorLUT(ColorLUT(id: "bad", name: "Bad", path: "../bad.cube", size: 2)))
    }
}
