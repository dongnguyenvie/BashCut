import Foundation
import Testing

@testable import BashCutProject

/// Sound, speed, the music bed's span and deleted captions set by hand on what an apply built, through a later apply.
struct PlanCutHandEditsTests {
    let captions = PlanCutCaptionsTests()

    func item(_ id: String, in project: Project) -> Item? {
        project.tracks.flatMap(\.items).first { $0.id == id }
    }

    func edited(_ project: Project, _ operations: EditOperation...) throws -> Project {
        try project.applying(.group(label: "Hand", author: .agent, ops: operations)).project
    }

    func ramp() throws -> SpeedCurve {
        try SpeedCurve([SpeedCurve.Point(t: 0, speed: 1), SpeedCurve.Point(t: 1, speed: 2)])
    }

    @Test("A speed ramp and a constant speed set by hand stay through a later apply; the list's speed wins")
    func keepsHandSpeed() throws {
        let built = try captions.apply(captions.twoClips(), on: captions.base.project())
        let plain = try #require(item("plan-a", in: built))
        let ramped = try edited(
            built, .setSpeedCurve(item: "plan-a", curve: ramp(), keepDuration: false),
            .setSpeed(item: "plan-b", speed: 1.5, keepDuration: false))
        let after = try captions.apply(captions.twoClips(volume: -3), on: ramped)
        let clip = try #require(item("plan-a", in: after))
        #expect(clip.speedCurve == (try ramp()))
        #expect(clip.duration < plain.duration)
        #expect(item(try #require(clip.linkedItemID), in: after)?.speedCurve == (try ramp()))
        #expect(item("plan-b", in: after)?["speed"] == .number(1.5))
        // The clips still play back to back after the shorter ones.
        #expect(item("plan-b", in: after).map(\.end) == clip.at)
        // A speed in the list replaces the hand ramp; dropping it from the list drops it from the clip.
        let listed = #"{"clips":[{"id":"b","media":"m","quote":"xin chào"},{"id":"a","media":"m","quote":"các bạn ơi giá năm chục","speed":2}]}"#
        let fast = try captions.apply(listed, on: after)
        #expect(item("plan-a", in: fast)?.speedCurve == nil && item("plan-a", in: fast)?["speed"] == .number(2))
        let unlisted = #"{"clips":[{"id":"b","media":"m","quote":"xin chào"},{"id":"a","media":"m","quote":"các bạn ơi giá năm chục"}]}"#
        let back = try captions.apply(unlisted, on: fast)
        #expect(item("plan-a", in: back)?["speed"] == nil)
    }

