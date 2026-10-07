@preconcurrency import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

/// Footage this Mac cannot decode (VP9 without its decoder; here a made-up codec): preview leaves it out and says
/// where, export refuses, and the proxy probe reports it instead of calling it light enough to skip.
struct UndecodableMediaTests {
    private func projectFolder() async throws -> URL {
        let video = try await TestFixtures.requireVideo()
        let root = try TestFixtures.temporaryDirectory("undecodable")
        try FileManager.default.copyItem(at: video, to: root.appendingPathComponent("clip.mp4"))
        try await UndecodableMovie.write(to: root.appendingPathComponent("odd.mov"), frames: 60)
        return root
    }

    /// The fixture clip on frames 0..<30, then the undecodable movie on 30..<60.
    private func project() throws -> Project {
        let clip = Media(fields: [
            "id": .string("clip"), "path": .string("clip.mp4"), "fps": FrameRate().json, "frames": .integer(59),
        ])
        let odd = Media(fields: [
            "id": .string("odd"), "path": .string("odd.mov"), "fps": FrameRate(30, 1).json, "frames": .integer(60),
            "hasAudio": .bool(false),
        ])
        return try Project(name: "Undecodable").applying(
            .group(label: "Fixture", author: .user, ops: [
                .addMedia(clip), .addMedia(odd),
                .insert(track: "v1", item: Item(media: "clip", at: 0, duration: 30)),
                .insert(track: "v1", item: Item(media: "odd", at: 30, duration: 30)),
            ])
        ).project
    }

    @Test("Preview builds without the undecodable item and says which frames it covers; export refuses")
    func build() async throws {
        let root = try await projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let builder = CompositionBuilder(source: OriginalMediaSource())
        let value = try project()
        let preview = try await builder.build(value, root: root, purpose: .preview)
        let expected = UndecodableMedia(mediaID: "odd", path: "odd.mov", codec: UndecodableMovie.codec, start: 30, end: 60)
        #expect(preview.undecodable == [expected])
        #expect(preview.undecodable(at: 10).isEmpty && preview.undecodable(at: 30) == [expected])

        // The decodable clip still renders.
        let generator = AVAssetImageGenerator(asset: preview.composition)
        generator.videoComposition = preview.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        _ = try await generator.image(at: value.fps.time(10))

        await #expect(throws: UndecodableMediaError([expected])) {
            try await builder.build(value, root: root, purpose: .export)
        }
        #expect(UndecodableMediaError([expected]).localizedDescription.contains("odd.mov (bczz)"))
    }

    @Test("The proxy probe marks undecodable video; decodable footage stays decodable")
    func probe() async throws {
        let root = try await projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let odd = try #require(try await ProxyManager().probe(root.appendingPathComponent("odd.mov")))
        #expect(!odd.decodable && odd.codec == UndecodableMovie.codec)
        #expect(try await ProxyManager().probe(root.appendingPathComponent("clip.mp4"))?.decodable == true)
    }
}
