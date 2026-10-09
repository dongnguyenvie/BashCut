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

enum CaptionPreset: String {
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
        // Heavy and condensed like social hook titles; ships with macOS and covers Vietnamese.
        case .hookTitle: return "HelveticaNeue-CondensedBlack"
        default: return "Arial-BoldMT"
        }
    }
    var size: Double {
        switch self {
        case .cinematicSerif: return 0.043
        case .placeCard: return 0.045
        case .hookTitle: return 0.085
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
        case .boldOutline: return 4
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
    /// Baseline distance in font sizes: hook titles stack their lines tight.
    var lineSpacing: Double { self == .hookTitle ? 1.0 : 1.28 }
    /// A soft drop shadow instead of an outline, for hook titles.
    var shadow: [String: JSONValue]? {
        self == .hookTitle
            ? ["color": .string("#000000"), "opacity": .number(0.5), "blur": .number(24), "dy": .number(-6)] : nil
    }
}

/// One line of a text block drawn larger and in its own colour (the keyword line of a hook title).
struct CaptionEmphasis {
    static let fill = "#FFD60A"
    static let scale = 1.4
    /// The line, counted from the top in reading order.
    let line: Int
    let fill: String
    let scale: Double
    /// A plate behind the line alone: `{color, opacity, padding, radius}` (padding and radius in font sizes).
    let plate: [String: JSONValue]?
}

struct CaptionDecoration {
    let rect: CGRect
    let color: CGColor
    var radius: CGFloat = 0
}

struct CaptionLineLayout {
    let line: CTLine
    let width: CGFloat
    let position: CGPoint
    /// The line's font: the first run's, which is the line's own (every run of a line shares it).
    var font: CTFont {
        guard let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first,
              let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] else {
            return CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        }
        return font as! CTFont  // swiftlint:disable:this force_cast
    }
}

/// A text item's look: its preset's defaults overridden by the open `textStyle` fields (Phase 2 restyle): `align`
/// left|center|right, `positionX` (0–1: the left edge, centre or right edge by align), `lineHeight` (× font size),
/// `tracking` (× font size between letters), `uppercase`, `background {color, opacity, padding, radius}` (a plate
/// behind the block), `shadow {color, opacity, blur, dx, dy}` and `accentBars [{side left|right|top|bottom, color,
/// opacity, thickness, gap (× font size), length (share of the block's side), radius}]` (flexibility audit C1). A
/// background or accent bars replace the preset's own plates and bars.
struct CaptionStyle {
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
        lineSpacing = style["lineHeight"]?.double ?? preset.lineSpacing
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
    var shadow: [String: JSONValue]? { style["shadow"]?.object ?? (style["shadow"] == nil ? preset.shadow : nil) }

    /// `textStyle.emphasis {line, fill, scale, plate}`: `line` counts from the top (negative from the bottom), `scale`
    /// × the font size. Without `line`, the last of two lines or the middle one is emphasised, and a single line is not.
    /// Hook titles emphasise by default; `false` turns it off.
    func emphasis(lineCount: Int) -> CaptionEmphasis? {
        let value = style["emphasis"]
        if value?.bool == false { return nil }
        if case .null? = value { return nil }
        let fields = value?.object
        let given = fields?["line"]?.double.map { Int($0) }
        // Without a line, a single line is not emphasised: it is the whole title.
        guard given != nil || ((fields != nil || preset == .hookTitle) && lineCount >= 2) else { return nil }
        let requested = given ?? (lineCount == 2 ? 1 : lineCount / 2)
        let line = requested < 0 ? lineCount + requested : requested
        guard lineCount > 0, (0..<lineCount).contains(line) else { return nil }
        return CaptionEmphasis(
            line: line, fill: fields?["fill"]?.string ?? CaptionEmphasis.fill,
            scale: min(3, max(0.3, fields?["scale"]?.double ?? CaptionEmphasis.scale)), plate: fields?["plate"]?.object)
    }

    /// `textStyle.lineFills`: line colours in reading order, repeating (two-tone titles); nil when not set.
    func lineFill(_ index: Int) -> String? {
        guard case .array(let fills)? = style["lineFills"] else { return nil }
        let colors = fills.compactMap(\.string)
        return colors.isEmpty ? nil : colors[index % colors.count]
    }
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
        let fonts = lineFonts(look, lines: lineTexts, canvas: size)
        let points = CTFontGetSize(fonts.base)
        let fill = color(style["fill"]?.string ?? preset.fill)
        let stroke = look.stroke
        let emphasis = look.emphasis(lineCount: lineTexts.count)
        func attributes(_ index: Int) -> [NSAttributedString.Key: Any] {
            let font = fonts.lines[index]
            let emphasized = emphasis?.line == index
            return [
                NSAttributedString.Key(kCTKernAttributeName as String): look.tracking * CTFontGetSize(font),
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): emphasized
                    ? color(emphasis?.fill ?? CaptionEmphasis.fill) : look.lineFill(index).map { color($0) } ?? fill,
                NSAttributedString.Key(kCTStrokeColorAttributeName as String): color(
                    style["stroke"]?.string ?? "#000000"),
                NSAttributedString.Key(kCTStrokeWidthAttributeName as String): -stroke,
            ]
        }
        let lineHeight = points * look.lineSpacing
        // Word indexes run in reading order; lines are laid out bottom-up.
        var firstWord: [Int] = []
        var wordCount = 0
        for text in lineTexts {
            firstWord.append(wordCount)
            wordCount += CaptionWords.tokens(text).count
        }
        let texts = lineTexts.indices.map { index in
            WordColoring(item: item, spoken: spoken, attributes: attributes(index))
                .string(lineTexts[index], firstWord: firstWord[index])
        }
        let lines = stack(look, texts: texts, fonts: fonts.lines, canvas: size)
        let decorations = decorations(look, lines: lines, lineHeight: lineHeight, canvas: size)
        let shadow = look.shadow
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
    /// The rendered layout of a text item on a `size` canvas (#465): the fitted font size and the union of the lines'
    /// typographic and glyph bounds (with the outline) plus the preset's plates and bars, in pixels with y up from the
    /// bottom, laid out exactly as `raster` draws them. Shadows and keyframed motion are not included.
    static func layout(_ item: Item, size: CGSize) -> TextLayout? {
        guard size.width > 0, size.height > 0,
              !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let look = CaptionStyle(item)
        let lineTexts = look.lines(item)
        let fonts = lineFonts(look, lines: lineTexts, canvas: size)
        let points = CTFontGetSize(fonts.base)
        let lineHeight = points * look.lineSpacing
        let lines = stack(look, texts: plainTexts(look, lines: lineTexts, fonts: fonts.lines), fonts: fonts.lines, canvas: size)
        var bounds = CGRect.null
        for layout in lines {
            // The outline is centred on the glyph edge, so half its width (a share of the font size) lies outside.
            let outline = abs(look.stroke) * CTFontGetSize(layout.font) / 200
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
        let texts = look.lines(item)
        let fonts = lineFonts(look, lines: texts, canvas: size).lines
        let lines = stack(look, texts: plainTexts(look, lines: texts, fonts: fonts), fonts: fonts, canvas: size)
        guard let bottom = lines.first, let top = lines.last else {
            return CGPoint(x: size.width * look.positionX, y: size.height * look.baseline)
        }
        // Halfway between the bottom baseline and the top line's cap height.
        let y = (bottom.position.y + top.position.y + CTFontGetSize(top.font) * 0.7) / 2
        guard look.align != "center" else { return CGPoint(x: size.width * look.positionX, y: y) }
        let widest = lines.map(\.width).max() ?? 0
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
