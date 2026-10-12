import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

/// P3-I2 fingerprints and P3-I3 outcomes: raw numbers, nulls stay null, no verdicts.
struct OutcomesTests {
    private func project() throws -> Project {
        var caption = Item(id: "c", at: 0, duration: 60)
        caption["text"] = .string("Xin chào các bạn")
        caption["textPreset"] = .string("bold-pop")
        var music = Item(id: "mu", media: "song", at: 0, duration: 300)
        music["volumeDb"] = .number(-18)
        return try Project(name: "Fingerprint", fps: FrameRate(30, 1)).applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(ProjectFixtures.media("m", path: "footage/m.mov", frames: 900, fps: FrameRate(30, 1), kind: "video", hasAudio: true)),
            .addMedia(ProjectFixtures.media("song", path: "music/song.m4a", frames: 900, fps: FrameRate(30, 1), kind: "audio", hasAudio: true)),
            .insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: 45)),
            .insert(track: "v1", item: Item(id: "b", media: "m", at: 45, duration: 90, sourceIn: 100)),
            .insert(track: "v1", item: Item(id: "d", media: "m", at: 135, duration: 165, sourceIn: 300)),
            .insert(track: "t1", item: caption), .insert(track: "a3", item: music),
            .upsertSection(id: "hook", label: "Hook", atFrame: 0), .upsertSection(id: "body", label: "Body", atFrame: 90),
        ])).project
    }

    @Test("A fingerprint holds the cut rhythm, presets, music, hook and sections")
    func fingerprint() throws {
        let fields = ProjectFingerprint.json(try project()).object
        #expect(fields["clips"] == .integer(3) && fields["seconds"] == .number(10))
        #expect(fields["averageCutSeconds"] == .number(3.333) && fields["medianCutSeconds"] == .number(3))
        #expect(fields["captionPresets"] == .array([.string("bold-pop")]) && fields["music"] == .array([.string("song.m4a")]))
        let hook = fields["hook"]?.object ?? [:]
        #expect(hook["firstCutSeconds"] == .number(1.5) && hook["firstTextSeconds"] == .number(0))
        #expect(hook["cutsInHook"] == .integer(1) && hook["firstMedia"] == .string("m.mov"))
        #expect(hook["words"] == .string("Xin chào các bạn"))
        #expect(ProjectFingerprint.sections(try project()) == [
            .init(label: "Hook", start: 0, end: 3), .init(label: "Body", start: 3, end: 10),
        ])
    }

    @Test("CSV with a position column becomes seconds; empty cells stay null")
    func csv() throws {
        let csv = """
            Video position (%),Audience retention (%)
            0,100
            25,80
            50,
            "75",60
            100,55
            """
        let parsed = try Outcomes.parse(csv, duration: 20)
        #expect(parsed.curve.map(\.t) == [0, 5, 10, 15, 20])
        #expect(parsed.curve[2].retention == nil && parsed.curve[1].retention == 80)
        let timed = try Outcomes.parse("time;viewers\n0:00;100\n0:05;70", duration: 0)
        #expect(timed.curve.map(\.t) == [0, 5] && timed.curve.last?.retention == 70)
        #expect(throws: ProjectError.self) { try Outcomes.parse("a,b\n1,2", duration: 10) }
        let named = try Outcomes.parse("a,b\n1,2", duration: 10, columns: .init(time: "a", retention: "b"))
        #expect(named.curve == [.init(t: 1, retention: 2)])
    }

    @Test("Mapping gives raw change, drop with words, lift, replay peak and views per section")
    func map() throws {
        let json = """
            {"curve": [{"t": 0, "retention": 100}, {"t": 2, "retention": 90}, {"t": 3, "retention": 60},
                       {"t": 6, "retention": 50}, {"t": 7, "retention": 58}, {"t": 8, "retention": 52}],
             "totals": {"views": 1000, "label": "x"}}
            """
        let parsed = try Outcomes.parse(json, duration: 10)
        #expect(parsed.totals.keys.sorted() == ["views"], "only numeric totals")
        let record = Outcomes.Record(export: "x-1", platform: "tiktok", curve: parsed.curve, totals: parsed.totals)
        #expect(record.unit == "percent")
        let result = Outcomes.map(
            record, sections: [.init(label: "Hook", start: 0, end: 3), .init(label: "Body", start: 3, end: 10)],
            words: [.init(text: "giá", start: 2.5), .init(text: "rẻ", start: 2.8), .init(text: "xa", start: 9)],
            duration: 10, top: 2).object
        let sections = result["sections"]?.array.map(\.object) ?? []
        #expect(sections[0]["startRetention"] == .number(100) && sections[0]["endRetention"] == .number(60))
        #expect(sections[0]["change"] == .number(-40) && sections[0]["viewsAtStart"] == .number(1000))
        #expect(sections[0]["drop"]?.object["at"] == .number(3) && sections[0]["drop"]?.object["words"] == .string("giá rẻ"))
        #expect(sections[0]["lift"] == .null && sections[0]["replayPeak"] == .null)
        #expect(sections[1]["endRetention"] == .null, "the curve stops at 8 s: null, not a guess")
        #expect(sections[1]["lift"]?.object["change"] == .number(8))
        #expect(sections[1]["replayPeak"]?.object["at"] == .number(7))
        let drops = result["drops"]?.array.map(\.object) ?? []
        #expect(drops.count == 2 && drops[0]["change"] == .number(-30) && drops[0]["section"] == .string("Hook"))
        #expect(drops[1]["at"] == .number(2) || drops[1]["at"] == .number(6))
    }
}

