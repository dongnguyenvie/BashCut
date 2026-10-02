import BashCutProject
import Foundation
import Testing

@Suite("Layer rules")
struct LayerRulesTests {
    private func media(_ id: String, kind: String = "video", hasAudio: Bool = true) -> Media {
        Media(fields: [
            "id": .string(id), "path": .string("\(id).mov"), "kind": .string(kind), "fps": FrameRate().json,
            "frames": .integer(600), "hasAudio": .bool(hasAudio),
        ])
    }

    private func project(media assets: [Media] = []) throws -> Project {
        var project = Project(name: "Layers")
        for asset in assets { project = try project.applying(.addMedia(asset)).project }
        return project
    }

    @Test("Visual layers stay above audio layers and the main layer is unique and permanent")
    func bandsAndMain() throws {
        let project = try project()
        #expect(throws: ProjectError.self) { try project.applying(.moveTrack(track: "a1", toIndex: 0)) }
        #expect(throws: ProjectError.self) { try project.applying(.moveTrack(track: "v2", toIndex: 5)) }
        #expect(throws: ProjectError.self) {
            try project.applying(.addTrack(track: Track(id: "v9", kind: "video", role: "overlay"), atIndex: 7))
        }
        #expect(throws: ProjectError.self) {
            try project.applying(.addTrack(track: Track(id: "v9", kind: "video", role: "main"), atIndex: 1))
        }
        #expect(throws: ProjectError.invalid("The main layer cannot be deleted")) {
            try project.applying(.deleteTrack(track: "v1"))
        }
        #expect(try project.applying(.moveTrack(track: "t1", toIndex: 1)).project.tracks[1].id == "t1")
        #expect(project.trackBand(kind: "audio") == 3..<7)
        #expect(project.defaultTrackIndex(kind: "text") == 3)
        // New video layers stay behind text layers; audio layers go to the bottom.
        #expect(project.defaultTrackIndex(kind: "video") == 2)
        #expect(project.defaultTrackIndex(kind: "audio") == 7)
        #expect(throws: ProjectError.invalid("Layer a1 is audio; audio layers stay below visual layers")) {
            try project.applying(.moveTrack(track: "a1", toIndex: 0))
        }
    }

    @Test("Items never overlap on one layer and media must suit the layer kind")
    func overlapAndKinds() throws {
        let project = try project(media: [media("clip"), media("song", kind: "audio"), media("mute", hasAudio: false)])
        let first = try project.applying(.insert(track: "v2", item: Item(id: "a", media: "clip", at: 0, duration: 30))).project
        #expect(throws: ProjectError.self) {
            try first.applying(.insert(track: "v2", item: Item(id: "b", media: "clip", at: 29, duration: 30)))
        }
        #expect(try first.applying(.insert(track: "v2", item: Item(id: "b", media: "clip", at: 30, duration: 30))).project
            .tracks[1].items.count == 2)
        #expect(throws: ProjectError.self) {
            try project.applying(.insert(track: "v2", item: Item(id: "s", media: "song", at: 0, duration: 30)))
        }
        #expect(throws: ProjectError.self) {
            try project.applying(.insert(track: "a3", item: Item(id: "m", media: "mute", at: 0, duration: 30)))
        }
        #expect(try project.applying(.insert(track: "a3", item: Item(id: "c", media: "clip", at: 0, duration: 30))).project
            .tracks[5].items.count == 1)
    }

    @Test("Placing on an occupied range spills onto a free layer, then onto a new layer next to it")
    func plannerSpills() throws {
        var planner = LayerPlanner(try project(media: [media("clip", hasAudio: false)]))
        try planner.place(Item(id: "a", media: "clip", at: 0, duration: 60), on: "v2")
        #expect(try planner.place(Item(id: "b", media: "clip", at: 30, duration: 60), on: "v2") == "v3")
        #expect(planner.project.tracks.map(\.id) == ["v1", "v2", "v3", "t1", "a1", "a2", "a3", "a4"])
        #expect(planner.project.tracks[2].role == "overlay")
        #expect(planner.project.tracks[2].name == "Overlay 2")
        #expect(!planner.project.tracks[2].magnetic)
        // A third overlapping clip reuses no occupied layer and adds another one after the earlier overflow.
        #expect(try planner.place(Item(id: "c", media: "clip", at: 40, duration: 10), on: "v2") == "v4")
        #expect(planner.project.tracks.map(\.id) == ["v1", "v2", "v3", "v4", "t1", "a1", "a2", "a3", "a4"])
        #expect(planner.project.tracks[3].name == "Overlay 3")
        // A free range on the first layer stays there.
        #expect(try planner.place(Item(id: "d", media: "clip", at: 100, duration: 10), on: "v2") == "v2")
        let result = try planner.project.applying(.group(label: "x", author: .user, ops: [])).project
        try result.validate()
    }

    @Test("Moving onto an occupied range spills picture and linked sound onto free layers")
    func plannerMovesLinkedItems() throws {
        let base = try project(media: [media("clip"), media("other")])
        var planner = LayerPlanner(base)
        try planner.placeMedia(media("clip"), on: "v1", at: 0, duration: 30, itemID: "a")
        try planner.placeMedia(media("other"), on: "v2", at: 60, duration: 30, itemID: "b")
        #expect(planner.project.track(id: "a1")?.items.map(\.id).sorted() == ["a-audio", "b-audio"])
        let placed = planner.project
        var mover = LayerPlanner(placed)
        try mover.move("a", to: "v2", at: 70)
        let moved = mover.project
        let video = try #require(moved.tracks.first { $0.items.contains { $0.id == "a" } })
        let audio = try #require(moved.tracks.first { $0.items.contains { $0.id == "a-audio" } })
        #expect(video.id == "v3")
        #expect(audio.kind == "audio" && audio.role == "dialogue" && audio.id != "a1")
        #expect(moved.tracks.filter { $0.role == "dialogue" }.map(\.name) == ["Dialogue", "Dialogue 2"])
        #expect(moved.tracks.flatMap(\.items).first { $0.id == "a-audio" }?.at == 70)
        #expect(moved.tracks.flatMap(\.items).first { $0.id == "a" }?.linkedItemID == "a-audio")
        try moved.validate()
    }

    @Test("Overlapping SRT cues import onto stacked caption layers")
    func overlappingCaptions() throws {
        let text = """
            1
            00:00:00,000 --> 00:00:02,000
            Một

            2
            00:00:01,000 --> 00:00:03,000
            Hai

            """
        let project = try Project(name: "Captions").applying(Project(name: "Captions").importingSubRip(text)).project
        let layers = project.tracks.filter { $0.role == "captions" }
        #expect(layers.map { $0.items.map(\.text) } == [["Một"], ["Hai"]])
        #expect(project.tracks.firstIndex { $0.id == layers[1].id } == 3)
    }

    @Test("Projects saved before layer rules are repaired on load; valid projects are unchanged")
    func normalization() throws {
        let valid = try project(media: [media("clip")])
        #expect(valid.normalizingLayers() == valid)

        var legacy = valid
        var tracks = legacy.tracks
        tracks[1].items = [
            Item(id: "o1", media: "clip", at: 0, duration: 40), Item(id: "o2", media: "clip", at: 20, duration: 40),
            Item(id: "o3", media: "clip", at: 50, duration: 10),
        ]
        tracks[2].fields["role"] = .string("main")
        tracks[2].fields["kind"] = .string("text")
        legacy.tracks = [tracks[3]] + tracks.filter { $0.id != "a1" }
        let data = try JSONEncoder().encode(legacy)
        let repaired = try Project.decode(data)
        #expect(repaired.tracks.map(\.kind) == ["video", "video", "video", "text", "audio", "audio", "audio", "audio"])
        #expect(repaired.tracks.filter { $0.role == "main" }.map(\.id) == ["v1"])
        #expect(repaired.tracks[1].items.map(\.id) == ["o1", "o3"])
        #expect(repaired.tracks[2].items.map(\.id) == ["o2"])
        #expect(repaired.tracks[3].role == "overlay")

        var mainless = valid
        mainless.tracks = valid.tracks.filter { $0.role != "main" }
        let withMain = mainless.normalizingLayers()
        #expect(withMain.tracks[0].role == "main" && withMain.tracks[0].magnetic)
        try withMain.validate()
    }
}
