import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import BashCutEngine

struct TextSizingTests {
    @Test("Text size follows the short side, so presets match in portrait and landscape")
    func shortSide() {
        let portrait = TextRenderer.fontSize(0.082, canvas: CGSize(width: 1080, height: 1920))
        let landscape = TextRenderer.fontSize(0.082, canvas: CGSize(width: 1920, height: 1080))
        #expect(abs(portrait - 88.56) < 0.01)
        #expect(portrait == landscape)
    }

    @Test("A line wider than the frame shrinks to fit; a short one keeps its size")
    func fitsWidth() {
        let long = TextRenderer.fittedFont(
            "Arial-BoldMT", size: 160, lines: ["MỘT NGÀY Ở BUÔN LÀNG", "x"], maximumWidth: 900)
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): long]
        let width = CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(NSAttributedString(string: "MỘT NGÀY Ở BUÔN LÀNG", attributes: attributes)),
            nil, nil, nil)
        #expect(CTFontGetSize(long) < 160)
        #expect(width <= 900.5)
        let short = TextRenderer.fittedFont("Arial-BoldMT", size: 60, lines: ["Hi"], maximumWidth: 900)
        #expect(CTFontGetSize(short) == 60)
    }
}
