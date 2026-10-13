import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing
@testable import BashCutEngine

/// A timeline without a single video clip used to abort the app: AVAssetReaderVideoCompositionOutput raises an
/// Objective-C exception for an empty track list.
struct ExportNoVideoTests {
    @Test("A captions-only timeline exports a picture over its whole length")
    func captionsOnly() async throws {
        let root = try TestFixtures.temporaryDirectory("captions-only-export")
        defer { try? FileManager.default.removeItem(at: root) }
        var caption = Item(id: "caption", at: 0, duration: 30)
        caption["text"] = .string("Hello")
        let project = try Project(name: "Captions only").applying(
            .group(label: "Fixture", author: .user, ops: [
                .setFormat(width: 320, height: 180), .insert(track: "t1", item: caption),
            ])).project
        let snapshot = try await CompositionBuilder().build(project, root: root)
        #expect(snapshot.composition.tracks(withMediaType: .video).count == 1)
        let final = root.appendingPathComponent("captions.mp4")
        _ = try await Exporter().export(snapshot, to: final, settings: ExportSettings(preset: .quickDraft))
        let asset = AVURLAsset(url: final)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - 1) < 0.05)
    }

    @Test("A composition without video tracks fails with an export error instead of crashing")
    func noVideoTracks() async throws {
        let root = try TestFixtures.temporaryDirectory("no-video-export")
        defer { try? FileManager.default.removeItem(at: root) }
        let composition = AVMutableComposition()
        let video = AVMutableVideoComposition()
        video.renderSize = CGSize(width: 320, height: 180)
        video.frameDuration = CMTime(value: 1, timescale: 30)
        let snapshot = CompositionSnapshot(composition: composition, videoComposition: video, audioMix: AVMutableAudioMix())
        await #expect(throws: ProjectError.self) {
            _ = try await Exporter().export(snapshot, to: root.appendingPathComponent("none.mp4"))
        }
    }
}
