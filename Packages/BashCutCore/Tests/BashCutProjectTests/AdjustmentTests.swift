import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

@Suite("Adjustment layers and style kits")
struct AdjustmentTests {
    private func caption(_ id: String, at: Int, style: String? = nil) -> Item {
        var item = Item(id: id, at: at, duration: 30)
        item["text"] = .string("Caption \(id)")
        if let style { item["style"] = .string(style) }
        return item
    }

    @Test("Adjustment layers sit above the picture, below text, and hold only color items")
    func layerRules() throws {
        let project = try ProjectFixtures.twoClips()
        #expect(project.newTrackID(kind: Track.adjustmentKind) == "fx1")
        #expect(project.defaultTrackIndex(kind: Track.adjustmentKind) == 2)
        let track = Track(id: "fx1", kind: Track.adjustmentKind, role: TrackRole.adjustment)
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

    @Test("A style kit grades the whole video, restyles captions, and replaces an earlier kit")
    func styleKits() throws {
        var project = try ProjectFixtures.twoClips().applying(
            .group(label: "Captions", author: .user, ops: [
                .insert(track: "t1", item: caption("c1", at: 0)),
                .insert(track: "t1", item: caption("c2", at: 60, style: "cinematic-serif")),
                .insert(track: "t1", item: caption("title", at: 90, style: "hook-title")),
            ])
        ).project
        #expect(throws: ProjectError.invalid("Add clips before applying a style kit")) {
            try Project(name: "Empty").styleKitOperations(StyleKit.all[0])
        }
        let cinematic = try #require(StyleKit.named("cinematic"))
        project = try project.applying(
            .group(label: "Kit", author: .user, ops: project.styleKitOperations(cinematic, itemID: "kit1"))
        ).project
        let grade = try #require(project.track(id: "fx1")?.items.first)
        #expect(grade.id == "kit1" && grade.at == 0 && grade.end == 120)
        #expect(grade["color"] == .object(cinematic.look.color))
        #expect(grade.adjustmentTitle(luts: []) == "Cinematic")
        func styles(_ project: Project) -> [String?] { project.track(id: "t1")?.items.map { $0["style"]?.string } ?? [] }
        #expect(styles(project) == ["cinematic-serif", "cinematic-serif", "hook-title"])

        // Re-applying with a longer timeline replaces the kit item instead of stacking a second grade.
        project = try project.applying(
            .insert(track: "v2", item: Item(id: "late", media: "m", at: 120, duration: 30))
        ).project
        let food = try #require(StyleKit.named("food-review"))
        project = try project.applying(
            .group(label: "Kit", author: .user, ops: project.styleKitOperations(food, itemID: "kit2"))
        ).project
        let grades = project.tracks.filter(\.isAdjustment).flatMap(\.items)
        #expect(grades.map(\.id) == ["kit2"])
        #expect(grades.first?.end == 150)
        #expect(styles(project) == ["bold-outline", "bold-outline", "hook-title"])
    }

    @Test("Adjustment titles name the kit, LUT or look")
    func titles() {
        let lut = ColorLUT(id: "warm", name: "Warm sunset", path: "luts/warm.cube", size: 33)
        #expect(Item.adjustment(at: 0, duration: 1).adjustmentTitle(luts: []) == "Adjustment")
        let muted = Item.adjustment(at: 0, duration: 1, color: ColorLook.named("muted-film")!.color)
        #expect(muted.adjustmentTitle(luts: []) == "Muted film")
        let graded = Item.adjustment(at: 0, duration: 1, color: ["lut": .string("warm"), "lutStrength": .number(0.5)])
        #expect(graded.adjustmentTitle(luts: [lut]) == "Warm sunset")
    }

    @Test("v2 projects migrate to v3 and drop the unused style setting")
    func migration() throws {
        var legacy = Project(name: "Legacy")
        legacy["schema"] = .string("bashcut.project/2")
        legacy["style"] = .string("cinematic")
        legacy["custom"] = .string("kept")
        let migrated = try Project.decode(try JSONEncoder().encode(legacy))
        #expect(migrated["schema"] == .string(Project.schema))
        #expect(migrated["style"] == nil)
        #expect(migrated["custom"] == .string("kept"))
        #expect(Project(name: "New")["style"] == nil)
    }
}
