import Foundation
import Testing

@testable import BashCutProject

/// Picture fields and overlays on plan.cut clip rows, and hand-set picture fields a later apply keeps (B3).
struct PlanCutPictureTests {
    let captions = PlanCutCaptionsTests()

    func item(_ id: String, in project: Project) -> Item? {
        project.tracks.flatMap(\.items).first { $0.id == id }
    }

    func list(_ first: String = #"{"id":"b","media":"m","quote":"xin chào"}"#, _ second: String = "") -> String {
        #"{"clips":[\#(first),{"id":"a","media":"m","quote":"các bạn ơi giá năm chục"\#(second)}]}"#
    }

    @Test("Clip and cover rows set backdrop, crop and keyframes on what they build")
    func pictureFields() throws {
        let built = try captions.apply(
            list(#"{"id":"b","media":"m","from":1,"to":2,"cover":[{"media":"m","from":10,"crop":{"left":0.1}}]}"#,
                 #","backdrop":{"kind":"blur"},"keyframes":{"zoom":[{"frame":0,"value":1},{"frame":10,"value":1.2}]}"#),
            on: captions.base.project())
        let clip = try #require(item("plan-a", in: built))
        #expect(clip["backdrop"]?.object["kind"] == .string("blur"))
        #expect(clip["keyframes"]?.object["zoom"] != nil)
        #expect(item("plan-b-cover1", in: built)?["crop"]?.object["left"] == .number(0.1))
        #expect(PlanCut.unknownFields(
            [.object(["backdrop": .object([:]), "crop": .object([:]), "keyframes": .object([:]), "fill": .bool(true)])],
            titles: [], ids: ["a"]).isEmpty)
        #expect(throws: ProjectError.self) { try captions.base.spec(list(#"{"id":"b","media":"m","quote":"xin chào","fill":3}"#)) }
    }

    @Test("A backdrop and keyframes set by hand stay through a later apply; the list can clear them with null")
    func keepsHandSetPicture() throws {
        let built = try captions.apply(list(), on: captions.base.project())
        let blur: JSONValue = .object(["kind": .string("blur")])
        let zoom: JSONValue = .object(["zoom": .array([.object(["frame": .integer(0), "value": .number(1.3)])])])
        let edited = try built.applying(.setProperties(item: "plan-a", patch: ["backdrop": blur, "keyframes": zoom])).project
        let after = try captions.apply(list(#"{"id":"b","media":"m","from":0.5,"to":1.9}"#), on: edited)
        #expect(item("plan-a", in: after)?["backdrop"] == blur)
        #expect(item("plan-a", in: after)?["keyframes"] == zoom)
        let cleared = try captions.apply(list(#"{"id":"b","media":"m","quote":"xin chào"}"#, #","backdrop":null"#), on: after)
        #expect(item("plan-a", in: cleared)?["backdrop"] == nil)
        #expect(item("plan-a", in: cleared)?["keyframes"] == zoom)
        // A field the list set is the list's: dropping it from the list drops it from the clip.
        let listed = try captions.apply(list(#"{"id":"b","media":"m","quote":"xin chào"}"#, #","crop":{"top":0.2}"#), on: built)
        #expect(item("plan-a", in: listed)?["crop"] != nil)
        #expect(item("plan-a", in: try captions.apply(list(), on: listed))?["crop"] == nil)
    }

    @Test("An overlay on a clip plays its own media in sync on an overlay layer and moves when an earlier clip changes")
    func overlayFollowsClip() throws {
        let pip = #","overlays":[{"offset":0.2,"zoom":0.3,"pan":600,"crop":{"radius":0.1}}]"#
        let built = try captions.apply(list(#"{"id":"b","media":"m","quote":"xin chào"}"#, pip), on: captions.base.project())
        let fps = built.fps.value
        let clip = try #require(item("plan-a", in: built))
        let overlay = try #require(item("plan-a-overlay1", in: built))
        let track = try #require(built.tracks.first { $0.items.contains { $0.id == overlay.id } })
        #expect(track.role == TrackRole.overlay)
        #expect(overlay.at == clip.at + Int((0.2 * fps).rounded()) && overlay.end == clip.end)
        #expect(overlay["transform"]?.object["zoom"] == .number(0.3) && overlay["crop"]?.object["radius"] == .number(0.1))
        #expect(overlay[PlanCut.tag] == .string("a"))
        let media = try #require(built.media.first { $0.id == "m" })
        #expect(abs(Double(overlay.sourceIn) / media.fps.value - (Double(clip.sourceIn) / media.fps.value + 0.2)) < 0.05)
        // A longer first clip pushes the clip and its overlay later together.
        let after = try captions.apply(list(#"{"id":"b","media":"m","from":0.2,"to":1.9}"#, pip), on: built)
        let moved = try #require(item("plan-a-overlay1", in: after))
        let movedClip = try #require(item("plan-a", in: after))
        #expect(movedClip.at > clip.at && moved.at - movedClip.at == overlay.at - clip.at)
        #expect(throws: ProjectError.self) {
            try captions.base.spec(list(#"{"id":"b","media":"m","quote":"xin chào","overlays":[{"media":"song"}]}"#))
        }
    }

    @Test("A patch puts a new or moved entry after or before another, and false clears a hand-set field it would drop (B8, B3)")
    func patchPlacesEntries() throws {
        let list = try JSONDecoder().decode(JSONValue.self, from: Data(list().utf8))
        let ids = { (value: JSONValue) in value.object["clips"]?.array.compactMap { $0.object["id"]?.string } ?? [] }
        let patched = try PlanCut.patch(list, with: .object(["clips": .object([
            "n": .object(["media": .string("m"), "from": .number(5), "to": .number(6), "after": .string("b")]),
            "a": .object(["before": .string("b")]),
        ])]))
        #expect(ids(patched) == ["a", "b", "n"])
        #expect(patched.object["clips"]?.array.allSatisfy { $0.object["after"] == nil && $0.object["before"] == nil } == true)
        let first = try PlanCut.patch(list, with: .object(["clips": .object([
            "n": .object(["media": .string("m"), "from": .number(5), "to": .number(6), "before": .string("b")]),
        ])]))
        #expect(ids(first) == ["n", "b", "a"])
        // null removes the key from the list, so false is how a patch clears a backdrop set by hand.
        let cleared = try PlanCut.patch(list, with: .object(["clips": .object(["a": .object(["backdrop": .bool(false)])])]))
        let spec = try PlanCut.decode(cleared)
        #expect(spec.clips.first { $0.id == "a" }?.picture["backdrop"] == .null)
    }
}
