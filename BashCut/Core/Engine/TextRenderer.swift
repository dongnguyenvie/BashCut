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

enum TextRenderer {
    private static let cache = CaptionCache()
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
        let preset = CaptionPreset(item.textPreset)
        let style = item["textStyle"]?.object ?? [:]
        let relativeSize = style["size"]?.double ?? preset.size
        let fontName = style["font"]?.string ?? preset.font
        let font = fittedFont(
            fontName, size: fontSize(relativeSize, canvas: size), lines: item.text.components(separatedBy: "\n"),
            maximumWidth: size.width * 0.9)
        let points = CTFontGetSize(font)
        let fill = color(style["fill"]?.string ?? preset.fill)
        let stroke = style["strokeWidth"]?.double ?? preset.strokeWidth
        let baseline = style["positionY"]?.double ?? preset.baseline
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill,
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): color(
                style["stroke"]?.string ?? "#000000"),
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): -stroke,
        ]
        let lineHeight = points * 1.28
        let lineTexts = item.text.components(separatedBy: "\n")
        let words = WordColoring(item: item, spoken: spoken, attributes: attributes,
                                 highlight: color(style["highlight"]?.string ?? CaptionWords.defaultHighlight))
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
            let position = CGPoint(
                x: preset.leftAligned ? size.width * 0.1 : (size.width - width) / 2,
                y: size.height * baseline + Double(index) * lineHeight)
            return CaptionLineLayout(line: line, width: width, position: position)
        }
        let decorations = decorations(preset, lines: lines, lineHeight: lineHeight, canvas: size)
        let canvas = CGRect(origin: .zero, size: size)
        let bounds = fullCanvas ? canvas : rasterBounds(lines: lines, decorations: decorations,
            padding: abs(stroke) * points / 100 + (preset == .hookTitle ? 32 : 2), canvas: canvas)
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
            if preset == .hookTitle {
                context.setShadow(offset: CGSize(width: 0, height: -5), blur: 8, color: color("#000000"))
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
    /// Hash only raster drawing inputs, once per TextLayer. Timing, identity and compositor transforms
    /// do not change these pixels; canvas size and the spoken word are appended by `image`.
    static func cacheKey(_ item: Item) -> String {
        let drawing: [String: JSONValue] = [
            "text": .string(item.text), "textPreset": .string(item.textPreset ?? ""),
            "textStyle": .object(item["textStyle"]?.object ?? [:]), "wordStyle": .string(item.wordStyle ?? "")
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let data = (try? encoder.encode(drawing)) ?? Data(item.text.utf8)
        return Data(SHA256.hash(data: data)).base64EncodedString()
    }

    /// The middle of the item's text block, where text keyframes scale and rotate it.
    static func anchor(_ item: Item, size: CGSize) -> CGPoint {
        let preset = CaptionPreset(item.textPreset)
        let style = item["textStyle"]?.object ?? [:]
        let lines = item.text.components(separatedBy: "\n")
        let font = fittedFont(
            style["font"]?.string ?? preset.font, size: fontSize(style["size"]?.double ?? preset.size, canvas: size),
            lines: lines, maximumWidth: size.width * 0.9)
        let points = CTFontGetSize(font)
        let baseline = style["positionY"]?.double ?? preset.baseline
        let y = size.height * baseline + points * 1.28 * Double(lines.count - 1) / 2 + points * 0.35
        guard preset.leftAligned else { return CGPoint(x: size.width / 2, y: y) }
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let widest = lines.map {
            CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: attributes)), nil, nil, nil)
        }.max() ?? 0
        return CGPoint(x: size.width * 0.1 + widest / 2, y: y)
    }

    /// Text size is a fraction of the canvas's short side, so a preset looks the same in portrait, landscape and
    /// square projects (for 1080×1920 and 1920×1080 that side is 1080).
    static func fontSize(_ relativeSize: Double, canvas: CGSize) -> CGFloat {
        min(canvas.width, canvas.height) * relativeSize
    }

    /// The font at `size`, made smaller when the widest line would not fit `maximumWidth`, so a title never runs
    /// off the frame.
    static func fittedFont(_ name: String, size: CGFloat, lines: [String], maximumWidth: CGFloat) -> CTFont {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
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

    private static func decorations(
        _ preset: CaptionPreset, lines: [CaptionLineLayout], lineHeight: CGFloat, canvas: CGSize
    ) -> [CaptionDecoration] {
        guard let first = lines.first else { return [] }
        switch preset {
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
    private static func color(_ hex: String) -> CGColor {
        let value =
            UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        return CGColor(
            red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

/// Colours each word of a line by its state for the item's `wordStyle`.
private struct WordColoring {
    private static let wordPattern = try? NSRegularExpression(pattern: "\\S+")
    let style: String?
    let spoken: Int?
    let attributes: [NSAttributedString.Key: Any]
    let highlight: CGColor

    init(item: Item, spoken: Int?, attributes: [NSAttributedString.Key: Any], highlight: CGColor) {
        style = item.wordStyle
        self.spoken = spoken
        self.attributes = attributes
        self.highlight = highlight
    }

    func string(_ line: String, firstWord: Int) -> NSAttributedString {
        let text = NSMutableAttributedString(string: line, attributes: attributes)
        guard let style else { return text }
        let fill = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let stroke = NSAttributedString.Key(kCTStrokeColorAttributeName as String)
        let clear = CGColor(gray: 0, alpha: 0)
        var index = firstWord
        let nsLine = line as NSString
        for match in Self.wordPattern?.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) ?? [] {
            defer { index += 1 }
            switch style {
            case "highlight" where index == spoken:
                text.addAttribute(fill, value: highlight, range: match.range)
            case "karaoke" where spoken.map({ index <= $0 }) == true:
                text.addAttribute(fill, value: highlight, range: match.range)
            case "reveal" where spoken.map({ index > $0 }) ?? true:
                text.addAttributes([fill: clear, stroke: clear], range: match.range)
            default: break
            }
        }
        return text
    }
}
