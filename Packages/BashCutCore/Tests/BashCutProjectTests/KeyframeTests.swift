import Foundation
import Testing
@testable import BashCutProject

struct KeyframeTests {
    private func project(keyframes: JSONValue? = nil) throws -> Project {
        let media = Media(fields: [
            "id": .string("m"), "path": .string("a.mov"), "fps": FrameRate(30, 1).json, "frames": .integer(300),
        ])
        var clip = Item(id: "a", media: "m", at: 30, duration: 90)
        if let keyframes { clip["keyframes"] = keyframes }
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
}
