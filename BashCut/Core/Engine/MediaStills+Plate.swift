import CoreGraphics
import Foundation

extension MediaStills {
    /// Contrast of text standing on its own plate (B7): each of `fills` (`#RRGGBB`: the fill, a spoken-word
    /// highlight) against the plate colour laid at `opacity` over the picture behind the block (the mean of `without`
    /// inside `rect`), the lowest of them. What the letters stand on is the plate, not the picture, so a dark scene
    /// does not lower the ratio of light letters on a dark plate. Nil when a colour does not read or the rect is empty.
    public static func plateContrast(
        fills: [String], plate: String, opacity: Double, without: CGImage, rect: CGRect
    ) -> Contrast? {
        let width = without.width, height = without.height
        guard let bytes = pixels(without, width: width, height: height), let box = rgb(plate) else { return nil }
        let x0 = max(0, Int(rect.minX * Double(width))), x1 = min(width, Int(rect.maxX * Double(width)))
        let y0 = max(0, Int(rect.minY * Double(height))), y1 = min(height, Int(rect.maxY * Double(height)))
        var sum = [0.0, 0.0, 0.0], count = 0
        for y in y0..<max(y0, y1) {
            for x in x0..<max(x0, x1) {
                let offset = (y * width + x) * 4
                for channel in 0..<3 { sum[channel] += Double(bytes[offset + channel]) }
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let alpha = min(1, max(0, opacity))
        var laid: [UInt8] = [255, 255, 255, 255]
        for channel in 0..<3 {
            let mixed: Double = alpha * box[channel] + (1 - alpha) * sum[channel] / Double(count)
            laid[channel] = UInt8(mixed.rounded())
        }
        let behind = luminance(laid, 0)
        var ratios: [(ratio: Double, text: Double)] = []
        for color in fills.compactMap(rgb) {
            let text = luminance(color.map { UInt8($0.rounded()) } + [255], 0)
            ratios.append(((max(text, behind) + 0.05) / (min(text, behind) + 0.05), text))
        }
        guard let lowest = ratios.min(by: { $0.ratio < $1.ratio }) else { return nil }
        let highest = ratios.map { $0.ratio }.max() ?? lowest.ratio
        return Contrast(
            ratio: lowest.ratio, meanRatio: lowest.ratio, text: lowest.text, background: behind, pixels: count,
            lightRatio: highest, darkRatio: lowest.ratio)
    }

    /// The 0–255 channels of a `#RRGGBB` (or `#RRGGBBAA`) colour.
    static func rgb(_ hex: String) -> [Double]? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits.prefix(6), radix: 16) else { return nil }
        return [Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF)]
    }
}
