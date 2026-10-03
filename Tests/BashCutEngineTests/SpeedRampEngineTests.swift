import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

struct SpeedRampEngineTests {
    @Test("A ramped clip fills exactly its timeline length with many scaled pieces of its source")
    func rampComposition() async throws {
        _ = try TestFixtures.requireVideo()
        let media = Media(fields: [
            "id": .string("m"), "path": .string("test.mp4"), "fps": FrameRate().json, "frames": .integer(59),
            "hasAudio": .bool(true),
        ])
        let ramp = try SpeedCurve([.init(t: 0, speed: 0.5), .init(t: 0.5, speed: 2), .init(t: 1, speed: 0.5)])
        let project = try Project(name: "Ramp").applying(
            .group(label: "Fixture", author: .user, ops: [
                .addMedia(media), .insert(track: "v1", item: Item(id: "c", media: "m", at: 0, duration: 40)),
                .setSpeedCurve(item: "c", curve: ramp, keepDuration: true),
            ])
        ).project
        let item = try #require(project.tracks.flatMap(\.items).first)
        #expect(item.duration == 40 && abs(item.speed - 1.25) < 1e-9)
        let snapshot = try await CompositionBuilder().build(project, root: TestFixtures.mediaRoot)
        let video = try #require(snapshot.composition.tracks(withMediaType: .video).first)
        let pieces = video.segments.filter { !$0.isEmpty }
        // 20 pieces; AVFoundation may merge neighbours that have the same rate.
        #expect(pieces.count >= 10)
        let end = try #require(pieces.last).timeMapping.target.end
        #expect(abs(end.seconds - FrameRate().time(40).seconds) < 0.001)
        // The source used is the clip's 40 frames at 1.25× on average: 50 source frames.
        let source = try #require(pieces.last).timeMapping.source.end
        #expect(abs(source.seconds - 50 / FrameRate().value) < 0.01)
    }
}
