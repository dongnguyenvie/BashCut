import Testing

@testable import BashCutProject

struct ReviewTests {
    @Test("Review finds picture gaps, long caption lines and missing tagged speech")
    func rules() throws {
        var project = Project(name: "Review")
        let media = Media(fields: [
            "id": .string("m"), "path": .string("video.mov"), "frames": .integer(300),
            "fps": FrameRate().json,
        ])
        var caption = Item(id: "caption", at: 0, duration: 90)
        caption["text"] = .string(String(repeating: "a", count: 50))
        project = try project.applying(
            .group(
                label: "fixture", author: .user,
                ops: [
                    .addMedia(media),
                    .insert(track: "v1", item: Item(id: "clip", media: "m", at: 30, duration: 60)),
                    .insert(track: "t1", item: caption),
                ])
        ).project
        let issues = TimelineReview.run(project)
        #expect(Set(issues.map(\.id)) == ["gap-clip", "caption-caption", "coverage"])
    }

    @Test("Review flags voiceover closer than 0.3 seconds to tagged speech across layers")
    func voiceoverProximity() throws {
        var project = Project(name: "Voice review", fps: FrameRate(30, 1))
        let media = Media(fields: [
            "id": .string("m"), "path": .string("video.mov"), "frames": .integer(300),
            "fps": FrameRate(30, 1).json,
        ])
        var speech = Item(id: "speech", media: "m", at: 0, duration: 30)
        speech["tag"] = .object(["role": .string("speech")])
        let close = Item(id: "close", media: "m", at: 38, duration: 5)
        let boundary = Item(id: "boundary", media: "m", at: 39, duration: 5)
        var extraVoice = Track(id: "a5", kind: "audio", role: "voiceover")
        extraVoice.items = [close, boundary]
        project = try project.applying(
            .group(
                label: "fixture", author: .user,
                ops: [.addMedia(media), .insert(track: "v1", item: speech)]
            )
        ).project
        project.tracks.append(extraVoice)

        let overlapIDs = Set(
            TimelineReview.run(project).filter { $0.id.hasPrefix("overlap-") }.map(\.id))
        #expect(overlapIDs == ["overlap-close"])
        #expect(abs(TimelineReview.speechCoverage(project) - 36.0 / 44.0) < 0.0001)
    }
}
