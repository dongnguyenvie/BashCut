import BashCutProject
import CoreGraphics
import Foundation
import Testing

@testable import BashCutEngine

struct WordCaptionTests {
    private func caption(_ style: String?) -> Item {
        var item = Item(id: "c", at: 30, duration: 60)
        item["text"] = .string("Xin chào các bạn")
        item["wordStyle"] = style.map(JSONValue.string)
        item["words"] = .array(["Xin", "chào", "các", "bạn"].enumerated().map { index, word in
            .object(["text": .string(word), "at": .integer(index * 15), "dur": .integer(12)])
        })
        return item
    }

    /// Opaque pixels and pixels in the highlight yellow (#FFD400).
    private func census(_ image: CGImage) throws -> (opaque: Int, yellow: Int) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var opaque = 0, yellow = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) where bytes[offset + 3] > 200 {
            opaque += 1
            if bytes[offset] > 230, bytes[offset + 1] > 180, bytes[offset + 1] < 235, bytes[offset + 2] < 60 { yellow += 1 }
        }
        return (opaque, yellow)
    }

    @Test("The spoken word follows composition time")
    func spokenWord() {
        let layer = TextLayer(item: caption("highlight"), fps: 30)
        #expect(layer.spokenWord(at: 0.5) == nil)  // frame 15, before the item
        #expect(layer.spokenWord(at: 1.0) == 0)  // frame 30, the item's first frame
        #expect(layer.spokenWord(at: 2.0) == 2)  // item frame 30
        #expect(TextLayer(item: caption(nil), fps: 30).wordStarts == nil)
    }

    @Test("Highlight colours one word, karaoke the words said so far, reveal hides the rest")
    func styles() throws {
        let size = CGSize(width: 540, height: 960)
        let plain = try census(try #require(TextRenderer.image(caption(nil), size: size)))
        #expect(plain.opaque > 500 && plain.yellow == 0)
        let first = try census(try #require(TextRenderer.image(caption("highlight"), size: size, spoken: 0)))
        let last = try census(try #require(TextRenderer.image(caption("karaoke"), size: size, spoken: 3)))
        #expect(first.yellow > 20)
        #expect(last.yellow > first.yellow * 2)
        let hidden = try census(try #require(TextRenderer.image(caption("reveal"), size: size, spoken: nil)))
        #expect(hidden.opaque == 0)
        let half = try census(try #require(TextRenderer.image(caption("reveal"), size: size, spoken: 1)))
        #expect(half.opaque > 0 && half.opaque < plain.opaque)
    }
}
