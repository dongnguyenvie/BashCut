import BashCutProject
import CoreGraphics
import Foundation

/// Colour of a picture as numbers (P0-B8, `color.measure`), on the scale the colour skill reads (0–100): luma
/// percentiles (Rec. 709 weights on the encoded values: black = p1, mid = p50, white = p99), mean HSV saturation and
/// its 95th percentile, the tint of shadows (luma < 0.25), mids and highlights (≥ 0.7) as R−B and G−(R+B)/2, and the
/// share of clipped (a channel at full) and crushed (luma ≤ 2/255) pixels. A comparison adds the mean CIE76 ΔE
/// between two pictures of the same frame. Facts only.
public enum ColorMeasure {
    public struct Stats: Sendable, Equatable {
        public var black, p5, mid, p95, white, mean: Double
        public var saturation, saturationP95: Double
        /// [R−B, G−(R+B)/2] × 100 per band, nil when the band has fewer than 20 pixels.
        public var tintShadows, tintMids, tintHighlights: [Double]?
        public var clipped, crushed: Double

        public var json: JSONValue {
            let round = { (value: Double) in JSONValue.number((value * 10).rounded() / 10) }
            let tint = { (value: [Double]?) in value.map { JSONValue.array($0.map(round)) } ?? .null }
            return .object([
                "black": round(black), "p5": round(p5), "mid": round(mid), "p95": round(p95), "white": round(white),
                "mean": round(mean), "saturation": round(saturation), "saturationP95": round(saturationP95),
                "tintShadows": tint(tintShadows), "tintMids": tint(tintMids), "tintHighlights": tint(tintHighlights),
                "clippedShare": .number((clipped * 1_000).rounded() / 1_000),
                "crushedShare": .number((crushed * 1_000).rounded() / 1_000),
            ])
        }
    }

    /// Encoded sRGB values 0…1, three per pixel, of `image` drawn `width` pixels wide.
    static func pixels(_ image: CGImage, width: Int = 320) -> [Float] {
        let width = max(1, min(width, image.width))
        let height = max(1, Int((Double(image.height) * Double(width) / Double(max(1, image.width))).rounded()))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var result = [Float](repeating: 0, count: width * height * 3)
        for index in 0..<(width * height) {
            for channel in 0..<3 { result[index * 3 + channel] = Float(bytes[index * 4 + channel]) / 255 }
        }
        return result
    }

    public static func stats(_ image: CGImage) -> Stats { stats(pixels: pixels(image)) }

    static func stats(pixels: [Float]) -> Stats {
        let count = pixels.count / 3
        var lumas = [Double](repeating: 0, count: count), saturations = [Double](repeating: 0, count: count)
        var bands = [(rb: 0.0, gm: 0.0, n: 0), (rb: 0.0, gm: 0.0, n: 0), (rb: 0.0, gm: 0.0, n: 0)]
        var clipped = 0, crushed = 0
        for index in 0..<count {
            let (r, g, b) = (Double(pixels[index * 3]), Double(pixels[index * 3 + 1]), Double(pixels[index * 3 + 2]))
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            lumas[index] = luma
            let high = max(r, g, b), low = min(r, g, b)
            saturations[index] = high > 0 ? (high - low) / high : 0
            let band = luma < 0.25 ? 0 : luma < 0.7 ? 1 : 2
            bands[band].rb += r - b
            bands[band].gm += g - (r + b) / 2
            bands[band].n += 1
            if high >= 254.0 / 255 { clipped += 1 }
            if luma <= 2.0 / 255 { crushed += 1 }
        }
        let sortedLuma = lumas.sorted(), sortedSaturation = saturations.sorted()
        let percentile = { (values: [Double], share: Double) in
            values.isEmpty ? 0 : values[min(values.count - 1, Int((Double(values.count - 1) * share).rounded()))] * 100
        }
        let tint = { (band: (rb: Double, gm: Double, n: Int)) -> [Double]? in
            band.n < 20 ? nil : [band.rb / Double(band.n) * 100, band.gm / Double(band.n) * 100]
        }
        let total = Double(max(1, count))
        return Stats(
            black: percentile(sortedLuma, 0.01), p5: percentile(sortedLuma, 0.05), mid: percentile(sortedLuma, 0.5),
            p95: percentile(sortedLuma, 0.95), white: percentile(sortedLuma, 0.99),
            mean: lumas.reduce(0, +) / total * 100, saturation: saturations.reduce(0, +) / total * 100,
            saturationP95: percentile(sortedSaturation, 0.95), tintShadows: tint(bands[0]), tintMids: tint(bands[1]),
            tintHighlights: tint(bands[2]), clipped: Double(clipped) / total, crushed: Double(crushed) / total)
    }

