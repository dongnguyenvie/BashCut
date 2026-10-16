import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

@Suite("Batch-fix actions (P2-C3)")
struct BatchFixTests {
    private static func caption(_ id: String, _ text: String, at: Int, timed: Bool = false) -> Item {
        var item = Item(id: id, at: at, duration: 60)
        item["text"] = .string(text)
        if timed {
            item["words"] = .array(CaptionWords.tokens(text).enumerated().map { index, word in
                .object(["text": .string(word), "at": .integer(index * 10), "dur": .integer(8)])
            })
        }
        return item
    }

    /// Captions `c1`–`c3` on the Captions layer and the title `t` on another text layer.
    private static func project() throws -> Project {
        var project = Project(name: "Fix", fps: FrameRate(30, 1))
        let captions = try project.requireTrack(role: TrackRole.captions).id
        var title = Track(id: "titles", kind: TrackKind.text, role: TrackRole.overlay)
        title.items = [caption("t", "Shop at Acme", at: 0)]
        project = try project.applying(.group(label: "Setup", author: .user, ops: [
            .insert(track: captions, item: caption("c1", "We love acme so much", at: 0, timed: true)),
            .insert(track: captions, item: caption("c2", "Acme, Acmeville and ACME!", at: 60)),
            .insert(track: captions, item: caption("c3", "Nothing here", at: 120, timed: true)),
            .addTrack(track: title, atIndex: 0),
        ])).project
        return project
    }

    private static func item(_ project: Project, _ id: String) throws -> Item {
        try #require(project.tracks.flatMap(\.items).first { $0.id == id })
    }

    private static func apply(_ operations: [EditOperation], to project: Project) throws -> Project {
        try project.applying(.group(label: "Fix", author: .user, ops: operations)).project
    }

    @Test("Find and replace changes only captions, ignores case, keeps whole words and word timings")
    func replaceInCaptions() throws {
        let project = try Self.project()
        let (operations, changes) = try project.captionReplaceOperations(CaptionReplace(find: "acme", replacement: "Zeta"))
        #expect(changes.map(\.item) == ["c1", "c2"])
        #expect(changes.map(\.count) == [1, 2])
        let fixed = try Self.apply(operations, to: project)
        let first = try Self.item(fixed, "c1")
        #expect(first.text == "We love Zeta so much")
        #expect(first["words"]?.array.compactMap { $0.object["text"]?.string } == ["We", "love", "Zeta", "so", "much"])
        #expect(first.wordTimings.map(\.at) == [0, 10, 20, 30, 40])
        #expect(try Self.item(fixed, "c2").text == "Zeta, Acmeville and Zeta!")
        #expect(try Self.item(fixed, "t").text == "Shop at Acme")
        #expect(try Self.item(fixed, "c3") == Self.item(project, "c3"))

        let exact = try project.captionReplaceOperations(CaptionReplace(find: "ACME", replacement: "Zeta", matchCase: true))
        #expect(exact.changes.map(\.after) == ["Acme, Acmeville and Zeta!"])
        let inside = try project.captionReplaceOperations(CaptionReplace(find: "acme", replacement: "Z", wholeWord: false))
        #expect(inside.changes.last?.after == "Z, Zville and Z!")
        // Special characters are literal, in the text and the replacement.
        #expect(try CaptionReplace(find: "a.b", replacement: "$1").apply(to: "a.b axb") == ("$1 axb", 1))
        #expect(throws: ProjectError.self) { try CaptionReplace(find: " ", replacement: "x").apply(to: "a b") }
    }

    @Test("A replacement that changes the word count drops the timings, which are then estimated")
    func replaceRetimes() throws {
        let project = try Self.project()
        let (operations, changes) = try project.captionReplaceOperations(
            CaptionReplace(find: "love", replacement: "really like"))
        #expect(changes.map(\.retimed) == [true])
        let fixed = try Self.apply(operations, to: project)
        let first = try Self.item(fixed, "c1")
        #expect(first["words"] == nil && first.wordTimings.count == 6)
        #expect(try project.captionReplaceOperations(CaptionReplace(find: "zzz", replacement: "y")).ops.isEmpty)
    }

