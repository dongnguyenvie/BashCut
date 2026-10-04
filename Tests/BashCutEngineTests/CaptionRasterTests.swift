import BashCutProject
import CoreImage
import Foundation
import Testing
@testable import BashCutEngine

struct CaptionRasterTests {
    private static let presets = ["bold-outline", "cinematic-serif", "keyword-sticker", "place-card", "hook-title", "chapter-card"]

    @Test("Cropped captions retain full-canvas pixels including decorations, outlines and shadows", arguments: presets)
    func parity(preset: String) throws {
        let context = CIContext()
        for size in [CGSize(width: 320, height: 180), CGSize(width: 540, height: 960)] {
            for position in [0.02, 0.5, 0.96] {
                var item = Item(id: "caption", at: 0, duration: 30)
                item["text"] = .string("Ăn ngon · ă â đ ê ô ơ ư ỹ\nXin chào 👋")
                item["textPreset"] = .string(preset)
                item["textStyle"] = .object(["positionY": .number(position), "strokeWidth": .number(12)])
                let cropped = try #require(TextRenderer.raster(item, size: size))
                let full = try #require(TextRenderer.raster(item, size: size, fullCanvas: true))
                let first = pixels(cropped.image, size: size, context: context)
                let second = pixels(full.image, size: size, context: context)
                // Integer-translated CoreText contexts can differ by one quantization level at antialiased edges.
                // Compare every channel, including alpha, so clipped accents/shadows and shifted glyphs still fail.
                let maximum = zip(first, second).map { abs(Int($0) - Int($1)) }.max() ?? 0
                #expect(maximum <= 1)
            }
        }
    }

    @Test("Animated word variants keep their canvas position after cropping")
    func animationAndWords() throws {
        let size = CGSize(width: 540, height: 960), context = CIContext()
        var item = Item(id: "words", at: 0, duration: 30)
        item["text"] = .string("Xin chào Việt Nam")
        item["textPreset"] = .string("hook-title")
        item["wordStyle"] = .string("highlight")
        item["keyframes"] = ItemMotion(keys: [
            "zoom": [.init(frame: 0, value: 1), .init(frame: 29, value: 1.4)],
            "rotation": [.init(frame: 0, value: 0), .init(frame: 29, value: 20)]
        ]).json
        let motion = try #require(item.pictureMotion)
        let layer = TextLayer(item: item, motion: LayerMotion(motion: motion, item: item, fps: 30), fps: 30)
        for spoken in [0, 2] {
            let crop = try #require(TextRenderer.raster(item, size: size, spoken: spoken))
            let full = try #require(TextRenderer.raster(item, size: size, spoken: spoken, fullCanvas: true))
            let actual = BashCutCompositor.animated(crop.image, text: layer, size: size, time: 0.5)
            let expected = BashCutCompositor.animated(full.image, text: layer, size: size, time: 0.5)
            let first = pixels(actual, size: size, context: context), second = pixels(expected, size: size, context: context)
            #expect(zip(first, second).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
        }
    }

    @Test("4K captions allocate a small raster and reuse the same positioned CIImage")
    func memoryAndReuse() throws {
        let size = CGSize(width: 3840, height: 2160)
        var item = Item(id: "memory", at: 0, duration: 30)
        item["text"] = .string("Xin chào")
        let raster = try #require(TextRenderer.raster(item, size: size))
        #expect(raster.bytes < Int(size.width * size.height * 4) / 10)
        #expect(TextRenderer.overlay(item, size: size) === raster.image)
        #expect(TextRenderer.overlay(item, size: size) === raster.image)
        print("CAPTION_RASTER 4K_bytes=\(raster.bytes) full_canvas_bytes=\(Int(size.width * size.height * 4))")
    }

    private func pixels(_ image: CIImage, size: CGSize, context: CIContext) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: Int(size.width * size.height * 4))
        context.render(image, toBitmap: &result, rowBytes: Int(size.width * 4), bounds: CGRect(origin: .zero, size: size),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return result
    }
}
