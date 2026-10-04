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
