import BashCutProject
import CoreGraphics
import CoreText
import Foundation

/// How a text block lays out: each line's font, the lines stacked bottom-up, and the plates and bars around them.
extension TextRenderer {
    /// Each line's font in reading order, and the block's base font: the style's font fitted to the frame by the
    /// lines that use it as is; the emphasis line (`scale` times larger) and lines with their own font or scale
    /// (`textStyle.lines`) are fitted on their own.
    static func lineFonts(_ look: CaptionStyle, lines: [String], canvas: CGSize) -> (base: CTFont, lines: [CTFont]) {
        let emphasis = look.emphasis(lineCount: lines.count)
        let scales = lines.indices.map { index in
            (emphasis?.line == index ? emphasis?.scale ?? 1 : 1) * TextLineStyles.scale(look.style, line: index)
        }
        let names = lines.indices.map { look.fontName(line: $0) }
        // A line drawn in its own font or size is fitted on its own, so it does not shrink the rest.
        let plain = lines.indices.filter { scales[$0] == 1 && names[$0] == look.fontName }
        let base = fittedFont(
            look.fontName, size: fontSize(look.relativeSize, canvas: canvas), lines: plain.map { lines[$0] },
            maximumWidth: canvas.width * 0.9, tracking: look.tracking)
        return (base, lines.indices.map { index in
            guard !plain.contains(index) else { return base }
            return fittedFont(
                names[index], size: CTFontGetSize(base) * scales[index], lines: [lines[index]],
                maximumWidth: canvas.width * 0.9, tracking: look.tracking)
        })
    }

    /// Lays out `texts` (reading order) bottom-up, placed by the style's align and positionX: the bottom baseline
    /// sits at `baseline` of the height and each line above sits `lineSpacing` × the mean of the two lines' font
    /// sizes higher, so a larger emphasis line gets room above and below it. The gap never drops below the ink the
    /// two lines reach toward each other (stacked tone marks, a dot below, the outline, the emphasis plate) plus a
    /// small clearance, so no preset or line height draws one line into the next.
    static func stack(
        _ look: CaptionStyle, texts: [NSAttributedString], fonts: [CTFont], canvas: CGSize
    ) -> [CaptionLineLayout] {
        var y = canvas.height * look.baseline
        var below: (points: CGFloat, top: CGFloat)?
        // A plate behind the emphasis line needs its padding clear of the lines next to it.
        let emphasis = look.emphasis(lineCount: texts.count)
        let plated = emphasis?.plate == nil ? nil : emphasis.map { texts.count - 1 - $0.line }
        let platePadding = CGFloat(emphasis?.plate?["padding"]?.double ?? 0.12)
        let lines = zip(texts, fonts).reversed().enumerated().map { index, entry in
            let (text, font) = entry
            let points = CTFontGetSize(font)
            let line = CTLineCreateWithAttributedString(text)
            let ink = inkExtent(line, points: points, stroke: look.stroke, plate: index == plated ? platePadding : nil)
            if let below {
                var gap = look.lineSpacing * (below.points + points) / 2
                if let plated, index == plated || index - 1 == plated {
                    gap += platePadding * max(below.points, points)
                }
                y += max(gap, below.top + ink.bottom + inkClearance * (below.points + points) / 2)
            }
            below = (points, ink.top)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            return CaptionLineLayout(line: line, width: width, position: CGPoint(x: look.x(width: width, canvas: canvas), y: y))
        }
        // Keep a tall block (large emphasis, landscape frame) inside the frame's height, as width fitting does.
        guard let bottom = lines.first, let top = lines.last else { return lines }
        var ascent: CGFloat = 0, descent: CGFloat = 0
        CTLineGetTypographicBounds(top.line, &ascent, nil, nil)
        CTLineGetTypographicBounds(bottom.line, nil, &descent, nil)
        let margin = canvas.height * 0.03
        let over = top.position.y + ascent * (1 + (plated == lines.count - 1 ? platePadding * 2 : 0)) - (canvas.height - margin)
        let room = bottom.position.y - descent - margin
        let shift = over > 0 ? -min(over, max(0, room)) : 0
        guard shift != 0 else { return lines }
        return lines.map {
            CaptionLineLayout(line: $0.line, width: $0.width, position: CGPoint(x: $0.position.x, y: $0.position.y + shift))
        }
    }

