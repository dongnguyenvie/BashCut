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
        let builder = CompositionBuilder()
        let snapshot = try await builder.build(project, root: TestFixtures.mediaRoot)
        _ = try await builder.build(project, root: TestFixtures.mediaRoot)
        #expect(await builder.rampPlanBuilds == 1)
        let video = try #require(snapshot.composition.tracks(withMediaType: .video).first)
        let pieces = video.segments.filter { !$0.isEmpty }
        // Adaptive pieces retain the curve while using fewer than the previous 20 uniform pieces.
        #expect(pieces.count > 2 && pieces.count < 20)
        let audio = try #require(snapshot.composition.tracks(withMediaType: .audio).first)
        let audioPieces = audio.segments.filter { !$0.isEmpty }
        #expect(audioPieces.count == pieces.count)
        for (sound, picture) in zip(audioPieces, pieces) {
            #expect(sound.timeMapping.source == picture.timeMapping.source)
            #expect(sound.timeMapping.target == picture.timeMapping.target)
        }
        let end = try #require(pieces.last).timeMapping.target.end
        #expect(abs(end.seconds - FrameRate().time(40).seconds) < 0.001)
        // The source used is the clip's 40 frames at 1.25× on average: 50 source frames.
        let source = try #require(pieces.last).timeMapping.source.end
        #expect(abs(source.seconds - 50 / FrameRate().value) < 0.01)
    }
}
