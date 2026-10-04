import Foundation
import Testing
@testable import BashCutProject

struct KeyframeTests {
    private func project(keyframes: JSONValue? = nil, fields: [String: JSONValue] = [:]) throws -> Project {
        let media = Media(fields: [
            "id": .string("m"), "path": .string("a.mov"), "fps": FrameRate(30, 1).json, "frames": .integer(300),
        ])
        var clip = Item(id: "a", media: "m", at: 30, duration: 90)
        if let keyframes { clip["keyframes"] = keyframes }
        for (key, value) in fields { clip[key] = value }
        return try Project(name: "Keys", fps: FrameRate(30, 1)).applying(.group(label: "clip", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: clip),
        ])).project
    }

    private func item(_ project: Project, _ id: String) throws -> Item {
        try #require(project.tracks.flatMap(\.items).first { $0.id == id })
    }

    @Test("Values hold outside the keys and follow each key's ease between them")
    func evaluation() throws {
        let motion = ItemMotion(keys: [
            "zoom": [.init(frame: 10, value: 1, ease: .linear), .init(frame: 20, value: 2, ease: .hold),
                     .init(frame: 30, value: 3)],
            "opacity": [.init(frame: 0, value: 0, ease: .easeInOut), .init(frame: 10, value: 1)],
        ])
        #expect(motion.value("zoom", at: 0) == 1)
        #expect(motion.value("zoom", at: 15) == 1.5)
        #expect(motion.value("zoom", at: 25) == 2)  // hold
        #expect(motion.value("zoom", at: 99) == 3)
        #expect(motion.value("opacity", at: 5) == 0.5)  // inOut is symmetric
        #expect(try #require(motion.value("opacity", at: 2)) < 0.2)
        #expect(motion.value("pan", at: 5) == nil)
        #expect(try ItemMotion(json: motion.json) == motion)
    }

    @Test("Audio items animate only volume, text items no volume; picture motion leaves volume out")
    func volumeKeys() throws {
        #expect(ItemMotion.properties(onTrackKind: TrackKind.audio) == ["volume"])
        #expect(!ItemMotion.properties(onTrackKind: TrackKind.text).contains("volume"))
        #expect(ItemMotion.properties(onTrackKind: TrackKind.video).contains("volume"))
        let volume = ItemMotion(keys: ["volume": [.init(frame: 0, value: -6)]])
        #expect(volume.picture == nil)
        let both = ItemMotion(keys: ["volume": [.init(frame: 0, value: -6)], "zoom": [.init(frame: 0, value: 2)]])
        #expect(both.picture?.keys.keys.sorted() == ["zoom"])
        _ = try project(keyframes: volume.json)
        #expect(throws: ProjectError.self) {
            try project(keyframes: ItemMotion(keys: ["volume": [.init(frame: 0, value: 30)]]).json)
        }

        func insert(_ item: Item, on track: String) throws {
            _ = try project().applying(.insert(track: track, item: item))
        }
        var music = Item(id: "b", media: "m", at: 0, duration: 30)
        music["keyframes"] = volume.json
        try insert(music, on: "a1")
        music["keyframes"] = both.json
        #expect(throws: ProjectError.self) { try insert(music, on: "a1") }
        var title = Item(id: "c", at: 0, duration: 30)
        title["text"] = .string("Hi")
        title["keyframes"] = volume.json
        #expect(throws: ProjectError.self) { try insert(title, on: "t1") }
    }

    @Test("Keyed frames list each frame with a key once, in order")
    func keyedFrames() {
        let motion = ItemMotion(keys: [
            "zoom": [.init(frame: 10, value: 1), .init(frame: 30, value: 2)],
            "opacity": [.init(frame: 0, value: 0), .init(frame: 10, value: 1)],
        ])
        #expect(motion.keyedFrames == [0, 10, 30])
        #expect(motion.shifted(by: -10).keyedFrames == [-10, 0, 20])
    }

    @Test("Validation rejects unknown properties, values out of range and frames out of order")
    func validation() throws {
        func rejects(_ json: JSONValue, _ fragment: String) {
            #expect {
                try project(keyframes: json)
            } throws: { ($0 as? ProjectError)?.errorDescription?.contains(fragment) == true }
        }
        rejects(.object(["blur": .array([.object(["frame": .integer(0), "value": .number(1)])])]), "unknown property")
        rejects(.object(["opacity": .array([.object(["frame": .integer(0), "value": .number(2)])])]), "value in")
        rejects(.object(["zoom": .array([
            .object(["frame": .integer(5), "value": .number(1)]), .object(["frame": .integer(5), "value": .number(2)]),
        ])]), "frames must increase")
        rejects(.object(["zoom": .array([.object(["frame": .integer(0), "value": .number(1), "ease": .string("bounce")])])]),
                "ease must be")
        _ = try project(keyframes: ItemMotion(keys: ["zoom": [.init(frame: 0, value: 1.2)]]).json)
    }

    @Test("Splitting and trimming the start keep the animation on the same picture")
    func editsShiftKeys() throws {
        let keys = ItemMotion(keys: ["zoom": [.init(frame: 0, value: 1), .init(frame: 60, value: 2)]])
        let base = try project(keyframes: keys.json)
        let split = try base.applying(.split(item: "a", atFrame: 60, newID: "b")).project
        #expect(try item(split, "a").motion?.value("zoom", at: 30) == keys.value("zoom", at: 30))
        // The right part starts 30 frames into the clip: its frame 0 is the original frame 30.
        #expect(try item(split, "b").motion?.value("zoom", at: 0) == keys.value("zoom", at: 30))
        #expect(try item(split, "b").motion?.keys["zoom"]?.map(\.frame) == [-30, 30])

        let trimmed = try base.applying(.trim(item: "a", edge: .start, toFrame: 45, ripple: false)).project
        #expect(try item(trimmed, "a").motion?.value("zoom", at: 0) == keys.value("zoom", at: 15))
        let undone = try base.applying(.trim(item: "a", edge: .start, toFrame: 45, ripple: false))
        #expect(try undone.project.applying(undone.inverse).project.tracks == base.tracks)
    }

    @Test("Setting keyframes to null removes them")
    func removal() throws {
        let base = try project(keyframes: ItemMotion(keys: ["zoom": [.init(frame: 0, value: 1.5)]]).json)
        let cleared = try base.applying(.setProperties(item: "a", patch: ["keyframes": .null])).project
        #expect(try item(cleared, "a")["keyframes"] == nil)
    }

    @Test("Presets fit the item and the frame")
    func presets() throws {
        for preset in MotionPreset.all {
            let motion = try MotionPreset.motion(preset.id, duration: 90, width: 1080, height: 1920, fps: FrameRate())
            #expect(!motion.isEmpty)
            #expect(motion.keys.values.allSatisfy { $0.allSatisfy { (0..<90).contains($0.frame) } }, "\(preset.id)")
            _ = try project(keyframes: motion.json)
        }
        let zoomIn = try MotionPreset.motion("zoom-in", duration: 90, width: 1080, height: 1920, fps: FrameRate())
        #expect(zoomIn.value("zoom", at: 0) == 1 && zoomIn.value("zoom", at: 89) == 1.12)
        #expect(throws: ProjectError.self) {
            try MotionPreset.motion("wobble", duration: 90, width: 1080, height: 1920, fps: FrameRate())
        }
        // A very short item still gets increasing frames.
        let short = try MotionPreset.motion("fade-in-out", duration: 3, width: 1080, height: 1920, fps: FrameRate())
        _ = try ItemMotion(json: short.json)
    }

    @Test("Focus frames a rectangle of a 1920×1080 recording on a 1080-wide canvas")
    func focus() throws {
        // A 480×270 panel centred at (1400, 300): zoom 4 over the fitted 0.5625 scale, centre moved to the middle.
        let panel = try MotionFocus.framing(
            MotionFocus.parse("1160,165,480,270"), source: (1920, 1080), canvas: (1080, 1920), fill: false)
        #expect(panel.zoom == 4)
        #expect(panel.pan == (960 - 1400) * 0.5625 * 4)
        // Centring would need tilt −540, but the 2430 px tall picture only has 255 px to spare above the 1920 frame.
        #expect(panel.tilt == -(1080 * 0.5625 * 4 - 1920) / 2)
        // The whole picture filled on a portrait canvas stays inside its edges: pan is clamped.
        let edge = try MotionFocus.framing(
            MotionFocus.parse("1800,0,120,1080"), source: (1920, 1080), canvas: (1080, 1920), fill: true)
        let spare = (1920 * (1920.0 / 1080) * edge.zoom - 1080) / 2
        #expect(abs(edge.pan) <= spare + 0.1)
        #expect(throws: ProjectError.self) { try MotionFocus.parse("1,2,3") }
        #expect(throws: ProjectError.self) {
            try MotionFocus.framing(
                MotionFocus.parse("3000,0,100,100"), source: (1920, 1080), canvas: (1080, 1920), fill: false)
        }
    }

    @Test("Crop sides and radius are validated")
    func crop() throws {
        _ = try project(fields: ["crop": .object(["left": .number(0.3), "right": .number(0.3), "radius": .number(0.5)])])
        #expect(throws: ProjectError.self) {
            try project(fields: ["crop": .object(["top": .number(0.6), "bottom": .number(0.5)])])
        }
        #expect(throws: ProjectError.self) { try project(fields: ["crop": .object(["radius": .number(0.7)])]) }
        #expect(throws: ProjectError.self) { try project(fields: ["crop": .number(1)]) }
    }
}
