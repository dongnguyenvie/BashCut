import BashCutProject
import CoreGraphics
import Foundation
import Testing
@testable import BashCutEngine

/// Titles on cover stills (#443).
struct CoverTitleTests {
    private func grey(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test("The title is drawn on the cover, sized by each cover's short side and fitted to its width")
    func title() throws {
        var item = Item(at: 0, duration: 1)
        item["text"] = .string("48 GIỜ Ở ĐÀ LẠT")
        item["textPreset"] = .string("hook-title")
        let vertical = try #require(CoverTitle.draw(item, over: try grey(width: 540, height: 960)))
        let wide = try #require(CoverTitle.draw(item, over: try grey(width: 960, height: 540)))
        #expect(vertical.image.width == 540 && vertical.image.height == 960)
        for box in [vertical.box, wide.box] {
            #expect(box.minX >= 0 && box.maxX <= 1 && box.minY >= 0 && box.maxY <= 1 && box.width > 0.1)
        }
        // The size follows the short side (540 px on both); a narrow cover may only shrink it to fit.
        #expect(vertical.box.height * 960 <= wide.box.height * 540 + 2)
        // Pixels in the box changed; the corners kept the picture.
        let pixels = try #require(vertical.image.dataProvider?.data as Data?)
        let row = vertical.image.bytesPerRow
        let changed = stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0] != pixels[0] }
        #expect(changed && pixels[0] == pixels[row * 959 + 539 * 4])
        // Blank text draws nothing.
        item["text"] = .string("  ")
        #expect(CoverTitle.draw(item, over: try grey(width: 100, height: 100)) == nil)
    }

    @Test("A cover title's size is a fraction of the short side; the cover default reads at phone size")
    func titleSize() throws {
        var item = Item(at: 0, duration: 1)
        item["text"] = .string("ĐÀ LẠT")
        let caption = try #require(CoverTitle.draw(item, over: try grey(width: 540, height: 960)))
        let cover = try #require(CoverTitle.draw(CoverTitle.sized(item, nil), over: try grey(width: 540, height: 960)))
        #expect(cover.box.height > caption.box.height * 1.8)
        #expect(cover.box.height * 960 >= 0.06 * 540, "the drawn text is at least half the font size tall")
    }
}
