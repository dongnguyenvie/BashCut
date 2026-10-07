import BashCutProject
import CoreGraphics
import CoreImage
import CoreText
import CryptoKit
import Foundation

final class CaptionRaster: @unchecked Sendable {
    let bitmap: CGImage
    let image: CIImage
    let bounds: CGRect
    var bytes: Int { bitmap.bytesPerRow * bitmap.height }

    init(bitmap: CGImage, bounds: CGRect) {
        self.bitmap = bitmap
        self.bounds = bounds
        image = CIImage(cgImage: bitmap).transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
    }
}
private final class CaptionCache: @unchecked Sendable {
    let images = NSCache<NSString, CaptionRaster>()
    init() {
        images.countLimit = 100
        images.totalCostLimit = 128 * 1024 * 1024
    }
}

private enum CaptionPreset: String {
    case boldOutline = "bold-outline"
    case cinematicSerif = "cinematic-serif"
    case keywordSticker = "keyword-sticker"
    case placeCard = "place-card"
    case hookTitle = "hook-title"
    case chapterCard = "chapter-card"

    init(_ value: String?) { self = CaptionPreset(rawValue: value ?? "") ?? .boldOutline }
    var font: String {
        switch self {
        case .cinematicSerif: return "TimesNewRomanPSMT"
        case .chapterCard: return "TimesNewRomanPS-BoldMT"
        default: return "Arial-BoldMT"
        }
    }
    var size: Double {
        switch self {
        case .cinematicSerif: return 0.043
        case .placeCard: return 0.045
        case .hookTitle: return 0.082
        case .chapterCard: return 0.06
        default: return 0.055
        }
    }
    var fill: String {
        switch self {
        case .cinematicSerif: return "#E0B43A"
        case .keywordSticker: return "#111111"
        case .chapterCard: return "#F5E7C6"
        default: return "#FFFFFF"
        }
    }
    var strokeWidth: Double {
        switch self {
        case .boldOutline, .hookTitle: return 4
        default: return 0
        }
    }
    var baseline: Double {
        switch self {
        case .placeCard: return 0.12
        case .hookTitle: return 0.56
        case .chapterCard: return 0.52
        default: return 0.18
        }
    }
    var leftAligned: Bool { self == .placeCard }
}

private struct CaptionDecoration {
    let rect: CGRect
    let color: CGColor
    var radius: CGFloat = 0
}

private struct CaptionLineLayout {
    let line: CTLine
    let width: CGFloat
    let position: CGPoint
}

/// A text item's look: its preset's defaults overridden by the open `textStyle` fields (Phase 2 restyle): `align`
/// left|center|right, `positionX` (0–1: the left edge, centre or right edge by align), `lineHeight` (× font size),
/// `tracking` (× font size between letters), `uppercase`, `background {color, opacity, padding, radius}` (a plate
/// behind the block), `shadow {color, opacity, blur, dx, dy}` and `accentBars [{side left|right|top|bottom, color,
/// opacity, thickness, gap (× font size), length (share of the block's side), radius}]` (flexibility audit C1). A
/// background or accent bars replace the preset's own plates and bars.
private struct CaptionStyle {
    let preset: CaptionPreset
    let style: [String: JSONValue]
    let relativeSize: Double
    let fontName: String
    let baseline: Double
    let stroke: Double
    let lineSpacing: Double
    let tracking: Double
    let uppercase: Bool
    let align: String
    let positionX: Double

    init(_ item: Item) {
        preset = CaptionPreset(item.textPreset)
        style = item["textStyle"]?.object ?? [:]
        relativeSize = style["size"]?.double ?? preset.size
        fontName = style["font"]?.string ?? preset.font
        baseline = style["positionY"]?.double ?? preset.baseline
        stroke = style["strokeWidth"]?.double ?? preset.strokeWidth
        lineSpacing = style["lineHeight"]?.double ?? 1.28
        tracking = style["tracking"]?.double ?? 0
        uppercase = style["uppercase"]?.bool ?? false
        align = style["align"]?.string ?? (preset.leftAligned ? "left" : "center")
        positionX = style["positionX"]?.double ?? (align == "left" ? 0.1 : align == "right" ? 0.9 : 0.5)
    }

