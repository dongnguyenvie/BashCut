import Foundation
import Testing

@testable import BashCutProject

/// Hand edits through a later apply by the build's record (`planBuilt`): kept while the list asks what it asked, the
/// list's when it changed the same field, both reported.
struct PlanCutKeepTests {
    let captions = PlanCutCaptionsTests()

    func item(_ id: String, in project: Project) -> Item? {
        project.tracks.flatMap(\.items).first { $0.id == id }
    }

    func edited(_ project: Project, _ operations: EditOperation...) throws -> Project {
        try project.applying(.group(label: "Hand", author: .agent, ops: operations)).project
    }

    /// `project` as a save and reopen leaves it: whole numbers read back as integers.
    func saved(_ project: Project) throws -> Project {
        try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
    }

    /// The edit `json` builds on `project`, and what the build reports of the hand edits.
    func apply(
        _ json: String, on project: Project, transcribed: Bool = true
    ) throws -> (project: Project, hand: PlanCut.HandReport) {
        let spec = try captions.base.spec(json)
        let transcripts = transcribed ? ["m": captions.base.transcript] : [:]
        let clips = PlanCut.resolve(spec, project: project, transcripts: transcripts).clips
        let built = try PlanCut.build(spec, clips: clips, on: project, transcripts: transcripts)
        let after = try project.applying(.group(label: "Plan", author: .user, ops: built.planner.operations)).project
        return (after, built.hand)
    }

    func fields(_ rows: [JSONValue]) -> [String] {
        rows.compactMap { row in row.object["field"]?.string.map { "\(row.object["item"]?.string ?? ""):\($0)" } }
    }