    /// The least space between one line's ink and the next, in font sizes.
    static let inkClearance: CGFloat = 0.06

    /// How far a line's ink reaches above and below its baseline: the glyph outlines (so stacked marks count), widened
    /// by the outer half of the stroke, or the emphasis plate (`plate` padding in font sizes) where it reaches further.
    static func inkExtent(_ line: CTLine, points: CGFloat, stroke: Double, plate: CGFloat?) -> (top: CGFloat, bottom: CGFloat) {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let outline = abs(stroke) * points / 200
        var top = (glyphs.isNull ? ascent : glyphs.maxY) + outline
        var bottom = (glyphs.isNull ? descent : -glyphs.minY) + outline
        if let plate {
            // The plate `decorations` draws: the glyph top to 0.4 of the descent, padded.
            top = max(top, (glyphs.isNull ? ascent : glyphs.maxY) + plate * points)
            bottom = max(bottom, descent * 0.4 + plate * points)
        }
        return (top, bottom)
    }

    /// Plain (uncoloured) line strings for measuring: each line's font and tracking.
    static func plainTexts(_ look: CaptionStyle, lines: [String], fonts: [CTFont]) -> [NSAttributedString] {
        zip(lines, fonts).map { text, font in
            NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTKernAttributeName as String): look.tracking * CTFontGetSize(font),
            ])
        }
    }

    static func rasterBounds(lines: [CaptionLineLayout], decorations: [CaptionDecoration], padding: CGFloat, canvas: CGRect) -> CGRect {
        var bounds = CGRect.null
        for line in lines {
            var ascent: CGFloat = 0, descent: CGFloat = 0
            CTLineGetTypographicBounds(line.line, &ascent, &descent, nil)
            let typographic = CGRect(x: line.position.x, y: line.position.y - descent, width: line.width, height: ascent + descent)
            let glyphs = CTLineGetBoundsWithOptions(line.line, .useGlyphPathBounds).offsetBy(dx: line.position.x, dy: line.position.y)
            bounds = bounds.union(typographic.union(glyphs).insetBy(dx: -padding, dy: -padding))
        }
        for decoration in decorations { bounds = bounds.union(decoration.rect.insetBy(dx: -1, dy: -1)) }
        let visible = bounds.integral.intersection(canvas)
        return visible.isNull || visible.isEmpty ? CGRect(x: 0, y: 0, width: 1, height: 1) : visible
    }

    /// The block's plates and bars, then the emphasis line's own plate on top of them.
    static func decorations(
        _ look: CaptionStyle, lines: [CaptionLineLayout], lineHeight: CGFloat, canvas: CGSize
    ) -> [CaptionDecoration] {
        let block = blockDecorations(look, lines: lines, lineHeight: lineHeight, canvas: canvas)
        guard let emphasis = look.emphasis(lineCount: lines.count), let plate = emphasis.plate else { return block }
        // `lines` run bottom-up; the emphasis line counts from the top.
        let layout = lines[lines.count - 1 - emphasis.line]
        let points = CTFontGetSize(layout.font)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        CTLineGetTypographicBounds(layout.line, &ascent, &descent, nil)
        let glyphs = CTLineGetBoundsWithOptions(layout.line, .useGlyphPathBounds)
        let padding = CGFloat(plate["padding"]?.double ?? 0.12) * points
        let top = glyphs.isNull ? ascent : glyphs.maxY
        let rect = CGRect(x: layout.position.x, y: layout.position.y - descent * 0.4, width: layout.width,
                          height: top + descent * 0.4).insetBy(dx: -padding, dy: -padding)
        return block + [CaptionDecoration(
            rect: rect, color: color(plate["color"]?.string ?? "#FFFFFF", alpha: plate["opacity"]?.double ?? 1),
            radius: CGFloat(plate["radius"]?.double ?? 0.06) * points)]
    }

    /// The style's own `background` plate, else the preset's plates and bars.
    static func blockDecorations(
        _ look: CaptionStyle, lines: [CaptionLineLayout], lineHeight: CGFloat, canvas: CGSize
    ) -> [CaptionDecoration] {
        guard let first = lines.first else { return [] }
        if look.background != nil || look.accentBars != nil {
            let points = lineHeight / look.lineSpacing
            let minX = lines.map(\.position.x).min() ?? 0
            let maxX = lines.map { $0.position.x + $0.width }.max() ?? 0
            // Reach the top line's marks and the bottom line's descenders, which a larger emphasis line or stacked
            // tone marks carry past the line height.
            let last = lines.last ?? first
            let topInk = inkExtent(last.line, points: CTFontGetSize(last.font), stroke: look.stroke, plate: nil).top
            let bottomInk = inkExtent(first.line, points: CTFontGetSize(first.font), stroke: look.stroke, plate: nil).bottom
            let top = last.position.y + max(lineHeight * 0.8, topInk)
            let bottom = first.position.y - max(lineHeight * 0.28, bottomInk)
            var box = CGRect(x: minX, y: bottom, width: maxX - minX, height: top - bottom)
            var result: [CaptionDecoration] = []
            if let background = look.background {
                let padding = CGFloat(background["padding"]?.double ?? 0.3) * points
                box = box.insetBy(dx: -padding, dy: -padding)
                result.append(CaptionDecoration(
                    rect: box, color: color(background["color"]?.string ?? "#000000", alpha: background["opacity"]?.double ?? 0.8),
                    radius: CGFloat(background["radius"]?.double ?? 0.2) * points))
            }
            return result + (look.accentBars ?? []).map { accentBar($0, around: box, points: points) }
        }
        switch look.preset {
        case .keywordSticker:
            return lines.map { CaptionDecoration(rect: CGRect(x: $0.position.x - 12, y: $0.position.y - 12,
                width: $0.width + 24, height: lineHeight + 12), color: color("#FACC15")) }
        case .placeCard:
            let width = min(canvas.width * 0.8, (lines.map(\.width).max() ?? 0) + 52)
            let rect = CGRect(x: canvas.width * 0.075, y: first.position.y - 18, width: width,
                              height: (lines.last?.position.y ?? first.position.y) - first.position.y + lineHeight + 30)
            return [CaptionDecoration(rect: rect, color: CGColor(gray: 0.03, alpha: 0.86), radius: 14),
                    CaptionDecoration(rect: CGRect(x: rect.minX, y: rect.minY, width: 8, height: rect.height), color: color("#FACC15"))]
        case .chapterCard:
            let top = lines.last?.position.y ?? first.position.y - 18
            return [CaptionDecoration(rect: CGRect(x: canvas.width * 0.25, y: first.position.y - 18, width: canvas.width * 0.5, height: 3),
                                      color: color("#E0B43A")),
                    CaptionDecoration(rect: CGRect(x: canvas.width * 0.38, y: top + lineHeight + 12, width: canvas.width * 0.24, height: 2),
                                      color: color("#E0B43A"))]
        default: return []
        }
    }
    /// One accent bar beside `box` (the text block, or its plate): on `side`, `gap` font sizes away, `thickness` font
    /// sizes thick and `length` of that side long, centred on it.
    static func accentBar(_ bar: [String: JSONValue], around box: CGRect, points: CGFloat) -> CaptionDecoration {
        let thickness = CGFloat(min(2, max(0.005, bar["thickness"]?.double ?? 0.12))) * points
        let gap = CGFloat(min(4, max(-4, bar["gap"]?.double ?? 0.2))) * points
        let share = CGFloat(min(1, max(0, bar["length"]?.double ?? 1)))
        let rect: CGRect
        switch bar["side"]?.string ?? "left" {
        case "right":
            rect = CGRect(x: box.maxX + gap, y: box.midY - box.height * share / 2, width: thickness, height: box.height * share)
        case "top":
            rect = CGRect(x: box.midX - box.width * share / 2, y: box.maxY + gap, width: box.width * share, height: thickness)
        case "bottom":
            rect = CGRect(x: box.midX - box.width * share / 2, y: box.minY - gap - thickness, width: box.width * share, height: thickness)
        default:
            rect = CGRect(x: box.minX - gap - thickness, y: box.midY - box.height * share / 2, width: thickness, height: box.height * share)
        }
        return CaptionDecoration(
            rect: rect, color: color(bar["color"]?.string ?? "#FACC15", alpha: bar["opacity"]?.double ?? 1),
            radius: CGFloat(max(0, bar["radius"]?.double ?? 0)) * thickness)
    }
}
