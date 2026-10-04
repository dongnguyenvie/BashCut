import AVFoundation
import BashCutProject
import BashCutTestSupport
import Testing

@testable import BashCutEngine

struct AudioDuckingTests {
    @Test("Speech and voiceover regions produce a combined music gain envelope")
    func envelope() throws {
        var project = Project(name: "Ducking", fps: FrameRate(30, 1))
        var video = Item(id: "video", media: "media", at: 20, duration: 20)
        video["tag"] = .object(["role": .string("speech")])
        var dialogue = Item(id: "dialogue", media: "media", at: 20, duration: 20)
        dialogue["linkedVideo"] = .string("video")
        let voice = Item(id: "voice", media: "media", at: 35, duration: 15)
        var tracks = project.tracks
        tracks[0].items = [video]
        tracks[3].items = [dialogue]
        tracks[4].items = [voice]
        tracks[5]["duckUnderSpeechDb"] = .integer(-20)
        tracks[5]["duckAttackFrames"] = .integer(5)
        tracks[5]["duckReleaseFrames"] = .integer(10)
        project.tracks = tracks

        let ranges = AudioGainPlanner.speechRanges(in: project)
        #expect(ranges == [20..<50])
        let music = Item(id: "music", media: "media", at: 0, duration: 70)
        let points = AudioGainPlanner.points(for: music, on: tracks[5], speech: ranges)
        #expect(points.map(\.frame) == [0, 15, 20, 50, 60, 70])
        #expect(abs((points.first { $0.frame == 20 }?.volume ?? 0) - 0.1) < 0.0001)
        #expect(points.first { $0.frame == 50 }?.volume == points.first { $0.frame == 20 }?.volume)
        #expect(points.first { $0.frame == 60 }?.volume == 1)
        let adjusted = AudioGainPlanner.points(
            for: music, on: tracks[5], speech: [], mixGainDb: -6)
        #expect(abs((adjusted.first?.volume ?? 0) - 0.501_187) < 0.0001)
    }

    @Test("A muted layer is silent and its speech no longer ducks music")
    func mutedLayer() {
        var project = Project(name: "Mute", fps: FrameRate(30, 1))
        var tracks = project.tracks
        tracks[4].items = [Item(id: "voice", media: "media", at: 10, duration: 20)]
        project.tracks = tracks
        #expect(AudioGainPlanner.speechRanges(in: project) == [10..<30])
        tracks[4]["muted"] = .bool(true)
        project.tracks = tracks
        #expect(AudioGainPlanner.speechRanges(in: project).isEmpty)
        let voice = tracks[4].items[0]
        #expect(AudioGainPlanner.points(for: voice, on: tracks[4], speech: []).allSatisfy { $0.volume == 0 })
    }

    @Test("Volume keys set the gain over the item, and a hold key jumps at the next key")
    func volumeKeys() {
        let track = Project(name: "Keys", fps: FrameRate(30, 1)).tracks[5]
        var music = Item(id: "music", media: "media", at: 100, duration: 60)
        music["volumeDb"] = .integer(6)  // replaced by the keys
        music["keyframes"] = ItemMotion(keys: ["volume": [
            .init(frame: 0, value: 0, ease: .linear), .init(frame: 20, value: -20, ease: .hold),
            .init(frame: 40, value: 0),
        ]]).json
        let points = AudioGainPlanner.points(for: music, on: track, speech: [])
        func volume(_ frame: Int) -> Float? { points.first { $0.frame == frame }?.volume }
        #expect(volume(100) == 1)
        #expect(abs((volume(120) ?? 0) - 0.1) < 0.0001)
        #expect(abs((volume(110) ?? 0) - 0.316_228) < 0.0001)  // -10 dB halfway
        #expect(points.contains { $0.frame == 104 })  // steps between keys
        #expect(abs((volume(139) ?? 0) - 0.1) < 0.0001)  // held until the next key
        #expect(volume(140) == 1)
        #expect(volume(160) == 1)
        #expect(points.allSatisfy { (100...160).contains($0.frame) })
    }

    @Test("Composition applies track ducking to music parameters")
    func composition() async throws {
        _ = try await TestFixtures.requireVideo()
        let root = TestFixtures.mediaRoot
        let media = Media(fields: [
            "id": .string("m"), "path": .string("test.mp4"),
            "fps": FrameRate().json, "frames": .integer(59),
        ])
        var voice = Item(id: "voice", media: "m", at: 15, duration: 15)
        voice["volumeDb"] = .integer(0)
        var music = Item(id: "music", media: "m", at: 0, duration: 45)
        music["preservePitch"] = .bool(false)
        var project = try Project(name: "Ducking").applying(
            .group(label: "Fixture", author: .user, ops: [
                .addMedia(media), .insert(track: "a2", item: voice), .insert(track: "a3", item: music),
                .setTrackProperties(track: "a3", patch: [
                    "duckUnderSpeechDb": .integer(-20), "duckAttackFrames": .integer(3),
                    "duckReleaseFrames": .integer(6),
                ]),
            ])).project
        project.revision = 0
        let snapshot = try await CompositionBuilder().build(project, root: root)
        let musicParameters = try #require(snapshot.audioMix.inputParameters.last)
        #expect(musicParameters.audioTimePitchAlgorithm == .varispeed)
        var start: Float = 0
        var end: Float = 0
        var range = CMTimeRange.invalid
        #expect(
            musicParameters.getVolumeRamp(
                for: project.fps.time(20), startVolume: &start, endVolume: &end, timeRange: &range))
        #expect(abs(start - 0.1) < 0.0001)
        #expect(abs(end - 0.1) < 0.0001)
    }
}
