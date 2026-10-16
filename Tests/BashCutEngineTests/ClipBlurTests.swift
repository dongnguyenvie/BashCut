import AVFoundation
import CoreImage
import BashCutProject
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import BashCutEngine

/// The item `blur`: a clip or image picture softened after its crop (a cropped copy over the clip blurs one area,
/// such as subtitles burned into the footage).
struct ClipBlurTests {
    /// A 200×100 PNG, left half red and right half blue.
    private func writePNG(to url: URL) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(try #require(CGColor(colorSpace: space, components: [1, 0, 0, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(try #require(CGColor(colorSpace: space, components: [0, 0, 1, 1])))
        context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try result.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return result
    }

    private func frame(fields: [String: JSONValue]) async throws -> CGImage {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePNG(to: root.appendingPathComponent("photo.png"))
        var project = Project(name: "Blur")
        project["clipFill"] = .bool(false)
        let image = Media(fields: [
            "id": .string("still"), "path": .string("photo.png"), "kind": .string("image"), "fps": project.fps.json,
            "frames": .integer(100_000), "width": .integer(200), "height": .integer(100), "hasAudio": .bool(false),
        ])
        var item = Item(id: "i", media: "still", at: 0, duration: 30)
        for (key, value) in fields { item[key] = value }
        project = try project.applying(.group(label: "Blur", author: .user, ops: [
            .addMedia(image), .insert(track: "v1", item: item),
        ])).project
        let snapshot = try await CompositionBuilder().build(project, root: root)
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: project.fps.time(10)).image
    }

    @Test("Blur mixes the picture across an edge, scaled to the picture's short side")
    func blurs() async throws {
        // Fitted, the 200×100 picture spans the 1080-wide frame: red to x 540, blue after it.
        let sharp = try await frame(fields: [:])
        let edge = try pixel(sharp, x: 525, y: 960)
        #expect(edge[0] > 200 && edge[2] < 30, "\(edge)")
        let soft = try await frame(fields: ["blur": .number(0.1)])
        let mixed = try pixel(soft, x: 525, y: 960)
        #expect(mixed[0] > 60 && mixed[2] > 60, "\(mixed)")
        // Far from the edge the colour stays.
        #expect(try pixel(soft, x: 100, y: 960)[0] > 200)
    }

    @Test("A cropped blur stays opaque to its crop's edge")
    func croppedBlur() async throws {
        let image = try await frame(fields: [
            "blur": .number(0.1), "crop": .object(["top": .number(0.4), "bottom": .number(0.4)]),
        ])
        // The kept middle fifth of the picture (y 906–1014) is fully covered, even 2 px inside its edges.
        #expect(try pixel(image, x: 100, y: 909)[3] == 255)
        #expect(try pixel(image, x: 100, y: 909)[0] > 180)
    }

    @Test("Blur is validated: 0…0.2")
    func validation() throws {
        var project = Project(name: "Blur")
        project = try project.applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(Media(fields: ["id": .string("m"), "path": .string("a.png"), "kind": .string("image"),
                                     "fps": project.fps.json, "frames": .integer(100), "width": .integer(10), "height": .integer(5)])),
            .insert(track: "v1", item: Item(id: "i", media: "m", at: 0, duration: 30)),
        ])).project
        #expect(throws: ProjectError.self) { try project.applying(.setProperties(item: "i", patch: ["blur": .number(0.5)])) }
        project = try project.applying(.setProperties(item: "i", patch: ["blur": .number(0.04)])).project
        #expect(project.tracks.flatMap(\.items).first { $0.id == "i" }?["blur"] == .number(0.04))
    }

    @Test("A crop at a fractional edge is cut at whole pixels, so its blur stays opaque inside")
    func fractionalCropStaysOpaque() throws {
        let fields: [String: JSONValue] = [
            "crop": .object(["top": .number(0.722), "bottom": .number(0.159), "left": .number(0.056), "right": .number(0.05)]),
        ]
        let crop = try #require(SourceCrop(fields: fields, naturalSize: CGSize(width: 360, height: 640), orientation: .identity))
        #expect(crop.rect == CGRect(x: 21, y: 102, width: 321, height: 75), "\(crop.rect)")
        let picture = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 360, height: 640))
        let blurred = BashCutCompositor.blurred(crop.apply(to: picture), soft: 18, x: 0, y: 0)
        var pixel = [UInt8](repeating: 0, count: 4)
        for y in [103.0, 140.0, 176.0] {
            CIContext().render(
                blurred, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 170, y: y, width: 1, height: 1), format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            #expect(pixel[3] == 255, "y \(y): \(pixel)")
        }
    }

    private func rgba(_ image: CIImage, _ x: Double, _ y: Double) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return pixel
    }

    /// A horizontal ramp from black to white, 200×100.
    private var ramp: CIImage {
        CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 200, y: 0),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0), "inputColor1": CIColor(red: 1, green: 1, blue: 1),
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    @Test("pixelate makes square cells of one colour, opaque to the edges")
    func pixelates() {
        let cells = BashCutCompositor.obscured(ramp, properties: ["pixelate": .number(0.1)], side: 100)
        // 10-pixel cells from the picture's corner: x 101 and 109 share a cell, 111 is the next one.
        #expect(rgba(cells, 101, 50) == rgba(cells, 109, 50))
        #expect(rgba(cells, 101, 50) != rgba(cells, 111, 50))
        #expect(rgba(cells, 1, 1)[3] == 255)
    }

    @Test("feather fades the edges and keeps the middle opaque")
    func feathers() {
        let soft = BashCutCompositor.obscured(ramp, properties: ["feather": .number(0.4)], side: 100)
        #expect(rgba(soft, 100, 50)[3] == 255)
        #expect(rgba(soft, 100, 1)[3] < 80, "\(rgba(soft, 100, 1))")
        #expect(rgba(soft, 1, 50)[3] < 80)
    }
}
