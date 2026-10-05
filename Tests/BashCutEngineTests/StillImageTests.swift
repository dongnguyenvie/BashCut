import AVFoundation
import BashCutProject
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import BashCutEngine

struct StillImageTests {
    /// A 200×100 PNG: the left half opaque red, the right half transparent.
    private func writePNG(to url: URL) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 200, height: 100))
        context.setFillColor(try #require(CGColor(colorSpace: space, components: [1, 0, 0, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
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
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            // Draw the image so that pixel (x, y), counted from the top, lands on the 1×1 context.
            context.draw(image, in: CGRect(
                x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return result
    }

    @Test("An image is held for its item's length, fitted, with its transparency over the layers below")
    func render() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let png = root.appendingPathComponent("sticker.png")
        try writePNG(to: png)
        #expect(StillImageMovie.isImage(png))
        #expect(StillImageMovie.pixelSize(of: png) == CGSize(width: 200, height: 100))

        var project = Project(name: "Stills")
        project["clipFill"] = .bool(false)
        let image = Media(fields: [
            "id": .string("still"), "path": .string("sticker.png"), "kind": .string("image"),
            "fps": project.fps.json, "frames": .integer(Int(Media.imageMaximumSeconds * project.fps.value)),
            "width": .integer(200), "height": .integer(100), "hasAudio": .bool(false),
        ])
        #expect(image.placementFrames(in: project.fps) == 90)
        let item = Item(id: "i", media: "still", at: 0, duration: 300)
        project = try project.applying(.group(label: "Still", author: .user, ops: [
            .addMedia(image), .insert(track: "v1", item: item),
        ])).project

        let snapshot = try await CompositionBuilder().build(project, root: root)
        let movie = root.appendingPathComponent(".bashcut/cache/stills/still.mov")
        #expect(FileManager.default.fileExists(atPath: movie.path))
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for frame in [0, 150, 299] {
            let picture = try await generator.image(at: project.fps.time(frame)).image
            // 1080 wide, so the image is 1080×540 in the middle of the 1920-high frame.
            let red = try pixel(picture, x: 270, y: 960)
            #expect(red[0] > 200 && red[1] < 40 && red[2] < 40, "frame \(frame): \(red)")
            let clear = try pixel(picture, x: 810, y: 960)
            #expect(clear[0] < 30 && clear[1] < 30 && clear[2] < 30, "frame \(frame): \(clear)")
            let bar = try pixel(picture, x: 540, y: 200)
            #expect(bar[0] < 30, "frame \(frame): \(bar)")
        }
    }

    @Test("The still movie is reused until the image changes")
    func reuse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let png = root.appendingPathComponent("a.png")
        try writePNG(to: png)
        let media = Media(fields: ["id": .string("m"), "path": .string("a.png"), "kind": .string("image")])
        let first = try await StillImageMovie.movie(for: media, image: png, root: root)
        func modified() throws -> Date? {
            try FileManager.default.attributesOfItem(atPath: first.path)[.modificationDate] as? Date
        }
        let made = try modified()
        _ = try await StillImageMovie.movie(for: media, image: png, root: root)
        #expect(try modified() == made)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: png.path)
        _ = try await StillImageMovie.movie(for: media, image: png, root: root)
        #expect(try modified() != made)
        let asset = AVURLAsset(url: first)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 200, height: 100))
    }

    @Test("Keyframes move an image frame by frame (Ken Burns) and fade text")
    func keyframes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePNG(to: root.appendingPathComponent("red.png"))
        var project = Project(name: "Keys")
        project["clipFill"] = .bool(false)
        let image = Media(fields: [
            "id": .string("still"), "path": .string("red.png"), "kind": .string("image"),
            "fps": project.fps.json, "frames": .integer(100_000), "hasAudio": .bool(false),
        ])
        var item = Item(id: "i", media: "still", at: 0, duration: 30)
        // The red half is 540 px wide at zoom 1 (left of centre); at zoom 0.2 it is 108 px, near the centre.
        item["keyframes"] = ItemMotion(keys: ["zoom": [.init(frame: 0, value: 0.2, ease: .linear),
                                                       .init(frame: 29, value: 1)]]).json
        var title = Item(id: "t", at: 0, duration: 30)
        title["text"] = .string("FADE")
        title["textPreset"] = .string("hook-title")
        title["keyframes"] = ItemMotion(keys: ["opacity": [.init(frame: 0, value: 0, ease: .linear),
                                                          .init(frame: 29, value: 1)]]).json
        project = try project.applying(.group(label: "Keys", author: .user, ops: [
            .addMedia(image), .insert(track: "v1", item: item), .insert(track: "t1", item: title),
        ])).project
        let snapshot = try await CompositionBuilder().build(project, root: root)
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let first = try await generator.image(at: project.fps.time(0)).image
        let last = try await generator.image(at: project.fps.time(29)).image
        // 100 px left of centre: outside the small square at the start, inside the red half at the end.
        #expect(try pixel(first, x: 300, y: 960)[0] < 30)
        #expect(try pixel(last, x: 300, y: 960)[0] > 200)
        #expect(try pixel(first, x: 500, y: 960)[0] > 200)
        // Hook titles are white over the picture: nothing at frame 0, white at the end. Find a bright pixel in
        // the title band of the last frame and check the same pixel is dark in the first.
        let band = stride(from: 300, through: 780, by: 4).flatMap { x in stride(from: 760, through: 900, by: 4).map { (x, $0) } }
        let lit = try band.first { try pixel(last, x: $0.0, y: $0.1).allSatisfy { $0 > 170 } }
        let point = try #require(lit)
        #expect(try pixel(first, x: point.0, y: point.1)[1] < 60)
    }
}
