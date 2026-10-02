import Foundation
import Testing

@testable import BashCutProject

struct ProjectTests {
    @Test("Color comparison preview bypasses color without mutating project data")
    func colorComparisonPreview() throws {
        var project = try fixture()
        var tracks = project.tracks
        tracks[0].items[0]["color"] = .object([
            "exposure": .number(0.5), "lut": .string("look"),
        ])
        tracks[0].items[0]["futureEffect"] = .string("preserve")
        project.tracks = tracks
        let original = project
        let preview = project.withoutColorEffects()
        #expect(preview.revision == project.revision)
        #expect(preview.tracks[0].items[0]["color"] == nil)
        #expect(preview.tracks[0].items[0]["futureEffect"] == .string("preserve"))
        #expect(preview.tracks[0].items[0].at == project.tracks[0].items[0].at)
        #expect(project == original)
    }

    @Test("Automatic reframing cycles deterministic validated project patches")
    func automaticReframing() throws {
        var item = Item(id: "clip", at: 0, duration: 30)
        var visited: [String] = []
        for _ in ReframePreset.all.indices {
            let preset = ReframePreset.next(after: item)
            visited.append(preset.id)
            for (key, value) in preset.patch { item[key] = value }
        }
        #expect(visited == ReframePreset.all.map(\.id))
        #expect(ReframePreset.next(after: item).id == "wide")

        var project = try fixture()
        let close = try #require(ReframePreset.all.first { $0.id == "close" })
        project = try project.applying(.setProperties(item: "c1", patch: close.patch)).project
        #expect(project.tracks[0].items[0]["reframePreset"] == .string("close"))
        #expect(project.tracks[0].items[0]["transform"]?.object["zoom"] == .number(1.3))
        try project.validate()
    }

    @Test("Track ducking properties are bounded and preserve unknown fields")
    func trackDuckingValidation() throws {
        var project = Project(name: "Ducking")
        #expect(project.tracks[5]["duckUnderSpeechDb"] == .integer(-14))
        var tracks = project.tracks
        tracks[5]["duckUnderSpeechDb"] = .integer(-14)
        tracks[5]["duckAttackFrames"] = .integer(3)
        tracks[5]["duckReleaseFrames"] = .integer(8)
        tracks[5]["futureDuckingMode"] = .string("adaptive")
        project.tracks = tracks
        try project.validate()
        #expect(project.tracks[5]["futureDuckingMode"] == .string("adaptive"))

        tracks[5]["duckUnderSpeechDb"] = .integer(4)
        project.tracks = tracks
        #expect(throws: ProjectError.self) { try project.validate() }
    }

