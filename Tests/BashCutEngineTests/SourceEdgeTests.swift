import AVFoundation
import BashCutProject
import BashCutTestSupport
import CoreImage
import Testing

@testable import BashCutEngine

/// Clips that use a camera file to its very first or last frame, as import records it, must export with picture
/// from the first to the last timeline frame.
struct SourceEdgeTests {
    enum Clip: String, CaseIterable, CustomTestStringConvertible {
        case whole, doubleSpeed, freezeLast, ramp, transitionAtEnd
        var testDescription: String { rawValue }
    }

    static let shapes: [(String, SourceEdgeMovie.Shape)] = [
        ("audio past picture", .init(pictures: 60, audioSeconds: 2.3)),
        ("late first picture", .init(pictures: 60, videoStart: CMTime(value: 1, timescale: 10), audioSeconds: 2.2)),
        ("23.976 fps", .init(pictures: 48, frame: CMTime(value: 1001, timescale: 24000), audioSeconds: 2.2)),
        ("25 fps", .init(pictures: 50, frame: CMTime(value: 1, timescale: 25), audioSeconds: 2.2)),
        ("30 fps", .init(pictures: 60, frame: CMTime(value: 1, timescale: 30), audioSeconds: 2.1)),
    ]

    @Test("Edge-to-edge clips export with picture on every frame", arguments: 0..<shapes.count, Clip.allCases)
    func export(shapeIndex: Int, clip: Clip) async throws {
        let (name, shape) = Self.shapes[shapeIndex]
        let root = try TestFixtures.temporaryDirectory("source-edge")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("camera.mov")
        try await SourceEdgeMovie.write(shape, to: file)
        let media = try await SourceEdgeMovie.media(file)
        var project = Project(name: "Source edge")
        var format = project["format"]?.object ?? [:]
        format["fps"] = FrameRate(30, 1).json
        format["width"] = .integer(320)
        format["height"] = .integer(180)
        project["format"] = .object(format)
        let full = media.placementFrames(in: project.fps)
        var ops: [EditOperation] = [.addMedia(media)]
        switch clip {
        case .whole:
            ops.append(.insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: full)))
        case .doubleSpeed:
            var item = Item(id: "a", media: "m", at: 0, duration: full / 2)
            item["speed"] = .number(2)
            ops.append(.insert(track: "v1", item: item))
        case .freezeLast:
            var item = Item(id: "a", media: "m", at: 0, duration: 30)
            item["freezeFrame"] = .integer(media.frames - 1)
            ops.append(.insert(track: "v1", item: item))
        case .ramp:
            let curve = try #require(SpeedCurve.preset("hero"))
            var item = Item(id: "a", media: "m", at: 0, duration: Int((Double(full) / curve.average).rounded(.down)))
            item["speedCurve"] = curve.json
            item["speed"] = .number(curve.average)
            ops.append(.insert(track: "v1", item: item))
        case .transitionAtEnd:
            ops += [
                .insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: full)),
                .insert(track: "v1", item: Item(id: "b", media: "m", at: full, duration: full)),
                .upsertTransition(id: "t", kind: "dissolve", from: "a", to: "b", duration: 8),
            ]
        }
        project = try project.applying(.group(label: "Fixture", author: .user, ops: ops)).project
        let snapshot = try await CompositionBuilder().build(project, root: root)
        let output = root.appendingPathComponent("export.mp4")
        do {
            try await Exporter().export(snapshot, to: output, settings: ExportSettings(preset: .quickDraft))
        } catch {
            Issue.record("\(name) / \(clip.rawValue): \(error) (media frames \(media.frames), timeline \(project.duration))")
            return
        }
        let rendered = AVURLAsset(url: output)
        let picture = try #require(try await rendered.loadTracks(withMediaType: .video).first)
        #expect(try await picture.load(.timeRange).end == project.fps.time(project.duration),
                "\(name) / \(clip.rawValue): the video track ends before the timeline")
        let generator = AVAssetImageGenerator(asset: rendered)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for frame in [0, project.duration - 1] {
            let image = try await generator.image(at: project.fps.time(frame)).image
            #expect(Self.isPicture(image), "\(name) / \(clip.rawValue): frame \(frame) is black")
        }
    }

    private static func isPicture(_ image: CGImage) -> Bool {
        let source = CIImage(cgImage: image)
        guard let average = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: source, kCIInputExtentKey: CIVector(cgRect: source.extent),
        ])?.outputImage else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return pixel.prefix(3).contains { $0 > 30 }
    }
}
