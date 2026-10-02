import BashCutProject
import CoreGraphics
import CoreText
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
    static func image(_ item: Item, size: CGSize) -> CGImage? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let key =
            ((try? encoder.encode(item)).flatMap { String(data: $0, encoding: .utf8) } ?? item.text)
            + "\(size.width)x\(size.height)"
        if let cached = cache.images.object(forKey: key as NSString) { return cached.image }
        guard
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let preset = CaptionPreset(item["style"]?.string)
        let style = item["textStyle"]?.object ?? [:]
        let relativeSize = style["size"]?.double ?? preset.size
        let fontName = style["font"]?.string ?? preset.font
        let font = CTFontCreateWithName(fontName as CFString, size.width * relativeSize, nil)
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
        let lineHeight = size.width * relativeSize * 1.28
        let lines = item.text.components(separatedBy: "\n").reversed().enumerated().map { index, lineText in
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: lineText, attributes: attributes))
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