    @Test("Project audio normalization settings are undoable and bounded")
    func audioNormalizationSettings() throws {
        let project = Project(name: "Normalize")
        let audio: JSONValue = .object([
            "targetLUFS": .integer(-16), "normalizeEnabled": .bool(true),
            "mixGainDb": .number(2.5), "measuredLUFS": .number(-16.1),
            "truePeakDbTP": .number(-1.2), "measurementVerified": .bool(true),
        ])
        let changed = try project.applying(.setProjectProperties(patch: ["audio": audio]))
        #expect(changed.project.targetLUFS == -16)
        #expect(changed.project.mixGainDb == 2.5)
        let restored = try changed.project.applying(changed.inverse).project
        #expect(restored["audio"] == project["audio"])
        #expect(throws: ProjectError.self) {
            try project.applying(.setProjectProperties(patch: [
                "audio": .object(["targetLUFS": .integer(0)])
            ]))
        }
    }

    @Test("Unsafe render properties fail atomically while unknown fields remain allowed")
    func renderProperties() throws {
        var history = ProjectHistory(project: try fixture())
        let original = history.project
        let invalid: [[String: JSONValue]] = [
            ["transform": .object(["zoom": .number(.infinity)])],
            ["transform": .object(["zoom": .integer(-1)])], ["transform": .array([])],
            ["opacity": .number(1.1)], ["volumeDb": .integer(9999)], ["speed": .string("fast")],
            ["fadeIn": .number(0.5)], ["muted": .string("yes")],
            ["color": .object(["saturation": .number(.nan)])],
            ["textStyle": .object(["size": .integer(-100)])],
        ]
        for patch in invalid {
            #expect(throws: ProjectError.self) {
                try history.apply(.setProperties(item: "c1", patch: patch), label: "Invalid")
            }
            #expect(history.project == original)
            #expect(history.undoEntries.isEmpty)
        }
        try history.apply(
            .setProperties(item: "c1", patch: ["future": .object(["feature": .string("keep")])]),
            label: "Future")
        #expect(history.project.tracks[0].items[0]["future"] != nil)
    }
    private func fixture() throws -> Project {
        let project = Project(name: "Vietnamese captions")
        let media = Media(fields: [
            "id": .string("m1"), "path": .string("footage/one.mov"),
            "fps": FrameRate(60_000, 1_001).json, "frames": .integer(1200),
        ])
        return try project.applying(
            .group(
                label: "Import", author: .user,
                ops: [
                    .addMedia(media),
                    .insert(track: "v1", item: Item(id: "c1", media: "m1", at: 0, duration: 120)),
                    .insert(track: "v1", item: Item(id: "c2", media: "m1", at: 120, duration: 60)),
                ])
        ).project
    }

    @Test("Every basic operation has an exact inverse and monotonic revision")
    func inverses() throws {
        let project = try fixture()
        let operations: [EditOperation] = [
            .insert(track: "v1", item: Item(id: "c3", media: "m1", at: 180, duration: 30)),
            .delete(item: "c1", ripple: true), .delete(item: "c1", ripple: false),
            .split(item: "c1", atFrame: 50, newID: "right"),
            .trim(item: "c1", edge: .start, toFrame: 30, ripple: true),
            .trim(item: "c1", edge: .end, toFrame: 90, ripple: true),
            .move(item: "c1", toTrack: "v2", atFrame: 10),
            .setProperties(item: "c1", patch: ["transform": .object(["zoom": .number(1.2)])]),
        ]
        for operation in operations {
            let applied = try project.applying(operation)
            var restored = try applied.project.applying(applied.inverse).project
            #expect(restored.revision == project.revision + 2)
            restored.revision = project.revision
            #expect(restored == project)
        }
    }

    @Test("Split uses source FPS and preserves the left identity")
    func sourceFrames() throws {
        let project = try fixture().applying(.split(item: "c1", atFrame: 50, newID: "right")).project
        #expect(project.tracks[0].items[0].id == "c1")
        #expect(project.tracks[0].items[1].sourceIn == 100)
        #expect(project.tracks[0].items[1].duration == 70)
    }

    @Test("Beat grids are validated, undoable and retain provider provenance")
    func beatGrid() throws {
        let project = try fixture()
        let provenance: [String: JSONValue] = ["provider": .string("local.beats")]
        let result = try project.applying(
            .setBeatGrid(media: "m1", bpm: 117.5, frames: [0, 15, 31], provenance: provenance))
        #expect(result.project.beatFrames == [0, 15, 31])
        #expect(result.project.beatBPM == 117.5)
        #expect(result.project["beatGrid"]?.object["generatedBy"] == .object(provenance))
        let restored = try result.project.applying(result.inverse).project
        #expect(restored.beatFrames.isEmpty)
        #expect(throws: ProjectError.self) {
            try project.applying(
                .setBeatGrid(media: "m1", bpm: 500, frames: [15, 0], provenance: nil))
        }
    }

    @Test("Freeze frame accepts one source frame and can be removed")
    func freezeFrame() throws {
        let project = try fixture()
        let frozen = try project.applying(
            .setProperties(item: "c1", patch: ["freezeFrame": .integer(1_199)])).project
        #expect(frozen.tracks[0].items[0]["freezeFrame"] == .integer(1_199))
        let unfrozen = try frozen.applying(
            .setProperties(item: "c1", patch: ["freezeFrame": .null])).project
        #expect(unfrozen.tracks[0].items[0]["freezeFrame"] == nil)
        #expect(throws: ProjectError.self) {
            try project.applying(
                .setProperties(item: "c1", patch: ["freezeFrame": .integer(1_200)]))
        }
    }

    @Test("A failed batch is atomic and stale revisions cannot edit")
    func atomicity() throws {
        var history = ProjectHistory(project: try fixture())
        let original = history.project
        #expect(throws: ProjectError.self) {
            try history.apply(
                .group(
                    label: "bad", author: .codex,
                    ops: [
                        .delete(item: "c2", ripple: true), .split(item: "c1", atFrame: 0, newID: "x"),
                    ]), label: "bad")
        }
        #expect(history.project == original)
        #expect(history.undoEntries.isEmpty)
        #expect(throws: ProjectError.self) {
            try history.apply(.delete(item: "c1", ripple: false), label: "stale", baseRevision: 0)
        }
    }

    @Test("Unknown nested fields survive decode, edits, save and undo")
    func roundTrip() throws {
        var original = try fixture()
        original["future"] = .object(["largeID": .integer(9_007_199_254_740_993)])
        original.tracks[0].items[0]["interop"] = .object(["resolve": .object(["id": .string("keep")])])
        let decoded = try Project.decode(original.data())
        #expect(decoded == original)
        let result = try decoded.applying(.trim(item: "c1", edge: .end, toFrame: 90, ripple: true))
        #expect(result.project["future"] == original["future"])
        #expect(result.project.tracks[0].items[0]["interop"] == original.tracks[0].items[0]["interop"])
    }

    @Test("Ripple closes the gap and undo/redo restores the complete batch")
    func history() throws {
        var history = ProjectHistory(project: try fixture())
        try history.apply(.delete(item: "c1", ripple: true), label: "Delete")
        #expect(history.project.tracks[0].items[0].at == 0)
        try history.undo()
        #expect(history.project.tracks[0].items.count == 2)
        try history.redo()
        #expect(history.project.tracks[0].items.count == 1)
        #expect(history.project.revision == 4)
    }

    @Test("Splitting a full source at a fractional source-frame boundary remains valid")
    func fractionalSplit() throws {
        var project = Project(name: "Mixed rates", fps: FrameRate(30, 1))
        let media = Media(fields: [
            "id": .string("m"), "path": .string("clip.mov"),
            "fps": FrameRate(24, 1).json, "frames": .integer(72),
        ])
        project = try project.applying(
            .group(
                label: "Import", author: .user,
                ops: [
                    .addMedia(media),
                    .insert(track: "v1", item: Item(id: "c", media: "m", at: 0, duration: 90)),
                ])
        ).project
        let split = try project.applying(.split(item: "c", atFrame: 1, newID: "right")).project
        #expect(split.duration == 90)
        #expect(split.tracks[0].items[1].sourceIn == 0)
        try split.validate()
    }

    @Test("External revisions remain monotonic and exhaustion fails safely")
    func externalRevision() throws {
        let original = try fixture()
        var external = original
        external.revision = 100
        let result = try original.applying(.restore(external))
        #expect(result.project.revision == 101)
        #expect(try result.project.applying(result.inverse).project.revision == 102)
        external.revision = Int.max - 1
        #expect(throws: ProjectError.self) { try external.applying(.restore(original)) }
    }

    @Test("Reject overlaps, source overruns, missing fields and unsupported schema")
    func invalidProjects() throws {
        let project = try fixture()
        #expect(throws: ProjectError.self) {
            try project.applying(.move(item: "c2", toTrack: "v1", atFrame: 1))
        }
        #expect(throws: ProjectError.self) {
            try project.applying(.trim(item: "c2", edge: .end, toFrame: 9999, ripple: false))
        }
        #expect(throws: ProjectError.self) { try Project.decode(Data("{}".utf8)) }
        var future = project
        future["schema"] = .string("bashcut.project/2")
        #expect(throws: ProjectError.self) { try future.validate() }
    }
}
