import AVFoundation
import BashCutProject
import BashCutTestSupport
import Testing

@testable import BashCutEngine

/// A frame the compositor could not read only said "code 2"; the error now names the item, track, media and frames.
struct RenderFrameErrorTests {
    @Test("Each video layer carries the item, track and media it shows")
    func layersNameTheirItem() async throws {
        let (directory, project) = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = try await CompositionBuilder().build(project, root: directory)
        let sources = snapshot.videoComposition.instructions
            .compactMap { $0 as? FrameInstruction }
            .flatMap(\.layers)
            .compactMap { layer -> LayerSource? in
                guard case .video(let video) = layer else { return nil }
                return video.source
            }
        let source = try #require(sources.first)
        #expect(source.itemID == "a")
        #expect(source.trackID == "v1")
        #expect(source.mediaID == "m")
        #expect(source.mediaPath.hasSuffix("clip.mov"))
        #expect(source.sourceIn == 6)
        // 30 fps project, 30 fps source: timeline frame 10 of an item at 0 with sourceIn 6 shows source frame 16.
        #expect(source.sourceFrame(at: 10) == 16)
    }

    @Test("The source frame follows speed and media rate, and a held frame stays put")
    func sourceFrameMath() {
        var source = LayerSource(
            itemID: "a", trackID: "v1", trackName: "Main", mediaID: "m", mediaPath: "media/a.mov", at: 100,
            sourceIn: 50, speed: 2, projectFPS: 30, mediaFPS: 60)
        // 15.5 frames (the middle of frame 15) into the item at 2x: 1.033 s of source at 60 fps.
        #expect(source.sourceFrame(at: 115) == 112)
        source.heldFrame = 7
        #expect(source.sourceFrame(at: 115) == 7)
        let error = RenderFrameError(frame: 115, reason: "source frame missing", source: source)
        let text = error.localizedDescription
        for part in ["frame 115", "item a", "track v1", "\"Main\"", "media m", "media/a.mov", "source frame 7"] {
            #expect(text.contains(part), "\(text)")
        }
    }

    @Test("An export whose layer frame is missing fails naming the item and frames")
    func exportNamesMissingFrame() async throws {
        let (directory, base) = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A later clip on the same track, so the lane is empty between frame 20 and 30.
        let project = try base.applying(
            .insert(track: "v1", item: Item(id: "b", media: "m", at: 30, duration: 10))).project
        let snapshot = try await CompositionBuilder().build(project, root: directory)
        let instructions = snapshot.videoComposition.instructions.compactMap { $0 as? FrameInstruction }
        let first = try #require(instructions.first?.layers.first)
        // Show item a's lane after it ends: the lane is empty there, so its frames never arrive.
        let broken = AVMutableVideoComposition()
        broken.customVideoCompositorClass = BashCutCompositor.self
        broken.renderSize = snapshot.videoComposition.renderSize
        broken.frameDuration = snapshot.videoComposition.frameDuration
        let failures = RenderFailures()
        broken.instructions = instructions.map {
            FrameInstruction(range: $0.timeRange, layers: $0.layers.isEmpty ? [first] : $0.layers, failures: failures, fps: 30)
        }
        let copy = CompositionSnapshot(
            composition: snapshot.composition, videoComposition: broken, audioMix: snapshot.audioMix,
            renderFailures: failures)
        let output = directory.appendingPathComponent("export.mp4")
        do {
            _ = try await Exporter().export(copy, to: output, settings: ExportSettings(preset: .quickDraft))
            Issue.record("The export should fail")
        } catch let error as RenderFrameError {
            #expect(error.frame == 20)
            #expect(error.source?.itemID == "a")
            #expect(error.source?.sourceFrame(at: error.frame) == 26)
            #expect(error.localizedDescription.contains("item a on track v1"), "\(error.localizedDescription)")
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    private static func fixture() async throws -> (URL, Project) {
        let directory = try TestFixtures.temporaryDirectory("render-frame-error")
        let source = directory.appendingPathComponent("clip.mov")
        try await SourceEdgeMovie.write(
            .init(pictures: 60, frame: CMTime(value: 1, timescale: 30), audioSeconds: 2), to: source)
        let media = try await SourceEdgeMovie.media(source, count: .pictures)
        let project = try Project(name: "Render error").applying(
            .group(label: "Fixture", author: .user, ops: [
                .addMedia(media),
                .insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: 20, sourceIn: 6)),
            ])).project
        return (directory, project)
    }
}
