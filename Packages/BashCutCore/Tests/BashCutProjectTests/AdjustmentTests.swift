import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

@Suite("Adjustment layers and style kits")
struct AdjustmentTests {
    private func caption(_ id: String, at: Int, style: String? = nil) -> Item {
        var item = Item(id: id, at: at, duration: 30)
        item["text"] = .string("Caption \(id)")
        if let style { item["textPreset"] = .string(style) }
        return item
    }

    @Test("Adjustment layers sit above the picture, below text, and hold only color items")
    func layerRules() throws {
        let project = try ProjectFixtures.twoClips()
        #expect(project.newTrackID(kind: TrackKind.adjustment) == "fx1")
        #expect(project.defaultTrackIndex(kind: TrackKind.adjustment) == 2)
        let track = Track(id: "fx1", kind: TrackKind.adjustment, role: TrackRole.adjustment)
        let layered = try project.applying(.addTrack(track: track, atIndex: 2)).project
        #expect(layered.tracks.map(\.id).prefix(4) == ["v1", "v2", "fx1", "t1"])
        // New video layers go behind adjustments so they are graded too.
        #expect(layered.defaultTrackIndex(kind: "video") == 2)

        let graded = try layered.applying(
            .insert(track: "fx1", item: .adjustment(id: "g", at: 0, duration: 60, color: ["saturation": .integer(0)]))
        ).project
        #expect(graded.track(id: "fx1")?.items.first?["color"] == .object(["saturation": .integer(0)]))
        #expect(throws: ProjectError.self) {
            try layered.applying(.insert(track: "fx1", item: Item(id: "x", media: "m", at: 0, duration: 30)))
        }
        #expect(throws: ProjectError.self) {
            try layered.applying(.insert(track: "fx1", item: caption("x", at: 0)))
        }
        #expect(throws: ProjectError.self) {
            try graded.applying(.insert(track: "fx1", item: .adjustment(id: "overlap", at: 30, duration: 30)))
        }
        #expect(throws: ProjectError.self) { try graded.applying(.slip(item: "g", sourceIn: 10)) }
        #expect(throws: ProjectError.self) {
            try graded.applying(.setProperties(item: "g", patch: ["color": .object(["lut": .string("missing")])]))
        }
        #expect(throws: ProjectError.self) { try graded.applying(.move(item: "g", toTrack: "v2", atFrame: 0)) }
        #expect(try graded.applying(.split(item: "g", atFrame: 20, newID: "g2")).project.track(id: "fx1")?.items.count == 2)
        #expect(try graded.applying(.setTrackProperties(track: "fx1", patch: ["hidden": .bool(true)])).project
            .track(id: "fx1")?.isHidden == true)
    }

    @Test("Placing an adjustment adds the layer once and spills overlaps onto another adjustment layer")
    func placement() throws {
        var planner = LayerPlanner(try ProjectFixtures.twoClips())
        #expect(try planner.placeAdjustment(.adjustment(id: "a", at: 0, duration: 60)) == "fx1")
        #expect(try planner.placeAdjustment(.adjustment(id: "b", at: 60, duration: 60)) == "fx1")
        #expect(try planner.placeAdjustment(.adjustment(id: "c", at: 30, duration: 60)) == "fx2")
        let project = planner.project
        #expect(project.tracks.filter(\.isAdjustment).map(\.id) == ["fx1", "fx2"])
        #expect(project.tracks.firstIndex { $0.id == "fx2" }! < project.tracks.firstIndex { $0.id == "t1" }!)
        #expect(project.contentDuration == 120)
    }

    @Test("Adjustment titles name the LUT or the built-in look")
    func titles() throws {
        var project = Project(name: "Titles")
        project = try project.applying(.addColorLUT(ColorLUT(id: "warm", name: "Warm sunset", path: "luts/warm.cube", size: 33))).project
        #expect(Item.adjustment(at: 0, duration: 1).adjustmentTitle(in: project) == "Adjustment")
        let look = try #require(LibraryBuiltIns.looks.first { $0.id == "muted-film" })
        let muted = Item.adjustment(at: 0, duration: 1, color: try #require(look.params["color"]?.object))
        #expect(muted.adjustmentTitle(in: project) == "Muted film")
        let graded = Item.adjustment(at: 0, duration: 1, color: ["lut": .string("warm"), "lutStrength": .number(0.5)])
        #expect(graded.adjustmentTitle(in: project) == "Warm sunset")
        #expect(Item.adjustment(at: 0, duration: 1, color: ["saturation": .number(1.3)]).adjustmentTitle(in: project)
            == "Adjustment")
    }

    @Test("Old projects keep their looks and style kits fields as they were (C8)")
    func legacyCatalog() throws {
        var project = try ProjectFixtures.twoClips()
        project["looks"] = .array([.object(["id": .string("warm"), "title": .string("Warm"), "color": .object([:])])])
        project["styleKits"] = .array([.object(["id": .string("x"), "look": .string("missing")])])
        try project.validate()
        let data = try JSONEncoder().encode(project)
        #expect(try JSONDecoder().decode(Project.self, from: data)["styleKits"] == project["styleKits"])
    }
}
