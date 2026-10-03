import BashCutProject
import CoreGraphics
import CoreText
import CryptoKit
import Foundation

private final class CaptionImage: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
private final class CaptionCache: @unchecked Sendable {
    let images = NSCache<NSString, CaptionImage>()
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

private struct CaptionLineLayout {
    let line: CTLine
    let width: CGFloat
    let position: CGPoint
}

enum TextRenderer {
    private static let cache = CaptionCache()
    /// The item's text drawn over a transparent frame. `spoken` is the index of the word being spoken, for items
    /// with a `wordStyle`.
    /// `itemKey` is `cacheKey(item)`, passed by callers that draw the same item many times (the compositor makes
    /// it once per layer, not once per frame).
    static func image(_ item: Item, size: CGSize, spoken: Int? = nil, itemKey: String? = nil) -> CGImage? {
        let key = (itemKey ?? cacheKey(item))
            + "\(size.width)x\(size.height)" + (item.wordStyle == nil ? "" : "#\(spoken ?? -1)")
        if let cached = cache.images.object(forKey: key as NSString) { return cached.image }
        guard
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
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
        decorate(preset, lines: lines, lineHeight: lineHeight, context: context, canvas: size)
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
        cache.images.setObject(
            CaptionImage(image), forKey: key as NSString, cost: Int(size.width * size.height * 4))
        return image
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

    private static func decorate(
        _ preset: CaptionPreset, lines: [CaptionLineLayout], lineHeight: CGFloat,
        context: CGContext, canvas: CGSize
    ) {
        guard !lines.isEmpty else { return }
        switch preset {
        case .keywordSticker:
            context.setFillColor(color("#FACC15"))
            for line in lines {
                context.fill(
                    CGRect(
                        x: line.position.x - 12, y: line.position.y - 12,
                        width: line.width + 24, height: lineHeight + 12))
            }
        case .placeCard:
            let width = min(canvas.width * 0.8, (lines.map(\.width).max() ?? 0) + 52)
            let rect = CGRect(
                x: canvas.width * 0.075, y: lines[0].position.y - 18, width: width,
                height: lineHeight * CGFloat(lines.count) + 30)
            context.setFillColor(CGColor(gray: 0.03, alpha: 0.86))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil))
            context.fillPath()
            context.setFillColor(color("#FACC15"))
            context.fill(CGRect(x: rect.minX, y: rect.minY, width: 8, height: rect.height))
        case .hookTitle:
            let widest = lines.max(by: { $0.width < $1.width })
            if let widest {
                context.setFillColor(color("#FF3B30"))
                context.fill(
                    CGRect(
                        x: widest.position.x, y: lines[0].position.y - 18,
                        width: widest.width, height: 9))
            }
        case .chapterCard:
            let centerY = lines[0].position.y - 18
            context.setFillColor(color("#E0B43A"))
            context.fill(
                CGRect(x: canvas.width * 0.25, y: centerY, width: canvas.width * 0.5, height: 3))
            let top = lines.last?.position.y ?? centerY
            context.fill(
                CGRect(x: canvas.width * 0.38, y: top + lineHeight + 12, width: canvas.width * 0.24, height: 2))
        default: break
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