    func lines(_ item: Item) -> [String] {
        (uppercase ? item.text.uppercased() : item.text).components(separatedBy: "\n")
    }

    /// Where a line of `width` starts on a `canvas`-wide frame.
    func x(width: CGFloat, canvas: CGSize) -> CGFloat {
        switch align {
        case "left": canvas.width * positionX
        case "right": canvas.width * positionX - width
        default: canvas.width * positionX - width / 2
        }
    }

    var background: [String: JSONValue]? { style["background"]?.object }
    var accentBars: [[String: JSONValue]]? {
        guard case .array(let bars)? = style["accentBars"] else { return nil }
        return bars.map(\.object)
    }
    var shadow: [String: JSONValue]? { style["shadow"]?.object }
}

/// The `textStyle` values a renderer preset uses when an item does not set them (#380, the library's text style sheet
/// and cards).
public enum TextPresetStyle {
    /// `size`, `positionY` and `strokeWidth` of `preset`.
    public static func defaults(_ preset: String?) -> [String: Double] {
        let preset = CaptionPreset(preset)
        return ["size": preset.size, "positionY": preset.baseline, "strokeWidth": preset.strokeWidth]
    }

    /// The PostScript name of `preset`'s font.
    public static func font(_ preset: String?) -> String { CaptionPreset(preset).font }

    /// `preset`'s text colour, `#RRGGBB`.
    public static func fill(_ preset: String?) -> String { CaptionPreset(preset).fill }

    /// How `item` lays out on a `size` frame, as the renderer draws it (#465).
    public static func layout(_ item: Item, size: CGSize) -> TextLayout? { TextRenderer.layout(item, size: size) }
}

enum TextRenderer {
    private static let cache = CaptionCache()

    /// Drops every cached raster (a font was registered or removed, so names may draw differently).
    static func clearCache() { cache.images.removeAllObjects() }
    /// The cropped raster; consumers needing canvas placement use `overlay` instead.
    static func image(_ item: Item, size: CGSize, spoken: Int? = nil, itemKey: String? = nil) -> CGImage? {
        raster(item, size: size, spoken: spoken, itemKey: itemKey)?.bitmap
    }

    /// Cached CIImage with canvas placement already applied, reused directly by every compositor frame.
    static func overlay(_ item: Item, size: CGSize, spoken: Int? = nil, itemKey: String? = nil) -> CIImage? {
        raster(item, size: size, spoken: spoken, itemKey: itemKey)?.image
    }

