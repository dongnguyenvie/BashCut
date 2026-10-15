import AVFoundation
import BashCutProject
import BashCutTestSupport
import CoreImage
import Foundation
import Testing
@testable import BashCutEngine

/// Transition kinds as an item's own entrance and exit (`enter`, `exit`), drawn inside the item's frame.
struct ItemTransitionRenderTests {
    private let context = CIContext()

    /// RGBA bytes of `image` over `rect`, the top row first.
    private func bytes(_ image: CIImage, in rect: CGRect) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Int(rect.width) * Int(rect.height) * 4)
        context.render(image, toBitmap: &bytes, rowBytes: Int(rect.width) * 4, bounds: rect, format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        return bytes
    }

    private func alpha(_ image: CIImage, x: CGFloat, y: CGFloat) -> Int {
        Int(bytes(image, in: CGRect(x: x, y: y, width: 1, height: 1))[3])
    }

    /// A caption on `size` with `enter` and `exit` (each 12 frames) over frames 0–60 at 30 fps.
    private func caption(enter: String?, exit: String?) -> Item {
        var item = Item(id: "cap", at: 0, duration: 60)
        item["text"] = .string("HELLO WORLD")
        item["textStyle"] = .object(["size": .number(0.2), "positionY": .number(0.4)])
        if let enter { item["enter"] = ItemTransition(kind: enter, duration: 12).json }
        if let exit { item["exit"] = ItemTransition(kind: exit, duration: 12).json }
        return item
    }

    @Test("An iris opens inside the text box and a wipe takes the text away from the right, with the keyframes")
    func overlay() throws {
        // A white box stands in for the text raster.
        let box = CGRect(x: 100, y: 60, width: 120, height: 60)
        let overlay = CIImage(color: .white).cropped(to: box)
        var item = Item(id: "t", at: 0, duration: 60)
        item["text"] = .string("Box")
        item["enter"] = ItemTransition(kind: "iris", duration: 12).json
        item["exit"] = ItemTransition(kind: "wipe", duration: 12).json
        let layer = TextLayer(item: item, fps: 30)
        let size = CGSize(width: 320, height: 180)
        func at(_ frame: Double) -> CIImage {
            BashCutCompositor.animated(overlay, text: layer, size: size, time: frame / 30)
        }
        // Frame 0: the circle has no size yet; half way it covers the box's centre, not its corners.
        #expect(alpha(at(0), x: 160, y: 90) == 0)
        #expect(alpha(at(6), x: 160, y: 90) == 255 && alpha(at(6), x: 102, y: 62) == 0)
        // The circle is the box's own: at the end of the entrance the corners show.
        #expect(alpha(at(12), x: 102, y: 62) == 255 && alpha(at(30), x: 218, y: 118) == 255)
        // Half way through the exit (frames 48–60) the left half shows and the right half is gone.
        #expect(alpha(at(54), x: 110, y: 90) == 255 && alpha(at(54), x: 210, y: 90) == 0)
        // A whip out moves up by the box's height and fades.
        item["exit"] = ItemTransition(kind: "whip-up", duration: 12).json
        let whip = BashCutCompositor.animated(overlay, text: TextLayer(item: item, fps: 30), size: size, time: 54.0 / 30)
        #expect(abs(whip.extent.minY - 90) < 1)
        let faded = alpha(whip, x: 160, y: 130)
        #expect(faded > 60 && faded < 200, "\(faded)")

        // With a pop-in keyframe on top the entrance still plays inside the box, then the zoom moves it.
        item["keyframes"] = .object(["zoom": .array([
            .object(["frame": .integer(0), "value": .number(2)]), .object(["frame": .integer(12), "value": .number(1)]),
        ])])
        let motion = try #require(item.pictureMotion)
        let keyed = TextLayer(item: item, motion: LayerMotion(motion: motion, item: item, fps: 30), fps: 30)
        let both = BashCutCompositor.animated(overlay, text: keyed, size: size, time: 6.0 / 30)
        // The opening circle, about 1.5 times as large around the text's anchor.
        let alone = at(6).extent
        #expect(both.extent.width > alone.width * 1.3 && abs(both.extent.midX - alone.midX) < 2, "\(both.extent) \(alone)")
    }

    @Test("A caption comes in with an iris and leaves with a wipe; preview, export and the exported file agree")
    func caption() async throws {
        let root = try TestFixtures.temporaryDirectory("item-transitions")
        defer { try? FileManager.default.removeItem(at: root) }
        let item = caption(enter: "iris", exit: "wipe")
        let project = try Project(name: "In and out").applying(.group(label: "Fixture", author: .user, ops: [
            .setFormat(width: 320, height: 180), .insert(track: "t1", item: item),
        ])).project
        let size = CGSize(width: 320, height: 180)
        let box = try #require(TextRenderer.raster(item, size: size)?.bounds)
        let preview = try await CompositionBuilder().build(project, root: root, purpose: .preview)
        let export = try await CompositionBuilder().build(project, root: root, purpose: .export)
        let file = root.appendingPathComponent("in-out.mp4")
        _ = try await Exporter().export(export, to: file, settings: ExportSettings(preset: .quickDraft))

        /// Lit pixels of the left and right half of the text box at `frame`.
        func lit(_ image: CGImage, frame: Int) -> (left: Int, right: Int) {
            let picture = CIImage(cgImage: image)
            let pixels = bytes(picture, in: box.integral)
            let width = Int(box.integral.width)
            var left = 0, right = 0
            for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index] > 128 {
                if (index / 4) % width < width / 2 { left += 1 } else { right += 1 }
            }
            return (left, right)
        }
        func frames(_ asset: AVAsset, composition: AVVideoComposition?) async throws -> [Int: CGImage] {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.videoComposition = composition
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            var result: [Int: CGImage] = [:]
            for frame in [1, 30, 54] { result[frame] = try await generator.image(at: project.fps.time(frame)).image }
            return result
        }
        let previewed = try await frames(preview.composition, composition: preview.videoComposition)
        let exported = try await frames(export.composition, composition: export.videoComposition)
        let encoded = try await frames(AVURLAsset(url: file), composition: nil)
        for frame in [1, 30, 54] {
            let a = try #require(previewed[frame]), b = try #require(exported[frame])
            #expect(CIImage(cgImage: a).extent == CIImage(cgImage: b).extent)
            #expect(bytes(CIImage(cgImage: a), in: box.integral) == bytes(CIImage(cgImage: b), in: box.integral),
                    "preview and export differ at frame \(frame)")
        }
        for source in [previewed, encoded] {
            let full = lit(try #require(source[30]), frame: 30)
            let opening = lit(try #require(source[1]), frame: 1)
            let leaving = lit(try #require(source[54]), frame: 54)
            #expect(full.left > 50 && full.right > 50, "\(full)")
            // One frame into a 12-frame iris only the middle of the box shows.
            #expect(opening.left + opening.right < (full.left + full.right) / 4, "\(opening) of \(full)")
            // Half way out of the wipe the right half has gone and the left half stays.
            #expect(leaving.right < full.right / 10 && leaving.left > full.left / 2, "\(leaving) of \(full)")
        }
    }

    @Test("A caption that comes in with an iris leaves with a whip up, rising and fading, in the exported file")
    func whipUp() async throws {
        let root = try TestFixtures.temporaryDirectory("item-transition-whip")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Project(name: "Whip").applying(.group(label: "Fixture", author: .user, ops: [
            .setFormat(width: 320, height: 180), .insert(track: "t1", item: caption(enter: "iris", exit: "whip-up")),
        ])).project
        let file = root.appendingPathComponent("whip.mp4")
        _ = try await Exporter().export(
            try await CompositionBuilder().build(project, root: root), to: file, settings: ExportSettings(preset: .quickDraft))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        /// The mean row (from the top) and the brightest level of the lit pixels at `frame`.
        func lit(_ frame: Int) async throws -> (y: Double, peak: Int) {
            let image = CIImage(cgImage: try await generator.image(at: project.fps.time(frame)).image)
            let pixels = bytes(image, in: image.extent)
            let width = Int(image.extent.width)
            var sum = 0.0, count = 0.0, peak = 0
            for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index] > 60 {
                sum += Double(index / 4 / width)
                count += 1
                peak = max(peak, Int(pixels[index]))
            }
            return (count == 0 ? 0 : sum / count, peak)
        }
        let full = try await lit(30), leaving = try await lit(54)
        #expect(leaving.y < full.y - 10, "\(leaving) against \(full)")
        #expect(leaving.peak < full.peak - 40, "\(leaving) against \(full)")
    }

    @Test("An overlay clip's entrance plays inside its placed picture, not the canvas")
    func overlayClip() async throws {
        let root = try TestFixtures.temporaryDirectory("item-transition-clip")
        defer { try? FileManager.default.removeItem(at: root) }
        try await PictureSamplerTests.writeMovie(to: root.appendingPathComponent("white.mov"), frames: 60, flat: true) { _ in 255 }
        var overlay = Item(id: "ov", media: "white", at: 0, duration: 60)
        overlay["transform"] = .object(["zoom": .number(0.5)])
        overlay["enter"] = ItemTransition(kind: "iris", duration: 12).json
        var project = Project(name: "Overlay", fps: FrameRate(30, 1))
        project["clipFill"] = .bool(false)
        project = try project.applying(.group(label: "Fixture", author: .user, ops: [
            .setFormat(width: 320, height: 180), .addMedia(PictureSamplerTests.media("white", "white.mov", frames: 60)),
            .insert(track: "v2", item: overlay),
        ])).project
        let snapshot = try await CompositionBuilder().build(project, root: root, purpose: .preview)
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // The picture is 160×90 in the middle (80…240, 45…135).
        let opening = CIImage(cgImage: try await generator.image(at: project.fps.time(6)).image)
        func red(_ image: CIImage, _ x: CGFloat, _ y: CGFloat) -> Int { Int(bytes(image, in: CGRect(x: x, y: y, width: 1, height: 1))[0]) }
        #expect(red(opening, 160, 90) > 200)
        // A canvas-sized iris at 0.5 would reach the picture's corner; the picture's own does not.
        #expect(red(opening, 84, 49) < 30)
        let open = CIImage(cgImage: try await generator.image(at: project.fps.time(20)).image)
        #expect(red(open, 84, 49) > 200 && red(open, 60, 90) < 30)
    }
}
