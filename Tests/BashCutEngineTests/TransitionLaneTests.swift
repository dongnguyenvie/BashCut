import AVFoundation
import BashCutProject
import BashCutTestSupport
import CoreGraphics
import Testing
@testable import BashCutEngine

struct TransitionLaneTests {
    private func project(clips: Int) throws -> Project {
        let media = Media(fields: [
            "id": .string("m"), "path": .string("test.mp4"), "fps": FrameRate().json, "frames": .integer(59)
        ])
        var operations: [EditOperation] = [.addMedia(media)]
        for index in 0..<clips {
            operations.append(.insert(track: "v1", item: Item(
                id: "c\(index)", media: "m", at: index * 20, duration: 20, sourceIn: index % 2 * 20)))
            if index > 0 {
                operations.append(.upsertTransition(
                    id: "t\(index)", kind: "dissolve", from: "c\(index - 1)", to: "c\(index)", duration: 8))
            }
        }
        return try Project(name: "Transitions").applying(.group(label: "Fixture", author: .user, ops: operations)).project
    }

    @Test("Sequential transition holds share two video lanes with no overlapping source requests")
    func laneCount() async throws {
        _ = try await TestFixtures.requireVideo()
        let value = try project(clips: 80)
        let built = try await CompositionBuilder().build(value, root: TestFixtures.mediaRoot)
        #expect(try await built.composition.loadTracks(withMediaType: .video).count == 2)
        for instruction in built.videoComposition.instructions {
            let frame = try #require(instruction as? FrameInstruction)
            let tracks = frame.layers.compactMap { layer -> CMPersistentTrackID? in
                guard case .video(let video) = layer else { return nil }
                return video.trackID
            }
            #expect(Set(tracks).count == tracks.count)
        }
    }

    @Test("Reused lanes render the same dissolve pictures as an isolated transition")
    func renderedPictures() async throws {
        _ = try await TestFixtures.requireVideo()
        let builder = CompositionBuilder()
        let reference = try await builder.build(project(clips: 2), root: TestFixtures.mediaRoot)
        let sequence = try await builder.build(project(clips: 12), root: TestFixtures.mediaRoot)
        func generator(_ snapshot: CompositionSnapshot) -> AVAssetImageGenerator {
            let generator = AVAssetImageGenerator(asset: snapshot.composition)
            generator.videoComposition = snapshot.videoComposition
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            return generator
        }
        let expected = generator(reference), actual = generator(sequence)
        for phase in [0, 4, 7, 8] {
            let referencePixels = try pixels(try await expected.image(at: FrameRate().time(20 + phase)).image)
            for boundary in [3, 7, 11] {
                let actualPixels = try pixels(try await actual.image(at: FrameRate().time(boundary * 20 + phase)).image)
                #expect(zip(referencePixels, actualPixels).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
            }
        }
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(
            data: nil, width: 32, height: 18, bitsPerComponent: 8, bytesPerRow: 128,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 18))
        let data = try #require(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: 128 * 18))
    }
}
