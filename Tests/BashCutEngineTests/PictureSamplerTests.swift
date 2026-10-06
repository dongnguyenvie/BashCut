@preconcurrency import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

/// The picture review's measurement (#432) on rendered fixture movies: black, still and moving picture, and cuts.
struct PictureSamplerTests {
    /// A video-only 160×90, 30 fps movie of `frames` pictures; `shade(index)` is the grey level of picture `index`
    /// (a horizontal ramp is added unless `flat`).
    static func writeMovie(
        to url: URL, frames: Int, flat: Bool = false, width: Int = 160, height: Int = 90,
        dot: ((Int) -> (x: Int, y: Int))? = nil, shade: (Int) -> Int
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CancellationError() }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            var value: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &value)
            let buffer = try #require(value)
            CVPixelBufferLockBaseAddress(buffer, [])
            let bytes = try #require(CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self))
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            // One row is drawn and copied down, so large frames stay quick to write.
            for column in 0..<width {
                let level = UInt8(max(0, min(255, shade(index) + (flat ? 0 : column * 80 / width))))
                (bytes[column * 4], bytes[column * 4 + 1], bytes[column * 4 + 2], bytes[column * 4 + 3]) =
                    (level, level, level, 255)
            }
            for row in 1..<height { memcpy(bytes + row * stride, bytes, width * 4) }
            // A small white square, such as a mouth or a ticker moving on a still background.
            if let (x, y) = dot?(index) {
                for row in y..<min(height, y + 6) { memset(bytes + row * stride + x * 4, 255, 6 * 4) }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else {
                throw writer.error ?? CancellationError()
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CancellationError() }
    }

    static func media(_ id: String, _ file: String, frames: Int) -> Media {
        Media(fields: [
            "id": .string(id), "path": .string(file), "kind": .string("video"), "fps": FrameRate(30, 1).json,
            "frames": .integer(frames), "hasAudio": .bool(false),
        ])
    }

    @Test("Black, frozen and moving picture and a jump cut between two copies of one shot")
    func measure() async throws {
        let root = try TestFixtures.temporaryDirectory("picture-sampler")
        defer { try? FileManager.default.removeItem(at: root) }
        try await Self.writeMovie(to: root.appendingPathComponent("moving.mov"), frames: 90) { 20 + $0 * 2 }
        try await Self.writeMovie(to: root.appendingPathComponent("black.mov"), frames: 30, flat: true) { _ in 0 }
        try await Self.writeMovie(to: root.appendingPathComponent("still.mov"), frames: 150) { _ in 60 }
        var project = Project(name: "Picture", fps: FrameRate(30, 1))
        project = try project.applying(.setFormat(width: 320, height: 180)).project
        project["review"] = .object(["maxStillSeconds": .number(3)])
        project = try project.applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(Self.media("moving", "moving.mov", frames: 90)),
            .addMedia(Self.media("black", "black.mov", frames: 30)),
            .addMedia(Self.media("still", "still.mov", frames: 150)),
            .addMedia(Self.media("still-copy", "still.mov", frames: 150)),
            .insert(track: "v1", item: Item(id: "a", media: "moving", at: 0, duration: 60)),
            .insert(track: "v1", item: Item(id: "b", media: "black", at: 60, duration: 30)),
            .insert(track: "v1", item: Item(id: "c", media: "still", at: 90, duration: 120)),
            .insert(track: "v1", item: Item(id: "d", media: "still-copy", at: 210, duration: 30)),
            .insert(track: "v1", item: Item(id: "e", media: "moving", at: 240, duration: 60)),
        ])).project
        let snapshot = try await CompositionBuilder().build(project, root: root)
        let picture = try await PictureSampler.measure(snapshot, project: project)
        #expect(picture.revision == project.revision)
        #expect(picture.interval == 15)
        #expect(picture.samples.count == 20)
        let black = picture.samples.filter(picture.isBlack).map(\.frame)
        #expect(black == [60, 75], "black samples: \(black)")
        let moving = picture.samples.filter { $0.frame > 0 && $0.frame < 60 }
        #expect(moving.allSatisfy { $0.change > ReviewPicture.stillChange }, "\(moving)")
        let still = picture.samples.filter { $0.frame > 90 && $0.frame < 240 }
        #expect(still.allSatisfy { $0.isStill }, "\(still)")
        #expect(Set(picture.cuts.keys) == ["b", "c", "d", "e"])
        #expect((picture.cuts["d"] ?? 1) < ReviewPicture.jumpCutChange)
        #expect((picture.cuts["b"] ?? 0) > ReviewPicture.jumpCutChange)

        let issues = TimelineReview.run(project, context: ReviewContext(picture: picture))
        let black0 = try #require(issues.first { $0.id.hasPrefix("black-") })
        #expect(black0.severity == .error)
        #expect(black0.frame == 60 && black0.endFrame == 90)
        let frozen = try #require(issues.first { $0.id.hasPrefix("still-") })
        #expect(frozen.frame == 90 && frozen.endFrame == 240)
        #expect(issues.contains { $0.id == "jump-d" && $0.fix?.command == "timeline.apply" })
        #expect(!issues.contains { $0.id == "jump-c" || $0.id == "jump-e" })
    }

    @Test("A small part moving on a still background is not frozen picture")
    func smallMovement() async throws {
        let root = try TestFixtures.temporaryDirectory("picture-sampler-dot")
        defer { try? FileManager.default.removeItem(at: root) }
        try await Self.writeMovie(
            to: root.appendingPathComponent("dot.mov"), frames: 180, dot: { (20 + ($0 / 15 % 2) * 60, 40) },
            shade: { _ in 90 })
        var project = Project(name: "Dot", fps: FrameRate(30, 1))
        project = try project.applying(.setFormat(width: 320, height: 180)).project
        project = try project.applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(Self.media("dot", "dot.mov", frames: 180)),
            .insert(track: "v1", item: Item(id: "a", media: "dot", at: 0, duration: 180)),
        ])).project
        let picture = try await PictureSampler.measure(try await CompositionBuilder().build(project, root: root), project: project)
        let moving = picture.samples.dropFirst()
        #expect(moving.allSatisfy { $0.change < 0.01 }, "the mean barely moves: \(moving.map(\.change))")
        #expect(moving.allSatisfy { !$0.isStill }, "\(moving.map(\.peak))")
        let issues = TimelineReview.run(project, context: ReviewContext(picture: picture))
        #expect(!issues.contains { $0.id.hasPrefix("still-") })
    }

    /// The ticket's budget (#432): a 3-minute 1080p edit. Run with BASHCUT_PERF=1.
    @Test("A 3-minute 1080p edit measures in under a minute",
          .enabled(if: ProcessInfo.processInfo.environment["BASHCUT_PERF"] == "1"))
    func threeMinutes() async throws {
        let root = try TestFixtures.temporaryDirectory("picture-sampler-perf")
        defer { try? FileManager.default.removeItem(at: root) }
        try await Self.writeMovie(to: root.appendingPathComponent("hd.mov"), frames: 600, width: 1920, height: 1080) {
            ($0 * 3) % 170
        }
        var project = Project(name: "Picture perf", fps: FrameRate(30, 1))
        project = try project.applying(.setFormat(width: 1920, height: 1080)).project
        var ops: [EditOperation] = [.addMedia(Self.media("hd", "hd.mov", frames: 600))]
        for index in 0..<36 {
            var item = Item(id: "c\(index)", media: "hd", at: index * 150, duration: 150)
            item["in"] = .integer((index * 97) % 450)
            ops.append(.insert(track: "v1", item: item))
        }
        project = try project.applying(.group(label: "Fixture", author: .user, ops: ops)).project
        #expect(project.duration == 5_400)
        let start = ContinuousClock.now
        let snapshot = try await CompositionBuilder().build(project, root: root, purpose: .preview)
        let picture = try await PictureSampler.measure(snapshot, project: project)
        let elapsed = start.duration(to: .now)
        print("PictureSampler: 3 min 1080p, \(picture.samples.count) samples, \(picture.cuts.count) cuts in \(elapsed)")
        #expect(picture.samples.count == 360)
        #expect(elapsed < .seconds(60), "\(elapsed)")
    }

    @Test("Thumbnails: flat black has no spread, identical pictures do not differ")
    func statistics() {
        let black = [UInt8](repeating: 0, count: 16)
        #expect(PictureSampler.statistics(black) == (0, 0))
        let ramp = (0..<16).map { UInt8($0 * 16) }
        #expect(PictureSampler.statistics(ramp).spread > 0.2)
        #expect(PictureSampler.difference(ramp, ramp) == 0)
        #expect(abs(PictureSampler.difference(black, [UInt8](repeating: 255, count: 16)) - 1) < 0.0001)
    }
}
