import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing
@testable import BashCutEngine

struct ExportPublicationTests {
    @Test("Publication is exclusive even when another file appears after export started")
    func exclusivePublication() throws {
        let root = try TestFixtures.temporaryDirectory("exclusive-export")
        defer { try? FileManager.default.removeItem(at: root) }
        let final = root.appendingPathComponent("movie.mp4")
        let destination = try ExportDestination(final)
        defer { destination.discard() }
        try Data("rendered".utf8).write(to: destination.partial)
        try Data("other writer".utf8).write(to: final)
        #expect(throws: (any Error).self) { try destination.publish() }
        #expect(try Data(contentsOf: final) == Data("other writer".utf8))
        #expect(try Data(contentsOf: destination.partial) == Data("rendered".utf8))
    }

    @Test("Export publishes only a completed, playable movie", arguments: [ExportPreset.quickDraft, .proRes422HQ])
    func success(preset: ExportPreset) async throws {
        let root = try TestFixtures.temporaryDirectory("publish-export")
        defer { try? FileManager.default.removeItem(at: root) }
        let final = root.appendingPathComponent("movie." + preset.fileExtension)
        let snapshot = try await snapshot()
        let receipt = try await Exporter().export(snapshot, to: final, settings: ExportSettings(preset: preset)) { value in
            if value < 1 { #expect(!FileManager.default.fileExists(atPath: final.path)) }
            if value == 1 { #expect(FileManager.default.fileExists(atPath: final.path)) }
        }
        #expect(receipt.url == final && receipt.bytes > 0)
        let asset = AVURLAsset(url: final)
        #expect(abs(try await asset.load(.duration).seconds - snapshot.composition.duration.seconds) < 0.05)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        let picture = try await AVAssetImageGenerator(asset: asset).image(at: .zero).image
        #expect(picture.width == 320 && picture.height == 180)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [final.lastPathComponent])
    }

    @Test("A video-only composition finishes without an audio input")
    func videoOnly() async throws {
        let root = try TestFixtures.temporaryDirectory("silent-export")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try await snapshot()
        let composition = try #require(original.composition.mutableCopy() as? AVMutableComposition)
        for track in composition.tracks where track.mediaType == .audio { composition.removeTrack(track) }
        let silent = CompositionSnapshot(composition: composition, videoComposition: original.videoComposition,
                                         audioMix: AVMutableAudioMix())
        let final = root.appendingPathComponent("silent.mp4")
        _ = try await Exporter().export(silent, to: final)
        let asset = AVURLAsset(url: final)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - silent.composition.duration.seconds) < 0.05)
    }

    @Test("Cancellation after writer startup removes the partial and leaves no final file")
    func cancellation() async throws {
        let root = try TestFixtures.temporaryDirectory("cancel-export")
        defer { try? FileManager.default.removeItem(at: root) }
        let final = root.appendingPathComponent("movie.mp4"), snapshot = try await snapshot()
        let (events, continuation) = AsyncStream<Double>.makeStream()
        let task = Task {
            defer { continuation.finish() }
            return try await Exporter().export(snapshot, to: final, settings: ExportSettings(preset: .quickDraft)) { value in
                continuation.yield(value)
            }
        }
        defer { continuation.finish(); task.cancel() }
        var started = false
        for await value in events {
            started = true
            #expect(value == 0)
            #expect(!FileManager.default.fileExists(atPath: final.path))
            task.cancel()
            break
        }
        #expect(started)
        do {
            _ = try await task.value
            Issue.record("Cancelled export unexpectedly published")
        } catch is CancellationError {
            // The native writer was started, but none of its incomplete output may remain.
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("A native compositor failure terminates export and removes its partial file")
    func renderFailure() async throws {
        let root = try TestFixtures.temporaryDirectory("failed-export")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try await snapshot()
        let video = try #require(original.videoComposition.mutableCopy() as? AVMutableVideoComposition)
        video.customVideoCompositorClass = FailingExportCompositor.self
        let broken = CompositionSnapshot(composition: original.composition, videoComposition: video, audioMix: original.audioMix)
        await #expect(throws: (any Error).self) {
            _ = try await Exporter().export(broken, to: root.appendingPathComponent("failed.mp4"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("An export preserves a competing destination and cleans up its own output")
    func destinationRace() async throws {
        let root = try TestFixtures.temporaryDirectory("racing-export")
        defer { try? FileManager.default.removeItem(at: root) }
        let final = root.appendingPathComponent("movie.mp4"), snapshot = try await snapshot()
        do {
            _ = try await Exporter().export(snapshot, to: final, settings: ExportSettings(preset: .quickDraft)) { value in
                if value == 0 { try? Data("keep this".utf8).write(to: final, options: .withoutOverwriting) }
            }
            Issue.record("Export replaced a competing destination")
        } catch {
            #expect(error.localizedDescription.contains("already exists"))
        }
        #expect(try Data(contentsOf: final) == Data("keep this".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [final.lastPathComponent])
    }

    private func snapshot() async throws -> CompositionSnapshot {
        _ = try TestFixtures.requireVideo()
        let media = Media(fields: ["id": .string("m"), "path": .string("test.mp4"),
                                   "fps": FrameRate().json, "frames": .integer(59)])
        let project = try Project(name: "Publication").applying(
            .group(label: "Fixture", author: .user, ops: [.setFormat(width: 320, height: 180), .addMedia(media),
                .insert(track: "v1", item: Item(id: "clip", media: "m", at: 0, duration: 45))])).project
        return try await CompositionBuilder().build(project, root: TestFixtures.mediaRoot)
    }
}

private final class FailingExportCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        request.finish(with: NSError(domain: "ExportPublicationTests", code: 1))
    }
}
