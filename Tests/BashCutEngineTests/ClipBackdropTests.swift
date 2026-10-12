import AVFoundation
import BashCutProject
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import BashCutEngine

/// The item backdrop (P3-J7): a fitted picture's empty frame filled with a blurred copy of itself or a colour.
struct ClipBackdropTests {
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

    private func frame(backdrop: JSONValue?) async throws -> CGImage {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePNG(to: root.appendingPathComponent("photo.png"))
        var project = Project(name: "Backdrop")
        project["clipFill"] = .bool(false)
        let image = Media(fields: [
            "id": .string("still"), "path": .string("photo.png"), "kind": .string("image"), "fps": project.fps.json,
            "frames": .integer(100_000), "width": .integer(200), "height": .integer(100), "hasAudio": .bool(false),
        ])
        var item = Item(id: "i", media: "still", at: 0, duration: 30)
        if let backdrop { item["backdrop"] = backdrop }
        project = try project.applying(.group(label: "Backdrop", author: .user, ops: [
            .addMedia(image), .insert(track: "v1", item: item),
        ])).project
        let snapshot = try await CompositionBuilder().build(project, root: root)
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: project.fps.time(10)).image
    }

    @Test("Without a backdrop the bars are black; a colour fills them; the picture stays on top")
    func color() async throws {
        let plain = try await frame(backdrop: nil)
        #expect(try pixel(plain, x: 540, y: 200).prefix(3).allSatisfy { $0 < 20 })
        let green = try await frame(backdrop: .object(["kind": .string("color"), "color": .string("#00FF00")]))
        let bar = try pixel(green, x: 540, y: 200)
        #expect(bar[1] > 200 && bar[0] < 40 && bar[2] < 40, "\(bar)")
        // The fitted picture (y 690–1230): red on the left, blue on the right.
        #expect(try pixel(green, x: 270, y: 960)[0] > 200)
        #expect(try pixel(green, x: 810, y: 960)[2] > 200)
    }

    @Test("Blur fills the bars with the picture itself, filled and blurred, and dim darkens it")
    func blur() async throws {
        let blurred = try await frame(backdrop: .object(["kind": .string("blur"), "blur": .number(0.02)]))
        // Filled, the 200×100 picture is 3840 wide: the frame's left part is red, its right part blue.
        let left = try pixel(blurred, x: 100, y: 200), right = try pixel(blurred, x: 980, y: 200)
        #expect(left[0] > 180 && left[2] < 60, "\(left)")
        #expect(right[2] > 180 && right[0] < 60, "\(right)")
        let dimmed = try await frame(backdrop: .object(["kind": .string("blur"), "blur": .number(0.02), "dim": .number(0.5)]))
        let half = try pixel(dimmed, x: 100, y: 200)
        // Half the light (in linear light: about 188 of 255 in sRGB).
        #expect(half[0] > 120 && Int(half[0]) < Int(left[0]) - 30, "\(half) against \(left)")
        #expect(try pixel(dimmed, x: 270, y: 960)[0] > 200)
    }

    @Test("A backdrop is validated and removable with null")
    func validation() throws {
        var project = Project(name: "Backdrop")
        project = try project.applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(Media(fields: ["id": .string("m"), "path": .string("a.png"), "kind": .string("image"),
                                     "fps": project.fps.json, "frames": .integer(100), "width": .integer(10), "height": .integer(5)])),
            .insert(track: "v1", item: Item(id: "i", media: "m", at: 0, duration: 30)),
        ])).project
        #expect(throws: ProjectError.self) {
            try project.applying(.setProperties(item: "i", patch: ["backdrop": .object(["kind": .string("glow")])]))
        }
        #expect(throws: ProjectError.self) {
            try project.applying(.setProperties(item: "i", patch: ["backdrop": .object(["kind": .string("blur"), "blur": .number(2)])]))
        }
        project = try project.applying(.setProperties(item: "i", patch: ["backdrop": .object(["kind": .string("blur")])])).project
        project = try project.applying(.setProperties(item: "i", patch: ["backdrop": .null])).project
        #expect(project.tracks.flatMap(\.items).first { $0.id == "i" }?["backdrop"] == nil)
    }
}
