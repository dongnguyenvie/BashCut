import BashCutProject
import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import BashCutEngine

/// Stacked lines never draw into each other, whatever the preset's line height: uppercase Vietnamese marks (the dot
/// below "Ự", the circumflex and tone of "Ế") and a larger emphasis line get the room their ink needs.
struct TextLineInkTests {
    private static let title = "AI DỰNG HẾT\nTRÊN TIMELINE"

    @Test("Hook-title and chapter-card lines keep their ink apart, with and without an emphasis line",
          arguments: [
            ("hook-title", nil),
            ("hook-title", ["emphasis": JSONValue.bool(false)]),
            ("hook-title", ["emphasis": .object(["line": .number(0)])]),
            ("hook-title", ["emphasis": .object(["line": .number(1), "plate": .object(["color": .string("#E11D48")])])]),
            ("hook-title", ["background": .object(["color": .string("#000000"), "padding": .number(0.3)])]),
            ("chapter-card", nil),
          ] as [(String, [String: JSONValue]?)])
    func linesDoNotTouch(preset: String, style: [String: JSONValue]?) throws {
        for size in [CGSize(width: 1080, height: 1920), CGSize(width: 1920, height: 1080)] {
            var item = Item(id: "ink", at: 0, duration: 30)
            item["text"] = .string(Self.title)
            item["textPreset"] = .string(preset)
            if let style { item["textStyle"] = .object(style) }
            let look = CaptionStyle(item)
            let texts = look.lines(item)
            let (base, fonts) = TextRenderer.lineFonts(look, lines: texts, canvas: size)
            let lines = TextRenderer.stack(
                look, texts: TextRenderer.plainTexts(look, lines: texts, fonts: fonts), fonts: fonts, canvas: size)
            let ink = try lines.map { try #require(drawnInk($0, size: size)) }
            #expect(ink.count == 2)
            // Lines run bottom-up: the top line's lowest ink stays above the bottom line's highest.
            #expect(!ink[0].intersects(ink[1]), "\(preset) \(size): \(ink[1]) touches \(ink[0])")
            #expect(ink[1].minY - ink[0].maxY >= CTFontGetSize(fonts[0]) * 0.03)
            let height = CTFontGetSize(base) * look.lineSpacing
            let decorations = TextRenderer.decorations(look, lines: lines, lineHeight: height, canvas: size)
            // The plate behind the bottom (emphasis) line stays clear of the top line's ink.
            if look.emphasis(lineCount: 2)?.plate != nil, let plate = decorations.last {
                #expect(!plate.rect.intersects(ink[1]), "plate \(plate.rect) covers \(ink[1])")
            }
            // A block background covers every mark of both lines.
            if look.background != nil, let background = decorations.first {
                #expect(background.rect.contains(ink[0].union(ink[1])), "\(background.rect) misses ink")
            }
        }
    }

    @Test("Lines whose ink has room keep the preset's tight line height")
    func tightStackingKept() throws {
        let size = CGSize(width: 1080, height: 1920)
        var item = Item(id: "tight", at: 0, duration: 30)
        item["text"] = .string("mo ra\nnam ca")
        item["textPreset"] = .string("hook-title")
        item["textStyle"] = .object(["emphasis": .bool(false)])
        let look = CaptionStyle(item)
        let texts = look.lines(item)
        let fonts = TextRenderer.lineFonts(look, lines: texts, canvas: size).lines
        let lines = TextRenderer.stack(
            look, texts: TextRenderer.plainTexts(look, lines: texts, fonts: fonts), fonts: fonts, canvas: size)
        let gap = lines[1].position.y - lines[0].position.y
        #expect(abs(gap - CTFontGetSize(fonts[0]) * look.lineSpacing) < 0.5)
    }

    /// The pixels one line draws on its own at its laid-out position, y up from the bottom.
    private func drawnInk(_ layout: CaptionLineLayout, size: CGSize) -> CGRect? {
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = context.data else { return nil }
        context.textPosition = layout.position
        CTLineDraw(layout.line, context)
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        var minX = width, maxX = -1, minRow = height, maxRow = -1
        for row in 0..<height {
            for column in 0..<width where pixels[row * width + column] > 24 {
                minX = min(minX, column); maxX = max(maxX, column)
                minRow = min(minRow, row); maxRow = max(maxRow, row)
            }
        }
        guard maxX >= 0 else { return nil }
        // Bitmap rows run top-down in memory.
        return CGRect(x: minX, y: height - 1 - maxRow, width: maxX - minX + 1, height: maxRow - minRow + 1)
    }
}