    /// `fullCanvas` keeps a reference rendering path for pixel-parity tests; production draws only the visible bounds.
    static func raster(_ item: Item, size: CGSize, spoken: Int? = nil, itemKey: String? = nil, fullCanvas: Bool = false) -> CaptionRaster? {
        let key = (itemKey ?? cacheKey(item))
            + "\(size.width)x\(size.height)" + (item.wordStyle == nil ? "" : "#\(spoken ?? -1)") + (fullCanvas ? ":full" : "")
        if let cached = cache.images.object(forKey: key as NSString) { return cached }
        let look = CaptionStyle(item)
        let preset = look.preset, style = look.style
        let lineTexts = look.lines(item)
        let font = fittedFont(
            look.fontName, size: fontSize(look.relativeSize, canvas: size), lines: lineTexts,
            maximumWidth: size.width * 0.9, tracking: look.tracking)
        let points = CTFontGetSize(font)
        let fill = color(style["fill"]?.string ?? preset.fill)
        let stroke = look.stroke
        let baseline = look.baseline
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTKernAttributeName as String): look.tracking * points,
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill,
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): color(
                style["stroke"]?.string ?? "#000000"),
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): -stroke,
        ]
        let lineHeight = points * look.lineSpacing
        let words = WordColoring(item: item, spoken: spoken, attributes: attributes)
        // Word indexes run in reading order; lines are laid out bottom-up.
        var firstWord: [Int] = []
        var wordCount = 0
        for text in lineTexts {
            firstWord.append(wordCount)
            wordCount += CaptionWords.tokens(text).count
        }
        let lines = Array(zip(lineTexts, firstWord)).reversed().enumerated().map { index, entry in
            let (lineText, first) = entry
            let line = CTLineCreateWithAttributedString(words.string(lineText, firstWord: first))
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            let position = linePosition(look, width: width, index: index, spacing: (baseline, lineHeight), canvas: size)
            return CaptionLineLayout(line: line, width: width, position: position)
        }
        let decorations = decorations(look, lines: lines, lineHeight: lineHeight, canvas: size)
        let shadow = look.shadow ?? (preset == .hookTitle && look.style["shadow"] == nil
            ? ["color": .string("#000000"), "blur": .number(8), "dy": .number(-5)] : nil)
        let canvas = CGRect(origin: .zero, size: size)
        let bounds = fullCanvas ? canvas : rasterBounds(lines: lines, decorations: decorations,
            padding: abs(stroke) * points / 100 + (shadow.map { CGFloat(($0["blur"]?.double ?? 8) * 2 + 16) } ?? 2), canvas: canvas)
        guard let context = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        for decoration in decorations {
            context.setFillColor(decoration.color)
            context.addPath(CGPath(roundedRect: decoration.rect, cornerWidth: decoration.radius, cornerHeight: decoration.radius, transform: nil))
            context.fillPath()
        }
        for layout in lines {
            context.saveGState()
            if let shadow {
                context.setShadow(
                    offset: CGSize(width: shadow["dx"]?.double ?? 0, height: shadow["dy"]?.double ?? -5),
                    blur: shadow["blur"]?.double ?? 8,
                    color: color(shadow["color"]?.string ?? "#000000", alpha: shadow["opacity"]?.double ?? 1))
            }
            context.textPosition = layout.position
            CTLineDraw(layout.line, context)
            context.restoreGState()
        }
        guard let image = context.makeImage() else { return nil }
        let raster = CaptionRaster(bitmap: image, bounds: bounds)
        cache.images.setObject(raster, forKey: key as NSString, cost: raster.bytes)
        return raster
    }
    /// Where line `index` (counted from the bottom line) starts, by the style's align and positionX; the bottom
    /// baseline sits at `baseline` of the height and lines stack upwards `lineHeight` apart.
    private static func linePosition(
        _ look: CaptionStyle, width: CGFloat, index: Int, spacing: (baseline: Double, lineHeight: CGFloat), canvas: CGSize
    ) -> CGPoint {
        CGPoint(x: look.x(width: width, canvas: canvas),
                y: canvas.height * spacing.baseline + Double(index) * spacing.lineHeight)
    }

    /// The rendered layout of a text item on a `size` canvas (#465): the fitted font size and the union of the lines'
    /// typographic and glyph bounds (with the outline) plus the preset's plates and bars, in pixels with y up from the
    /// bottom, laid out exactly as `raster` draws them. Shadows and keyframed motion are not included.
    static func layout(_ item: Item, size: CGSize) -> TextLayout? {
        guard size.width > 0, size.height > 0,
              !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let look = CaptionStyle(item)
        let lineTexts = look.lines(item)
        let font = fittedFont(
            look.fontName, size: fontSize(look.relativeSize, canvas: size), lines: lineTexts,
            maximumWidth: size.width * 0.9, tracking: look.tracking)
        let points = CTFontGetSize(font)
        let lineHeight = points * look.lineSpacing
        let baseline = look.baseline
        // The outline is centred on the glyph edge, so half its width (a share of the font size) lies outside.
        let outline = abs(look.stroke) * points / 200
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): look.tracking * points,
        ]
        let lines = lineTexts.reversed().enumerated().map { index, text in
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            return CaptionLineLayout(
                line: line, width: width,
                position: linePosition(look, width: width, index: index, spacing: (baseline, lineHeight), canvas: size))
        }
        var bounds = CGRect.null
        for layout in lines {
            var ascent: CGFloat = 0, descent: CGFloat = 0
            CTLineGetTypographicBounds(layout.line, &ascent, &descent, nil)
            let typographic = CGRect(x: layout.position.x, y: layout.position.y - descent, width: layout.width, height: ascent + descent)
            let glyphs = CTLineGetBoundsWithOptions(layout.line, .useGlyphPathBounds)
                .offsetBy(dx: layout.position.x, dy: layout.position.y)
            bounds = bounds.union((glyphs.isNull ? typographic : typographic.union(glyphs)).insetBy(dx: -outline, dy: -outline))
        }
        for decoration in decorations(look, lines: lines, lineHeight: lineHeight, canvas: size) {
            bounds = bounds.union(decoration.rect)
        }
        guard !bounds.isNull else { return nil }
        return TextLayout(
            points: points, lines: lineTexts.count, minX: bounds.minX, maxX: bounds.maxX, minY: bounds.minY, maxY: bounds.maxY)
    }

    /// Hash only raster drawing inputs, once per TextLayer. Timing, identity and compositor transforms
    /// do not change these pixels; canvas size and the spoken word are appended by `image`.
    static func cacheKey(_ item: Item) -> String {
        let drawing: [String: JSONValue] = [
            "text": .string(item.text), "textPreset": .string(item.textPreset ?? ""),
            "textStyle": .object(item["textStyle"]?.object ?? [:]), "wordStyle": item["wordStyle"] ?? .string("")
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let data = (try? encoder.encode(drawing)) ?? Data(item.text.utf8)
        return Data(SHA256.hash(data: data)).base64EncodedString()
    }

    /// The middle of the item's text block, where text keyframes scale and rotate it.
    static func anchor(_ item: Item, size: CGSize) -> CGPoint {
        let look = CaptionStyle(item)
        let lines = look.lines(item)
        let font = fittedFont(
            look.fontName, size: fontSize(look.relativeSize, canvas: size), lines: lines,
            maximumWidth: size.width * 0.9, tracking: look.tracking)
        let points = CTFontGetSize(font)
        let y = size.height * look.baseline + points * look.lineSpacing * Double(lines.count - 1) / 2 + points * 0.35
        guard look.align != "center" else { return CGPoint(x: size.width * look.positionX, y: y) }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): look.tracking * points,
        ]
        let widest = lines.map {
            CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: attributes)), nil, nil, nil)
        }.max() ?? 0
        return CGPoint(x: look.x(width: widest, canvas: size) + widest / 2, y: y)
    }

    /// Text size is a fraction of the canvas's short side, so a preset looks the same in portrait, landscape and
    /// square projects (for 1080×1920 and 1920×1080 that side is 1080).
    static func fontSize(_ relativeSize: Double, canvas: CGSize) -> CGFloat {
        min(canvas.width, canvas.height) * relativeSize
    }

    /// The font at `size`, made smaller when the widest line would not fit `maximumWidth`, so a title never runs
    /// off the frame.
    static func fittedFont(_ name: String, size: CGFloat, lines: [String], maximumWidth: CGFloat, tracking: Double = 0) -> CTFont {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking * size,
        ]
        let widest = lines.map { text in
            CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), nil, nil,
                nil)
        }.max() ?? 0
        guard widest > maximumWidth, widest > 0 else { return font }
        return CTFontCreateWithName(name as CFString, size * maximumWidth / widest, nil)
    }

    private static func rasterBounds(lines: [CaptionLineLayout], decorations: [CaptionDecoration], padding: CGFloat, canvas: CGRect) -> CGRect {
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

    /// The style's own `background` plate, else the preset's plates and bars.
    private static func decorations(
        _ look: CaptionStyle, lines: [CaptionLineLayout], lineHeight: CGFloat, canvas: CGSize
    ) -> [CaptionDecoration] {
        guard let first = lines.first else { return [] }
        if look.background != nil || look.accentBars != nil {
            let points = lineHeight / look.lineSpacing
            let minX = lines.map(\.position.x).min() ?? 0
            let maxX = lines.map { $0.position.x + $0.width }.max() ?? 0
            let top = (lines.last?.position.y ?? first.position.y) + lineHeight * 0.8
            var box = CGRect(x: minX, y: first.position.y - lineHeight * 0.28, width: maxX - minX,
                             height: top - first.position.y + lineHeight * 0.28)
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
                              height: lineHeight * CGFloat(lines.count) + 30)
            return [CaptionDecoration(rect: rect, color: CGColor(gray: 0.03, alpha: 0.86), radius: 14),
                    CaptionDecoration(rect: CGRect(x: rect.minX, y: rect.minY, width: 8, height: rect.height), color: color("#FACC15"))]
        case .hookTitle:
            guard let widest = lines.max(by: { $0.width < $1.width }) else { return [] }
            return [CaptionDecoration(rect: CGRect(x: widest.position.x, y: first.position.y - 18, width: widest.width, height: 9),
                                      color: color("#FF3B30"))]
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
    private static func accentBar(_ bar: [String: JSONValue], around box: CGRect, points: CGFloat) -> CaptionDecoration {
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

    static func color(_ hex: String, alpha: Double = 1) -> CGColor {
        let value =
            UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        return CGColor(
            red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: CGFloat(min(1, max(0, alpha))))
    }
}

/// Colours each word of a line by its state (spoken, upcoming, past) for the item's `wordStates`: a state's `fill`
/// replaces the text colour, its `opacity` fades the fill and outline. Before any word is spoken every word is
/// upcoming.
private struct WordColoring {
    private static let wordPattern = try? NSRegularExpression(pattern: "\\S+")
    let states: [String: [String: JSONValue]]?
    let spoken: Int?
    let attributes: [NSAttributedString.Key: Any]

    init(item: Item, spoken: Int?, attributes: [NSAttributedString.Key: Any]) {
        states = item.wordStates
        self.spoken = spoken
        self.attributes = attributes
    }

    func string(_ line: String, firstWord: Int) -> NSAttributedString {
        let text = NSMutableAttributedString(string: line, attributes: attributes)
        guard let states, !states.isEmpty else { return text }
        let fill = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let stroke = NSAttributedString.Key(kCTStrokeColorAttributeName as String)
        let baseFill = attributes[fill].map { $0 as! CGColor }  // swiftlint:disable:this force_cast
        let baseStroke = attributes[stroke].map { $0 as! CGColor }  // swiftlint:disable:this force_cast
        var index = firstWord
        let nsLine = line as NSString
        for match in Self.wordPattern?.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) ?? [] {
            defer { index += 1 }
            let state = spoken.map { index == $0 ? "spoken" : index < $0 ? "past" : "upcoming" } ?? "upcoming"
            guard let look = states[state] else { continue }
            let opacity = CGFloat(min(1, max(0, look["opacity"]?.double ?? 1)))
            var color = look["fill"]?.string.map { TextRenderer.color($0) } ?? baseFill
            color = color.flatMap { $0.copy(alpha: $0.alpha * opacity) }
            if let color { text.addAttribute(fill, value: color, range: match.range) }
            if opacity < 1, let outline = baseStroke?.copy(alpha: (baseStroke?.alpha ?? 1) * opacity) {
                text.addAttribute(stroke, value: outline, range: match.range)
            }
        }
        return text
    }
}

extension ProjectFonts {
    /// The font a text item draws with (its `textStyle.font`, else its preset's) and the characters of its text that
    /// font has no glyphs for (P1-E1); nil when every character is covered or the font itself is missing.
    public static func missingGlyphs(_ item: Item) -> (font: String, characters: String)? {
        let name = item["textStyle"]?.object["font"]?.string ?? CaptionPreset(item.textPreset).font
        guard isAvailable(name) else { return nil }
        let characters = missingCharacters(name, text: item.text)
        return characters.isEmpty ? nil : (name, characters)
    }
}
