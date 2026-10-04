import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

@Suite("Generated captions follow clips")
struct GeneratedCaptionTests {
    /// Media `m` (one second in) at frame 90 on the main layer with its linked sound, a manual caption at 0, and
    /// media `n` that is not on the timeline.
    private func project() throws -> Project {
        var video = Item(id: "v", media: "m", at: 90, duration: 60, sourceIn: 30)
        video["linkedAudio"] = .string("a")
        var audio = Item(id: "a", media: "m", at: 90, duration: 60, sourceIn: 30)
        audio["linkedVideo"] = .string("v")
        var manual = Item(id: "manual", at: 0, duration: 30)
        manual["text"] = .string("Tiêu đề")
        return try Project(name: "Captions", fps: FrameRate(30, 1)).applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(ProjectFixtures.media("m", path: "m.mov", frames: 600, fps: FrameRate(30, 1), kind: "video", hasAudio: true)),
            .addMedia(ProjectFixtures.media("n", path: "n.mov", frames: 600, fps: FrameRate(30, 1), kind: "video", hasAudio: true)),
            .insert(track: "a1", item: audio), .insert(track: "v1", item: video), .insert(track: "t1", item: manual),
        ])).project
    }

    private let srt = """
        1
        00:00:00,200 --> 00:00:00,800
        Trước

        2
        00:00:01,500 --> 00:00:02,000
        Giữa

        3
        00:00:02,800 --> 00:00:03,400
        Qua cắt
        """

    private func captions(_ project: Project) -> [Item] {
        project.tracks.filter { $0.kind == "text" }.flatMap(\.items).sorted { $0.at < $1.at }
    }

    @Test("Source times map through the clip; speech outside it is dropped and the linked pair counts once")
    func placesThroughClips() throws {
        let base = try project()
        let result = try base.applying(base.importingSubRip(srt, media: "m")).project
        let generated = captions(result).filter { $0["captionMedia"] == .string("m") }
        #expect(generated.map(\.text) == ["Giữa", "Qua cắt"])
        #expect(generated.map(\.at) == [105, 144])
        #expect(generated.map(\.end) == [120, 150])
        #expect(captions(result).contains { $0.id == "manual" })
    }

    @Test("Replacing removes only the captions made from that media")
    func replaceKeepsOtherCaptions() throws {
        var project = try project()
        project = try project.applying(project.importingSubRip(srt, media: "m")).project
        project = try project.applying(project.importingSubRip(srt, replace: true, media: "m")).project
        #expect(captions(project).map(\.text) == ["Tiêu đề", "Giữa", "Qua cắt"])
    }

    @Test("Captions from before media tracking stay, and new ones go around them")
    func olderCaptionsStay() throws {
        var project = try project()
        var older = Item(id: "older", at: 100, duration: 30)
        older["text"] = .string("Cũ")
        project = try project.applying(.insert(track: "t1", item: older)).project
        project = try project.applying(project.importingSubRip(srt, replace: true, media: "m")).project
        #expect(captions(project).map(\.text) == ["Tiêu đề", "Cũ", "Giữa", "Qua cắt"])
    }

    @Test("A range keeps only its cues and replaces only the captions heard inside it")
    func rangeReplacesOneStretch() throws {
        var project = try project()
        project = try project.applying(project.importingSubRip(srt, media: "m")).project
        let again = """
            1
            00:00:01,500 --> 00:00:02,000
            Giữa mới

            2
            00:00:02,000 --> 00:00:02,600
            Tràn ra

            3
            00:00:02,800 --> 00:00:03,400
            Ngoài khoảng
            """
        project = try project.applying(
            project.importingSubRip(again, replace: true, media: "m", range: 1.4...2.2)).project
        // Source 1.4–2.2 s plays at frames 102–126: "Giữa" goes, "Qua cắt" (frame 144) stays, the spill is cut at 2.2 s.
        #expect(captions(project).map(\.text) == ["Tiêu đề", "Giữa mới", "Tràn ra", "Qua cắt"])
        #expect(captions(project).first { $0.text == "Tràn ra" }.map { [$0.at, $0.end] } == [120, 126])
        #expect(throws: ProjectError.self) {
            try project.importingSubRip(again, media: "m", range: 10...12)
        }
    }

    @Test("Speed changes the timeline position")
    func followsSpeed() throws {
        var project = try project()
        project = try project.applying(.setSpeed(item: "v", speed: 2, keepDuration: true)).project
        project = try project.applying(project.importingSubRip(srt, media: "m")).project
        // At 2× the clip covers source 1–5 s: 1.5 s plays at 90 + 0.25 s.
        #expect(captions(project).first { $0.text == "Giữa" }?.at == 98)
    }

    @Test("Media that is not on the timeline keeps the cue times as timeline times")
    func unplacedMediaKeepsTimes() throws {
        let base = try project()
        let result = try base.applying(base.importingSubRip(srt, media: "n")).project
        #expect(captions(result).filter { $0["captionMedia"] == .string("n") }.map(\.at) == [6, 45, 84])
    }

    @Test("A muted clip gets no captions")
    func mutedClipsAreSilent() throws {
        var project = try project()
        project = try project.applying(.setProperties(item: "a", patch: ["muted": .bool(true)])).project
        #expect(throws: ProjectError.self) { try project.importingSubRip(srt, media: "m") }
    }
}
