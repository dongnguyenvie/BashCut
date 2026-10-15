import Foundation
import Testing

@testable import BashCutProject

/// An item's own entrance and exit (`enter`, `exit`): transition kinds on text, stickers and overlays.
struct ItemTransitionTests {
    /// A caption `cap` (0–60) on t1, an overlay clip `ov` (0–90) on v2 and a sound `snd` on a1.
    func project() throws -> Project {
        let media = Media(fields: [
            "id": .string("m"), "path": .string("a.mov"), "fps": FrameRate(30, 1).json, "frames": .integer(300),
        ])
        var caption = Item(id: "cap", at: 0, duration: 60)
        caption["text"] = .string("Hello")
        return try Project(name: "In and out", fps: FrameRate(30, 1)).applying(.group(label: "items", author: .user, ops: [
            .addMedia(media), .insert(track: "t1", item: caption),
            .insert(track: "v2", item: Item(id: "ov", media: "m", at: 0, duration: 90)),
            .insert(track: "a1", item: Item(id: "snd", media: "m", at: 0, duration: 30)),
        ])).project
    }

    @Test("enter and exit take built-in kinds or any kind with motion, frames and an easing; bad ones are refused")
    func validation() throws {
        let base = try project()
        let good: [JSONValue] = [
            .object(["kind": .string("iris"), "duration": .integer(12)]),
            .object(["kind": .string("whip-up"), "duration": .integer(10), "easing": .string("inOut")]),
            .object(["kind": .string("my-pop"), "duration": .integer(8),
                     "motion": .object(["incoming": .object(["zoom": .array([.number(0.5), .number(1)])])])]),
        ]
        for value in good {
            _ = try base.applying(.setProperties(item: "cap", patch: ["enter": value, "exit": value]))
            _ = try base.applying(.setProperties(item: "ov", patch: ["enter": value]))
        }
        let bad: [JSONValue] = [
            .string("iris"), .object(["duration": .integer(12)]), .object(["kind": .string("iris")]),
            .object(["kind": .string("iris"), "duration": .integer(0)]),
            .object(["kind": .string("not-built-in"), "duration": .integer(12)]),
            .object(["kind": .string("iris"), "duration": .integer(12), "easing": .string("bounce")]),
            .object(["kind": .string("x"), "duration": .integer(12),
                     "motion": .object(["incoming": .object(["warp": .array([.number(0), .number(1)])])])]),
        ]
        for value in bad {
            #expect(throws: ProjectError.self) { try base.applying(.setProperties(item: "cap", patch: ["exit": value])) }
        }
        // Only video and text items draw an entrance.
        #expect(throws: ProjectError.self) {
            try base.applying(.setProperties(item: "snd", patch: ["enter": good[0]]))
        }
    }

    @Test("enter and exit survive save and load with unknown fields, undo and null removes them")
    func roundTrip() throws {
        let base = try project()
        let enter: JSONValue = .object(["kind": .string("iris"), "duration": .integer(12), "future": .string("kept")])
        let result = try base.applying(.setProperties(item: "cap", patch: [
            "enter": enter, "exit": .object(["kind": .string("whip-up"), "duration": .integer(10)]),
        ]))
        let decoded = try Project.decode(result.project.data())
        let caption = try #require(decoded.tracks.flatMap(\.items).first { $0.id == "cap" })
        #expect(caption["enter"] == enter)
        #expect(caption.enterTransition == ItemTransition(kind: "iris", duration: 12))
        #expect(caption.exitTransition?.kind == "whip-up")
        let undone = try decoded.applying(result.inverse)
        #expect(undone.project.tracks.flatMap(\.items).first { $0.id == "cap" }?["enter"] == nil)
        let removed = try decoded.applying(.setProperties(item: "cap", patch: ["enter": .null])).project
        let after = try #require(removed.tracks.flatMap(\.items).first { $0.id == "cap" })
        #expect(after["enter"] == nil && after["exit"] != nil)
    }

    @Test("A split keeps the entrance on the left part and the exit on the right")
    func split() throws {
        let base = try project().applying(.setProperties(item: "ov", patch: [
            "enter": .object(["kind": .string("iris"), "duration": .integer(12)]),
            "exit": .object(["kind": .string("wipe"), "duration": .integer(12)]),
        ])).project
        let split = try base.applying(.split(item: "ov", atFrame: 45, newID: "ov2")).project
        let items = split.tracks.flatMap(\.items)
        let left = try #require(items.first { $0.id == "ov" }), right = try #require(items.first { $0.id == "ov2" })
        #expect(left["enter"] != nil && left["exit"] == nil)
        #expect(right["enter"] == nil && right["exit"] != nil)
    }

    @Test("Enter plays the incoming side; exit the outgoing one, a wipe or shape backwards; others fade")
    func tracks() {
        let iris = ItemTransition(kind: "iris", duration: 12)
        #expect(iris.tracks(entering: true) == ["iris": [0, 1]])
        #expect(iris.tracks(entering: false) == ["iris": [1, 0]])
        #expect(ItemTransition(kind: "wipe", duration: 12).tracks(entering: false) == ["reveal": [1, 0]])
        let whip = ItemTransition(kind: "whip-up", duration: 10).tracks(entering: false)
        #expect(whip["panY"] == [0, 1] && whip["opacity"] == [1, 0])
        #expect(ItemTransition(kind: "whip-up", duration: 10).tracks(entering: true)["opacity"] == [0, 1])
        #expect(ItemTransition(kind: "dissolve", duration: 10).tracks(entering: false) == ["opacity": [1, 0]])
        // A side that lists its own opacity keeps it.
        #expect(ItemTransition(kind: "flicker", duration: 10).tracks(entering: true)["opacity"]?.count == 11)
    }

    @Test("At render time each side is clamped to the item, and a cut transition at an edge wins")
    func appearance() throws {
        var item = Item(id: "x", at: 30, duration: 20)
        item["enter"] = ItemTransition(kind: "iris", duration: 12).json
        item["exit"] = ItemTransition(kind: "wipe", duration: 40).json
        let appearance = try #require(ItemAppearance(item: item))
        #expect(appearance.enter?.start == 30 && appearance.enter?.duration == 12)
        #expect(appearance.exit?.start == 30 && appearance.exit?.duration == 20)
        #expect(appearance.side(at: 31)?.entering == true)
        #expect(appearance.side(at: 45)?.entering == false)
        #expect(appearance.enter?.value("iris", at: 36) == 0.5)
        #expect(appearance.side(at: 50) == nil)
        #expect(ItemAppearance(item: item, cutAtStart: true, cutAtEnd: true) == nil)
        #expect(ItemAppearance(item: Item(id: "y", at: 0, duration: 10)) == nil)
    }

    @Test("The schema describes enter and exit")
    func schema() throws {
        let text = try #require(String(data: try ProjectSchema.data(), encoding: .utf8))
        #expect(text.contains("\"itemTransition\""))
        #expect(text.contains("#/$defs/itemTransition"))
    }
}