    @Test("Caption style restyles every caption: preset, then style merged, then word style")
    func styleCaptions() throws {
        var project = try Self.project()
        project = try Self.apply([.setProperties(item: "c1", patch: [
            "textStyle": .object(["font": .string("Old"), "strokeWidth": .integer(2)]),
        ])], to: project)
        let preset = LibraryTextPreset(textPreset: "hook-title", textStyle: ["fill": .string("#FFD400")])
        let operations = try project.captionStyleOperations(
            preset: preset, style: ["size": .number(0.06), "strokeWidth": .null], wordStyle: .string("karaoke"))
        let fixed = try Self.apply(operations, to: project)
        for id in ["c1", "c2", "c3"] {
            let item = try Self.item(fixed, id)
            #expect(item.textPreset == "hook-title")
            #expect(item["textStyle"]?.object["fill"] == .string("#FFD400"))
            #expect(item["textStyle"]?.object["size"] == .number(0.06))
            #expect(item["textStyle"]?.object["strokeWidth"] == nil)
            #expect(item.wordStyle == "karaoke")
        }
        #expect(try Self.item(fixed, "c1")["textStyle"]?.object["font"] == .string("Old"))
        #expect(try Self.item(fixed, "t").textPreset == nil)

        let plain = try Self.apply(project.captionStyleOperations(wordStyle: .null), to: fixed)
        #expect(try Self.item(plain, "c2").wordStyle == nil)
        #expect(throws: ProjectError.self) { try project.captionStyleOperations() }
        #expect(throws: ProjectError.self) { try project.captionStyleOperations(style: ["colour": .string("#FFFFFF")]) }
        #expect(throws: ProjectError.self) { try project.captionStyleOperations(wordStyle: .string("wobble")) }
        #expect(throws: ProjectError.self) {
            try Self.apply(project.captionStyleOperations(style: ["fill": .string("red")]), to: project)
        }
        #expect(throws: ProjectError.self) { try Project(name: "Empty").captionStyleOperations(wordStyle: .null) }
    }

    private static func sound(_ id: String, seconds: Int) -> Media {
        ProjectFixtures.media(id, path: "music/\(id).wav", frames: seconds * 30, fps: FrameRate(30, 1), kind: "audio",
                              hasAudio: true)
    }

    /// Two clips of the bed `old` on the Music layer: frames 30–330 and 330–630, at −18 dB with fades.
    private static func bedProject() throws -> Project {
        var project = try ProjectFixtures.twoClips("a", "b")
        let music = try project.requireTrack(role: TrackRole.music).id
        var first = Item(id: "m1", media: "old", at: 30, duration: 300)
        first["volumeDb"] = .number(-18)
        first["fadeIn"] = .integer(15)
        var second = Item(id: "m2", media: "old", at: 330, duration: 300, sourceIn: 300)
        second["volumeDb"] = .number(-18)
        second["fadeOut"] = .integer(45)
        project = try project.applying(.group(label: "Bed", author: .user, ops: [
            .addMedia(sound("old", seconds: 30)), .insert(track: music, item: first), .insert(track: music, item: second),
        ])).project
        return project
    }

    @Test("Replacing the music bed covers its span at the old level and fades, looping a short sound, as one undo step")
    func replaceMusic() throws {
        let project = try Self.bedProject()
        let plan = try project.musicReplacePlan(Self.sound("new", seconds: 8), fromSeconds: 1)
        #expect(plan.removed == ["m1", "m2"] && plan.at == 30 && plan.duration == 600 && plan.looped && !plan.shortened)
        var history = ProjectHistory(project: project)
        try history.apply(.group(label: "Replace music", author: .user, ops: plan.planner.operations), label: "Replace music")
        #expect(history.undoEntries.count == 1)
        let bed = history.project.musicBedItems.map(\.item)
        #expect(bed.map(\.id) == plan.itemIDs && bed.allSatisfy { $0.mediaID == "new" && $0.sourceIn == 30 })
        #expect(bed.map(\.at) == [30, 240, 450] && bed.map(\.duration) == [210, 210, 180])
        #expect(bed.allSatisfy { $0["volumeDb"] == .number(-18) })
        #expect(bed.first?["fadeIn"] == .integer(15) && bed.dropFirst().allSatisfy { $0["fadeIn"] == nil })
        #expect(bed.last?["fadeOut"] == .integer(45) && bed.dropLast().allSatisfy { $0["fadeOut"] == nil })
        #expect(history.project.media.contains { $0.id == "new" })

        let once = try project.musicReplacePlan(Self.sound("new", seconds: 8), loop: false)
        #expect(once.itemIDs.count == 1 && once.duration == 240 && once.shortened && !once.looped)
        #expect(throws: ProjectError.self) { try project.musicReplacePlan(Self.sound("new", seconds: 8), fromSeconds: 9) }
        #expect(throws: ProjectError.self) {
            try project.musicReplacePlan(ProjectFixtures.media("v", path: "v.mov", frames: 300, fps: FrameRate(30, 1)))
        }
        #expect(throws: ProjectError.self) { try ProjectFixtures.twoClips("a", "b").musicReplacePlan(Self.sound("new", seconds: 8)) }
    }

    @Test("The step catalog offers each batch fix as a step a pipeline can run")
    func stepCatalog() throws {
        for action in ["captions.replace", "captions.style", "library.apply", "music.replace", "export"] {
            let entry = try #require(BatchStepCatalog.entry(action))
            #expect(entry.step.action == action && entry.step.label == entry.title)
        }
        #expect(BatchStepCatalog.entries.filter { $0.group == .fix }.count == 4)
        #expect(Set(BatchStepCatalog.entries.map(\.action)).count == BatchStepCatalog.entries.count)
        let pipeline = BatchPipeline(name: "Fix", inputs: [BatchInput(path: "a")], steps: BatchStepCatalog.entries.map(\.step))
        #expect(pipeline.steps.count == BatchStepCatalog.entries.count)
    }
}