/// P3-I5: numbers, prices, superlatives and names in titles and the voiceover, minus what the claims ledger covers.
struct ClaimScanTests {
    @Test("A scan finds numbers, prices, superlatives and names; Title Case finds no names")
    func scan() {
        let found = ClaimScan.scan("Hồ Tây rộng 528 ha, phở 50k là rẻ nhất. We met Lan at Phở Thìn for $5")
        #expect(found.numbers == ["528"])
        #expect(found.prices == ["50k", "$5"])
        #expect(found.superlatives == ["rẻ nhất"])
        #expect(found.names.contains("Lan") && found.names.contains("Thìn") && !found.names.contains("We"))
        #expect(ClaimScan.scan("The Best Coffee In Town").names.isEmpty)
        #expect(ClaimScan.scan("Giá 30 nghìn đồng").prices == ["30 nghìn"] || ClaimScan.scan("Giá 30 nghìn đồng").numbers == ["30"])
        let left = ClaimScan.unsourced(found, claims: ["528 ha", "phở 50k", "Lan"])
        #expect(left.numbers.isEmpty && left.prices == ["$5"] && !left.names.contains("Lan"))
    }

    @Test("Review lists unsourced claims in titles and voiceover lines at info, not in captions")
    func review() throws {
        var title = Item(id: "t", at: 30, duration: 60)
        title["text"] = .string("Only 3 days")
        var caption = Item(id: "c", at: 0, duration: 30)
        caption["text"] = .string("I paid 40 dollars")
        var project = try Project(name: "Claims").applying(.group(label: "Setup", author: .user, ops: [
            .addTrack(track: Track(id: "t2", kind: "text", role: "titles"), atIndex: 3),
            .insert(track: "t2", item: title), .insert(track: "t1", item: caption),
        ])).project
        let line: JSONValue = .object(["id": .string("l1"), "text": .string("The cheapest flight is 99 euros")])
        project["plan"] = JSONValue.object(["cut": .object(["voiceover": .array([line])])])
        let issues = TimelineReview.run(project, context: ReviewContext()).filter { $0.kind == "unsourced-claim" }
        #expect(issues.map(\.id).sorted() == ["unsourced-claim-t", "unsourced-claim-vo-l1"])
        #expect(issues.allSatisfy { $0.severity == .info })
        var context = ReviewContext()
        context.claims = ["only 3 days", "cheapest flight 99 euros"]
        #expect(TimelineReview.run(project, context: context).filter { $0.kind == "unsourced-claim" }.isEmpty)
    }
}
