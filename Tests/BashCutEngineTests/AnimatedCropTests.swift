import AVFoundation
import BashCutProject
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import BashCutEngine

/// Keyed `crop.*` fields (rounded corners and sides) cut the picture anew at each frame.
struct AnimatedCropTests {
    /// A 200×100 opaque red PNG.
    private func writeRed(to url: URL) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(try #require(CGColor(colorSpace: space, components: [1, 0, 0, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// The red value of pixel (x, y) from the top left.
    private func red(_ image: CGImage, x: Int, y: Int) throws -> UInt8 {
        var result = [UInt8](repeating: 0, count: 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try result.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return result[0]
    }

    @Test("crop.radius and crop.left keys round the corners and cut the side over the item")
    func keyedCrop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRed(to: root.appendingPathComponent("red.png"))
        var project = Project(name: "Crop keys")
        project["clipFill"] = .bool(false)
        let image = Media(fields: [
            "id": .string("still"), "path": .string("red.png"), "kind": .string("image"), "fps": project.fps.json,
            "frames": .integer(100_000), "width": .integer(200), "height": .integer(100), "hasAudio": .bool(false),
        ])
        var item = Item(id: "i", media: "still", at: 0, duration: 30)
        item["keyframes"] = ItemMotion(keys: [
            "crop.radius": [.init(frame: 0, value: 0, ease: .linear), .init(frame: 29, value: 0.5)],
            "crop.left": [.init(frame: 0, value: 0, ease: .hold), .init(frame: 15, value: 0.5)],
        ]).json
        project = try project.applying(.group(label: "Keys", author: .user, ops: [
            .addMedia(image), .insert(track: "v1", item: item),
        ])).project
        let snapshot = try await CompositionBuilder().build(project, root: root)
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // Fitted, the picture is 1080×540 from y 690 to 1230; a corner pixel and a pixel left of centre.
        let first = try await generator.image(at: project.fps.time(0)).image
        #expect(try red(first, x: 4, y: 694) > 200)
        #expect(try red(first, x: 270, y: 960) > 200)
        let last = try await generator.image(at: project.fps.time(29)).image
        // The left half is cut and the corners of what is left (540×540) are rounded to a circle.
        #expect(try red(last, x: 1076, y: 694) < 40)
        #expect(try red(last, x: 270, y: 960) < 40)
        #expect(try red(last, x: 810, y: 960) > 200)
    }

    @Test("Crop sides and radius are keyframable on clips and images, not on text")
    func properties() {
        #expect(ItemMotion.properties(onTrackKind: TrackKind.video).contains("crop.radius"))
        #expect(!ItemMotion.properties(onTrackKind: TrackKind.text).contains("crop.radius"))
        #expect(ItemMotion.ranges["crop.left"] == 0...0.95 && ItemMotion.ranges["crop.radius"] == 0...0.5)
        let motion = ItemMotion(keys: ["crop.radius": [.init(frame: 0, value: 0.2)]])
        #expect(motion.keysCrop && motion.style != nil)
        #expect(motion.styled(["crop": .object(["left": .number(0.1)])], at: 0)["crop"]
            == .object(["left": .number(0.1), "radius": .number(0.2)]))
    }
}