    /// The median of each field over several frames.
    public static func median(_ list: [Stats]) -> Stats? {
        guard let first = list.first else { return nil }
        func middle(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0 : sorted.count % 2 == 1 ? sorted[sorted.count / 2]
                : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        func value(_ path: KeyPath<Stats, Double>) -> Double { middle(list.map { $0[keyPath: path] }) }
        func tint(_ path: KeyPath<Stats, [Double]?>) -> [Double]? {
            let present = list.compactMap { $0[keyPath: path] }
            return present.isEmpty ? nil : [middle(present.map { $0[0] }), middle(present.map { $0[1] })]
        }
        var result = first
        result.black = value(\.black)
        result.p5 = value(\.p5)
        result.mid = value(\.mid)
        result.p95 = value(\.p95)
        result.white = value(\.white)
        result.mean = value(\.mean)
        result.saturation = value(\.saturation)
        result.saturationP95 = value(\.saturationP95)
        result.tintShadows = tint(\.tintShadows)
        result.tintMids = tint(\.tintMids)
        result.tintHighlights = tint(\.tintHighlights)
        result.clipped = value(\.clipped)
        result.crushed = value(\.crushed)
        return result
    }

    /// Mean CIE76 ΔE between two pictures of the same frame, both drawn `width` pixels wide (sizes must match in
    /// shape; the shorter list sets the count).
    public static func deltaE(_ first: CGImage, _ second: CGImage, width: Int = 160) -> Double {
        let a = pixels(first, width: width), b = pixels(second, width: width)
        let count = min(a.count, b.count) / 3
        guard count > 0 else { return 0 }
        var total = 0.0
        for index in 0..<count {
            let left = lab(a, index), right = lab(b, index)
            total += ((left.0 - right.0) * (left.0 - right.0) + (left.1 - right.1) * (left.1 - right.1)
                + (left.2 - right.2) * (left.2 - right.2)).squareRoot()
        }
        return total / Double(count)
    }

    /// CIE L*a*b* (D65) of the encoded sRGB pixel at `index`.
    static func lab(_ pixels: [Float], _ index: Int) -> (Double, Double, Double) {
        let linear = { (value: Float) -> Double in
            let channel = Double(value)
            return channel <= 0.040_45 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let (r, g, b) = (linear(pixels[index * 3]), linear(pixels[index * 3 + 1]), linear(pixels[index * 3 + 2]))
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.950_47
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.088_83
        let f = { (t: Double) in t > 0.008_856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    /// Graded against source: each field's change, clipping and crushing growth, the saturation ratio, the black
    /// lift and the mean ΔE.
    public static func compare(source: Stats, graded: Stats, deltaE: Double?) -> JSONValue {
        let round = { (value: Double) in JSONValue.number((value * 10).rounded() / 10) }
        var result: [String: JSONValue] = [
            "black": round(graded.black - source.black), "mid": round(graded.mid - source.mid),
            "white": round(graded.white - source.white), "saturation": round(graded.saturation - source.saturation),
            "chromaRatio": .number(source.saturation > 0 ? ((graded.saturation / source.saturation) * 100).rounded() / 100 : 0),
            "blackLift": round(graded.black - source.black),
            "clippedGrowth": .number(((graded.clipped - source.clipped) * 1_000).rounded() / 1_000),
            "crushedGrowth": .number(((graded.crushed - source.crushed) * 1_000).rounded() / 1_000),
        ]
        if let mids = graded.tintMids, let before = source.tintMids {
            result["tintMids"] = .array([round(mids[0] - before[0]), round(mids[1] - before[1])])
        }
        if let deltaE { result["meanDeltaE"] = round(deltaE) }
        return .object(result)
    }
}