    @Test("Volume, mute and fades set by hand stay through a later apply; a volumeDb in the list wins")
    func keepsHandSound() throws {
        let built = try captions.apply(captions.twoClips(), on: captions.base.project())
        let sound = try #require(item("plan-a", in: built)?.linkedItemID)
        let quiet = try edited(
            built, .setProperties(item: "plan-a", patch: ["volumeDb": .number(-96)]),
            .setProperties(item: sound, patch: ["volumeDb": .number(-96), "fadeIn": .integer(3)]),
            .setProperties(item: "plan-b-audio", patch: ["muted": .bool(true)]),
            .setProperties(item: "plan-music", patch: ["fadeOut": .integer(12)]))
        let after = try captions.apply(captions.twoClips(volume: -3), on: quiet)
        #expect(item("plan-a", in: after)?["volumeDb"] == .number(-96))
        #expect(item(sound, in: after)?["volumeDb"] == .number(-96) && item(sound, in: after)?["fadeIn"] == .integer(3))
        #expect(item("plan-b-audio", in: after)?["muted"] == .bool(true))
        // The bed takes the list's level and keeps its hand fade.
        #expect(item("plan-music", in: after)?["volumeDb"] == .number(-3))
        #expect(item("plan-music", in: after)?["fadeOut"] == .integer(12))
        // A muted clip is not heard, so it gets no captions.
        #expect(!captions.cues(after).contains { $0.text.contains("xin") })
        let listed = #"""
            {"clips":[{"id":"b","media":"m","quote":"xin chào"},{"id":"a","media":"m","quote":"các bạn ơi giá năm chục","volumeDb":-6}]}
            """#
        let loud = try captions.apply(listed, on: after)
        #expect(item("plan-a", in: loud)?["volumeDb"] == .number(-6) && item(sound, in: loud)?["volumeDb"] == .number(-6))
        #expect(item("plan-b-audio", in: loud)?["muted"] == .bool(true))
    }

    @Test("A cover unmuted by hand stays unmuted; one the build muted stays muted")
    func keepsUnmutedCover() throws {
        let covered = #"{"clips":[{"id":"a","media":"m","quote":"các bạn ơi giá năm chục","cover":[{"media":"m","from":10}]}]}"#
        let built = try captions.apply(covered, on: captions.base.project())
        #expect(item("plan-a-cover1", in: built)?["muted"] == .bool(true))
        #expect(item("plan-a-cover1", in: try captions.apply(covered, on: built))?["muted"] == .bool(true))
        let unmuted = try edited(built, .setProperties(item: "plan-a-cover1", patch: ["muted": .bool(false)]))
        #expect(item("plan-a-cover1", in: try captions.apply(covered, on: unmuted))?["muted"] == .bool(false))
    }

    @Test("A music bed trimmed or extended by hand keeps its span while the list plays the same music from the same point")
    func keepsHandMusicSpan() throws {
        let built = try captions.apply(captions.twoClips(), on: captions.base.project())
        let bed = try #require(item("plan-music", in: built))
        let fps = built.fps.value
        for length in [bed.duration / 2, bed.duration + Int(5 * fps)] {
            var trimmed = built
            for track in trimmed.tracks.indices {
                for index in trimmed.tracks[track].items.indices where trimmed.tracks[track].items[index].id == bed.id {
                    trimmed.tracks[track].items[index].duration = length
                }
            }
            let after = try captions.apply(captions.twoClips(volume: -3), on: trimmed)
            #expect(item("plan-music", in: after)?.duration == length)
            #expect(item("plan-music", in: after)?.at == 0)
            // Music from another point is a new bed, as long as the clips.
            let moved = #"""
                {"clips":[{"id":"b","media":"m","quote":"xin chào"},{"id":"a","media":"m","quote":"các bạn ơi giá năm chục"}],
                "music":{"media":"song","from":4,"volumeDb":-3}}
                """#
            #expect(item("plan-music", in: try captions.apply(moved, on: after))?.duration == bed.duration)
        }
        // Untouched, the bed follows the edit's length.
        let longer = #"""
            {"clips":[{"id":"b","media":"m","quote":"xin chào"},{"id":"a","media":"m","from":2,"to":6}],
            "music":{"media":"song","volumeDb":-3}}
            """#
        #expect(try #require(item("plan-music", in: try captions.apply(longer, on: built))).duration > bed.duration)
    }

    @Test("Captions deleted by hand stay deleted when an apply rebuilds the captions; new speech gets its captions")
    func keepsDeletedCaptions() throws {
        let built = try captions.apply(captions.twoClips(), on: captions.base.project())
        #expect(captions.cues(built).map(\.text) == ["xin chào", "các bạn ơi giá năm chục"])
        let junk = try #require(captions.cues(built).first)
        let deleted = try edited(built, .delete(item: junk.id, ripple: false))
        let restyled = try captions.apply(captions.twoClips(captions: #"{"from":"speech","style":{"size":0.07}}"#), on: deleted)
        #expect(captions.cues(restyled).map(\.text) == ["các bạn ơi giá năm chục"])
        #expect(captions.cues(restyled).allSatisfy { $0["textStyle"]?.object["size"] == .number(0.07) })
        // A cue cut from a grouped set stays out; a new clip's speech gets its captions.
        let grouped = try captions.regrouped(try captions.apply(captions.list(), on: captions.base.project()))
        let cut = try edited(grouped, .delete(item: try #require(captions.cues(grouped).first).id, ripple: false))
        #expect(captions.cues(try captions.apply(captions.twoClips(), on: cut)).map(\.text) == ["xin chào", "giá năm chục"])
        // Captions added to a list that had none caption everything.
        let silent = try captions.apply(
            #"{"clips":[{"id":"b","media":"m","quote":"xin chào"},{"id":"a","media":"m","quote":"các bạn ơi giá năm chục"}]}"#,
            on: captions.base.project())
        #expect(captions.cues(try captions.apply(captions.twoClips(), on: silent)).count == 2)
    }

    @Test("Words cut from a cue by hand stay out of the rebuilt cue, and rule grouping holds through a hand ramp")
    func keepsPartialDeletesAndGroupingWithRamp() throws {
        let built = try captions.apply(captions.list(), on: captions.base.project())
        // "các bạn ơi giá năm chục" cut down to "giá năm chục" by hand.
        let grouped = try captions.regrouped(built)
        let first = try #require(captions.cues(grouped).first)
        let trimmed = try edited(grouped, .delete(item: first.id, ripple: false))
        let after = try captions.apply(captions.list(captions: #"{"from":"speech","style":{"size":0.07}}"#), on: trimmed)
        #expect(captions.cues(after).map(\.text) == ["giá năm chục"])

        let rule = CaptionGrouping.Rule(maxChars: 12, maxSeconds: 10, breakGapSeconds: 5)
        let words = captions.spans(built)
        let groups = CaptionGrouping.groups(words, rule: rule, fps: built.fps.value, cuts: CaptionGrouping.cuts(built))
        let ruled = try built.applying(
            CaptionGrouping.operation(built, words: words, groups: groups, author: .agent, mark: rule.json).operation).project
        let ramped = try edited(ruled, .setSpeedCurve(item: "plan-a", curve: ramp(), keepDuration: false))
        let rebuilt = try captions.apply(captions.twoClips(), on: ramped)
        #expect(item("plan-a", in: rebuilt)?.speedCurve == (try ramp()))
        #expect(captions.cues(rebuilt).count >= 2)
        #expect(captions.cues(rebuilt).allSatisfy { CaptionGrouping.Rule(json: $0[CaptionGrouping.field]) == rule })
        #expect(captions.cues(rebuilt).allSatisfy { $0.text.count <= 12 })
    }
}
