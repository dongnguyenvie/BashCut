import BashCutProject
import CoreGraphics
import Foundation
import Testing
@testable import BashCutEngine

/// The rendered text layout for the review (#465) matches the pixels `TextRenderer` draws.
struct TextLayoutTests {
    @Test("Layout bounds match the drawn pixels within a few pixels on long Vietnamese lines",
          arguments: ["bold-outline", "cinematic-serif", "keyword-sticker", "place-card", "chapter-card"])
    func matchesPixels(preset: String) throws {
        for size in [CGSize(width: 1080, height: 1920), CGSize(width: 1920, height: 1080)] {
            var item = Item(id: "layout", at: 0, duration: 30)
            item["text"] = .string("Hôm nay mình đi ăn phở bò ở Hà Nội, quán này ngon nhất phố cổ\nGiá chỉ 45.000 đồng")
            item["textPreset"] = .string(preset)
            item["textStyle"] = .object(["positionY": .number(0.3)])
            let layout = try #require(TextPresetStyle.layout(item, size: size))
            let raster = try #require(TextRenderer.raster(item, size: size, fullCanvas: true))
            let drawn = try #require(inkBounds(raster.bitmap))
            #expect(layout.lines == 2)
            #expect(abs(layout.minX - drawn.minX) <= 4)
            #expect(abs(layout.maxX - drawn.maxX) <= 4)
            #expect(abs(layout.minY - drawn.minY) <= 4)
            #expect(abs(layout.maxY - drawn.maxY) <= 4)
        }
    }

    @Test("Open textStyle fields (align, positionX, tracking, line height, uppercase, plate) lay out as drawn")
    func openStyle() throws {
        let size = CGSize(width: 1080, height: 1920)
        var item = Item(id: "open", at: 0, duration: 30)
        item["text"] = .string("Phở bò\nHà Nội")
        item["textPreset"] = .string("my-own-look")
        item["textStyle"] = .object([
            "align": .string("right"), "positionX": .number(0.9), "positionY": .number(0.3), "tracking": .number(0.05),
            "lineHeight": .number(1.6), "uppercase": .bool(true),
            "background": .object(["color": .string("#101010"), "opacity": .number(0.9), "radius": .number(0.3)]),
        ])
        let layout = try #require(TextPresetStyle.layout(item, size: size))
        let raster = try #require(TextRenderer.raster(item, size: size, fullCanvas: true))
        let drawn = try #require(inkBounds(raster.bitmap))
        #expect(abs(layout.maxX - drawn.maxX) <= 4 && abs(layout.minX - drawn.minX) <= 4)
        #expect(abs(layout.minY - drawn.minY) <= 4 && abs(layout.maxY - drawn.maxY) <= 4)
        #expect(layout.maxX > size.width * 0.9 - 2 && layout.maxX < size.width * 0.95)
    }

    @Test("Accent bars sit beside the block, replace the preset's bars, and the layout includes them (C1)")
    func accentBars() throws {
        let size = CGSize(width: 1920, height: 1080)
        var item = Item(id: "bars", at: 0, duration: 30)
        item["text"] = .string("Chapter one")
        item["textPreset"] = .string("place-card")
        let plain = try #require(TextPresetStyle.layout(item, size: size))
        item["textStyle"] = .object(["accentBars": .array([
            .object(["side": .string("left"), "thickness": .number(0.2), "gap": .number(0.5), "color": .string("#FF0000")]),
            .object(["side": .string("bottom"), "thickness": .number(0.1), "gap": .number(1)]),
        ])])
        let layout = try #require(TextPresetStyle.layout(item, size: size))
        let raster = try #require(TextRenderer.raster(item, size: size, fullCanvas: true))
        let drawn = try #require(inkBounds(raster.bitmap))
        #expect(abs(layout.minX - drawn.minX) <= 4 && abs(layout.minY - drawn.minY) <= 4)
        #expect(abs(layout.maxX - drawn.maxX) <= 4 && abs(layout.maxY - drawn.maxY) <= 4)
        // The place card's plate is gone; the bars reach below and left of the text.
        #expect(layout.minY < plain.minY && layout.points > 0)
        item["textStyle"] = .object(["accentBars": .array([])])
        let bare = try #require(TextPresetStyle.layout(item, size: size))
        #expect(bare.maxX - bare.minX < plain.maxX - plain.minX)
    }

    @Test("Empty text has no layout")
    func empty() {
        var item = Item(id: "empty", at: 0, duration: 30)
        item["text"] = .string("  ")
        #expect(TextPresetStyle.layout(item, size: CGSize(width: 1080, height: 1920)) == nil)
    }

    /// Bounds of the pixels with visible alpha, with y up from the bottom like the layout.
    private func inkBounds(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, maxX = -1, minRow = height, maxRow = -1
        for row in 0..<height {
            for column in 0..<width where pixels[(row * width + column) * 4 + 3] > 8 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
            }
        }
        guard maxX >= 0 else { return nil }
        // Memory row 0 is the top of the image.
        return CGRect(x: minX, y: height - maxRow - 1, width: maxX - minX + 1, height: maxRow - minRow + 1)
    }
}
