import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

/// Results made from a source that changed since (P2-G6).
@Suite("Review provenance")
struct ReviewProvenanceTests {
    private let srt = """
        1
        00:00:01,100 --> 00:00:01,800
        Xin chào
        """

    /// Media `m` on Main with its captions from file key `k1`, a beat grid from `music` with key `b1`, and a voice
    /// take whose text hash matches its text.
    private func project() throws -> Project {
        var voice = Item(id: "vo", media: "take", at: 0, duration: 30)
        voice["voice"] = .object(["text": .string("Xin chào"), "textHash": .string(SourceHash.text("Xin chào"))])
        var project = try Project(name: "Provenance", fps: FrameRate(30, 1)).applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(ProjectFixtures.media("m", path: "m.mov", frames: 600, fps: FrameRate(30, 1), kind: "video", hasAudio: true)),
            .addMedia(ProjectFixtures.media("music", path: "music.m4a", frames: 600, fps: FrameRate(30, 1), kind: "audio", hasAudio: true)),
            .addMedia(ProjectFixtures.media("take", path: "take.wav", frames: 30, fps: FrameRate(30, 1), kind: "audio", hasAudio: true)),
            .insert(track: "v1", item: Item(id: "v", media: "m", at: 0, duration: 90)),
            .insert(track: "a2", item: voice),
        ])).project
        project = try project.applying(project.importingSubRip(
            srt, provenance: ["provider": .string("whisper"), "sourceKey": .string("k1")], media: "m")).project
        return try project.applying(.setBeatGrid(
            media: "music", bpm: 120, frames: [0, 15, 30], provenance: ["sourceKey": .string("b1")])).project
    }

    private func ids(_ project: Project, keys: [String: String]) -> [String] {
        var context = ReviewContext()
        context.mediaKeys = keys
        return TimelineReview.provenanceIssues(project, context: context).map(\.id)
    }

    @Test("Unchanged sources raise nothing; the media to key are the captions' and the beat grid's")
    func unchanged() throws {
        let project = try project()
        #expect(project.sourceKeyedMedia == ["m", "music"])
        #expect(ids(project, keys: ["m": "k1", "music": "b1"]).isEmpty)
        // A file BashCut cannot read now is not evidence of a change.
        #expect(ids(project, keys: [:]).isEmpty)
    }

    @Test("A changed media file is one info issue per media; a changed voice text is one per item")
    func changed() throws {
        var project = try project()
        #expect(ids(project, keys: ["m": "k2", "music": "b2"]) == ["captions-source-changed-m", "beats-source-changed-music"])
        project = try project.applying(.setProperties(item: "vo", patch: ["voice": .object([
            "text": .string("Xin chào các bạn"), "textHash": .string(SourceHash.text("Xin chào")),
        ])])).project
        var context = ReviewContext()
        context.mediaKeys = ["m": "k1", "music": "b1"]
        let issues = TimelineReview.provenanceIssues(project, context: context)
        let voice = try #require(issues.first)
        #expect(issues.count == 1 && voice.id == "voice-text-changed-vo" && voice.severity == .info)
        #expect(voice.fix?.command == "voice.speak" && voice.fix?.arguments["replace"] == .string("vo"))
        // review run carries them.
        #expect(TimelineReview.run(project, context: context).contains { $0.id == "voice-text-changed-vo" })
    }

    @Test("The text hash is stable, short and differs with the text")
    func textHash() {
        #expect(SourceHash.text("Xin chào") == SourceHash.text("Xin chào"))
        #expect(SourceHash.text("Xin chào").count == 24 && SourceHash.text("Xin chào") != SourceHash.text("Xin chào!"))
    }
}