    func list(clip: String = "", title: String = #""style":{"positionY":0.8}"#) -> String {
        #"""
        {"clips":[{"id":"b","media":"m","quote":"xin chào"},{"id":"a","media":"m","quote":"các bạn ơi giá năm chục"\#(clip)}],
        "titles":[{"id":"t","clip":"a","text":"GIÁ NĂM CHỤC",\#(title)}],
        "music":{"media":"song","volumeDb":-6}}
        """#
    }

    @Test("Keyframes and a framing set by clip motion stay through a later apply; the list's own framing wins once changed")
    func keepsClipMotion() throws {
        let built = try apply(list(clip: #","zoom":1.2"#), on: captions.base.project()).project
        let zoom: JSONValue = .object(["zoom": .array([
            .object(["frame": .integer(0), "value": .number(1.2)]), .object(["frame": .integer(20), "value": .number(1.6)]),
        ])])
        let moved = try edited(built, .setProperties(item: "plan-a", patch: [
            "keyframes": zoom, "transform": .object(["zoom": .number(1.2), "pan": .number(120)]),
        ]))
        let again = try apply(list(clip: #","zoom":1.2"#), on: moved)
        let clip = try #require(item("plan-a", in: again.project))
        #expect(clip["keyframes"] == zoom)
        #expect(clip["transform"] == .object(["zoom": .number(1.2), "pan": .number(120)]))
        #expect(Set(fields(again.hand.kept)).isSuperset(of: ["plan-a:keyframes", "plan-a:transform.pan"]))
        #expect(again.hand.overwritten.isEmpty)
        // A zoom the list changes is the list's; the pan set by hand stays beside it.
        let zoomed = try apply(list(clip: #","zoom":1.5"#), on: again.project)
        #expect(item("plan-a", in: zoomed.project)?["transform"] == .object(["zoom": .number(1.5), "pan": .number(120)]))
        #expect(item("plan-a", in: zoomed.project)?["keyframes"] == zoom)
    }

    @Test("A gain set by clip volume stays over the list's same volumeDb; a new volumeDb in the list replaces it, reported")
    func keepsClipVolume() throws {
        let built = try apply(list(clip: #","volumeDb":-3"#), on: captions.base.project()).project
        let sound = try #require(item("plan-a", in: built)?.linkedItemID)
        let louder = try saved(edited(
            built, .setProperties(item: "plan-a", patch: ["volumeDb": .number(8)]),
            .setProperties(item: sound, patch: ["volumeDb": .number(8)]),
            .setProperties(item: "plan-music", patch: ["volumeDb": .number(-23)])))
        let again = try apply(list(clip: #","volumeDb":-3"#), on: louder)
        #expect(item("plan-a", in: again.project)?["volumeDb"] == .integer(8))
        #expect(item(sound, in: again.project)?["volumeDb"] == .integer(8))
        #expect(item("plan-music", in: again.project)?["volumeDb"] == .integer(-23))
        #expect(again.hand.keepsMusicLevel)
        #expect(fields(again.hand.kept).contains("plan-a:volumeDb"))
        // Applying the same list once more still keeps it: the record is the list's, not the hand's.
        let third = try apply(list(clip: #","volumeDb":-3"#), on: saved(again.project))
        #expect(third.hand.overwritten.isEmpty)
        #expect(item("plan-a", in: third.project)?["volumeDb"] == .integer(8))
        let changed = try apply(list(clip: #","volumeDb":-1"#), on: third.project)
        #expect(item("plan-a", in: changed.project)?["volumeDb"] == .number(-1))
        let overwritten = try #require(changed.hand.overwritten.first { $0.object["item"] == .string("plan-a") })
        #expect(overwritten.object["hand"] == .integer(8) && overwritten.object["list"] == .number(-1))
    }

    @Test("A title's lineHeight and text fixed by hand stay; the list's other style changes still land")
    func keepsTextStyle() throws {
        let built = try apply(list(), on: captions.base.project()).project
        var style = try #require(item("plan-t", in: built)?["textStyle"]?.object)
        style["lineHeight"] = .number(1.25)
        let fixed = try edited(
            built, .setProperties(item: "plan-t", patch: ["textStyle": .object(style), "text": .string("GIÁ 50K")]))
        let again = try apply(list(title: #""style":{"positionY":0.7}"#), on: fixed)
        let title = try #require(item("plan-t", in: again.project))
        #expect(title["textStyle"]?.object["lineHeight"] == .number(1.25))
        #expect(title["textStyle"]?.object["positionY"] == .number(0.7))
        #expect(title.text == "GIÁ 50K")
        #expect(Set(fields(again.hand.kept)) == ["plan-t:textStyle.lineHeight", "plan-t:text"])
    }

    @Test("A ripple cut inside a clip keeps its pieces and moves what follows; a new range in the row rebuilds it whole")
    func keepsRippleCut() throws {
        let built = try apply(list(), on: captions.base.project()).project
        let first = try #require(item("plan-b", in: built))
        let clip = try #require(item("plan-a", in: built))
        let title = try #require(item("plan-t", in: built))
        try #require(first.duration > 12)
        // Cut 6 frames out of the middle of b (picture and sound): split twice, ripple-delete the middle.
        let (from, to) = (first.at + 3, first.at + 9)
        let cut = try edited(
            built, .split(item: "plan-b", atFrame: from, newID: "mid"), .split(item: "mid", atFrame: to, newID: "rest"),
            .delete(item: "mid", ripple: true))
        #expect(item("plan-a", in: cut)?.at == clip.at - 6)
        let again = try apply(list(), on: cut)
        #expect(item("plan-b", in: again.project)?.duration == 3)
        let rest = try #require(item("rest", in: again.project))
        #expect(rest.at == first.at + 3 && rest.sourceIn == (item("rest", in: cut)?.sourceIn ?? -1))
        #expect(rest[PlanCut.tag] == .string("b"))
        // What follows starts where the shorter clip ends, the title with it.
        #expect(item("plan-a", in: again.project)?.at == clip.at - 6)
        #expect(item("plan-t", in: again.project)?.at == title.at - 6)
        #expect(fields(again.hand.kept).contains("plan-b:timing"))
        // The pieces carry the record of what the build made, so they stay through one more apply.
        let third = try apply(list(), on: again.project)
        #expect(item("rest", in: third.project) != nil && item("plan-a", in: third.project)?.at == clip.at - 6)
        // Another range in the row is the list's: the clip is built whole again, and the report says what went.
        let whole = try apply(list().replacingOccurrences(of: #""quote":"xin chào""#, with: #""from":0.2,"to":1.9"#), on: third.project)
        #expect(item("rest", in: whole.project) == nil)
        #expect(fields(whole.hand.overwritten).contains("plan-b:timing"))
    }

    @Test("Items built before records keep what differs from the list while their row is the stored one")
    func keepsUnrecordedEdits() throws {
        let built = try apply(list(), on: captions.base.project()).project
        var old = built
        for track in old.tracks.indices {
            for index in old.tracks[track].items.indices { old.tracks[track].items[index].fields[PlanCut.builtTag] = nil }
        }
        var plan = old["plan"]?.object ?? [:]
        plan["cut"] = try JSONDecoder().decode(JSONValue.self, from: Data(list().utf8))
        old["plan"] = .object(plan)
        var style = try #require(item("plan-t", in: old)?["textStyle"]?.object)
        style["lineHeight"] = .number(1.25)
        let fixed = try edited(old, .setProperties(item: "plan-t", patch: ["textStyle": .object(style)]))
        let again = try apply(list(), on: fixed)
        #expect(item("plan-t", in: again.project)?["textStyle"]?.object["lineHeight"] == .number(1.25))
        // A changed row is the list's, whatever the item holds.
        let changed = try apply(list(title: #""style":{"positionY":0.6}"#), on: fixed)
        #expect(item("plan-t", in: changed.project)?["textStyle"]?.object["lineHeight"] == nil)
    }

    @Test("Every caption of a media deleted by hand stays deleted; a media transcribed since the last apply gets its captions")
    func keepsDeletedMediaCaptions() throws {
        let timed = #"{"clips":[{"id":"b","media":"m","from":0,"to":1.9},{"id":"a","media":"m","from":2,"to":6}],"captions":{"from":"speech"}}"#
        let built = try apply(timed, on: captions.base.project()).project
        let cues = captions.cues(built)
        try #require(!cues.isEmpty)
        var cleared = built
        for cue in cues { cleared = try edited(cleared, .delete(item: cue.id, ripple: false)) }
        let restyled = timed.replacingOccurrences(of: #""from":"speech""#, with: #""from":"speech","style":{"size":0.06}"#)
        let again = try apply(restyled, on: cleared)
        #expect(captions.cues(again.project).isEmpty)
        #expect(fields(again.hand.kept).contains("captions:deleted"))
        // Built before the media had a transcript: no captions then, all of them once it is transcribed.
        let untranscribed = try apply(timed, on: captions.base.project(), transcribed: false).project
        #expect(captions.cues(untranscribed).isEmpty)
        #expect(captions.cues(try apply(timed, on: untranscribed).project).count == cues.count)
    }

    @Test("A clip of the same media placed by hand gets no captions from the plan")
    func handClipGetsNoPlanCaptions() throws {
        let timed = #"{"clips":[{"id":"a","media":"m","from":2,"to":6}],"captions":{"from":"speech"}}"#
        let built = try apply(timed, on: captions.base.project()).project
        let end = built.duration
        // The same speech again after the edit, on another layer, placed by hand.
        let track = try #require(built.tracks.first { $0.role == TrackRole.dialogue })
        let hand = Item(id: "hand", media: "m", at: end + 30, duration: 120, sourceIn: 0)
        let placed = try edited(built, .insert(track: track.id, item: hand))
        let after = try apply(timed.replacingOccurrences(of: #""from":"speech""#, with: #""from":"speech","style":{"size":0.06}"#), on: placed)
        #expect(!captions.cues(after.project).isEmpty)
        #expect(!captions.cues(after.project).contains { $0.end > end + 30 })
    }

    @Test("A cut-range through a covered clip (its sound, cover and overlay) keeps all three pieces in step")
    func keepsRangeCutOfCoveredClip() throws {
        let covered = #"""
            {"clips":[{"id":"b","media":"m","quote":"xin chào"},
            {"id":"a","media":"m","from":2,"to":6,"cover":[{"media":"m","from":10}],"overlays":[{"zoom":0.3}]}]}
            """#
        let built = try apply(covered, on: captions.base.project()).project
        let sound = try #require(item("plan-a-sound", in: built))
        let (from, to) = (sound.at + 15, sound.at + 45)
        let cut = try edited(built, .rippleDeleteRange(from: from, to: to, tracks: nil, continuous: nil))
        let again = try apply(covered, on: cut)
        #expect(fields(again.hand.kept).contains { $0.hasSuffix(":timing") })
        for id in ["plan-a-sound", "plan-a-cover1", "plan-a-overlay1"] {
            let was = try #require(item(id, in: cut)), now = try #require(item(id, in: again.project))
            #expect(now.at == was.at && now.duration == was.duration && now.sourceIn == was.sourceIn)
        }
        // The parts after the cut stay, each where the cut left it.
        let parts = cut.tracks.flatMap(\.items).filter { $0[PlanCut.tag] == .string("a") && $0.id.hasSuffix(Project.rippleRangeSuffix) }
        #expect(!parts.isEmpty)
        for part in parts { #expect(item(part.id, in: again.project).map { [$0.at, $0.sourceIn] } == [part.at, part.sourceIn]) }
    }
}
