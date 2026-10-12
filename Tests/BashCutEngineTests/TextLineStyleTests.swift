import BashCutProject
import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import BashCutEngine

/// Two fonts in one title (`textStyle.lines`, text phase 2).
struct TextLineStyleTests {
    private func title(_ lines: JSONValue?) -> Item {
        var item = Item(id: "t", at: 0, duration: 30)
        item["text"] = .string("BIG NEWS\nsmall print")
        var style: [String: JSONValue] = ["font": .string("Arial-BoldMT")]
        if let lines { style["lines"] = lines }
        item["textStyle"] = .object(style)
        return item
    }

    @Test("A line's own font and scale draw it; the other lines keep the block's font and size")
    func lineFonts() throws {
        let canvas = CGSize(width: 1080, height: 1920)
        let plain = title(nil)
        let mixed = title(.array([.null, .object(["font": .string("TimesNewRomanPSMT"), "scale": .number(0.5)])]))
        let before = TextRenderer.lineFonts(CaptionStyle(plain), lines: CaptionStyle(plain).lines(plain), canvas: canvas)
        let after = TextRenderer.lineFonts(CaptionStyle(mixed), lines: CaptionStyle(mixed).lines(mixed), canvas: canvas)
        #expect(CTFontCopyPostScriptName(after.lines[0]) as String == "Arial-BoldMT")
        #expect(CTFontCopyPostScriptName(after.lines[1]) as String == "TimesNewRomanPSMT")
        #expect(CTFontGetSize(after.lines[0]) == CTFontGetSize(before.lines[0]))
        #expect(abs(CTFontGetSize(after.lines[1]) - CTFontGetSize(after.base) * 0.5) < 0.01)
        // The smaller second line makes the block shorter than with one size.
        let tall = try #require(TextRenderer.layout(plain, size: canvas))
        let short = try #require(TextRenderer.layout(mixed, size: canvas))
        #expect(short.maxY - short.minY < tall.maxY - tall.minY)
        #expect(TextRenderer.cacheKey(plain) != TextRenderer.cacheKey(mixed))
        #expect(TextRenderer.image(mixed, size: canvas) != nil)
    }

    @Test("A line's own fill colours it")
    func lineFill() throws {
        var item = title(.array([.object(["fill": .string("#FF0000")])]))
        item["textPreset"] = .string("hook-title")
        item["textStyle"] = .object((item["textStyle"]?.object ?? [:]).merging(["emphasis": .bool(false)]) { $1 })
        #expect(CaptionStyle(item).line(0)?["fill"] == .string("#FF0000"))
        #expect(CaptionStyle(item).line(1) == nil)
        #expect(CaptionStyle(item).fontName(line: 0) == "Arial-BoldMT")
    }
}
