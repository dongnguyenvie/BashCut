import BashCutProject
import CoreGraphics
import Foundation
import Testing

@testable import BashCutEngine

/// Colour as numbers (P0-B8), on generated pictures.
struct ColorMeasureTests {
    /// A picture whose top half is `top` and bottom half `bottom` (sRGB 0–1).
    func picture(top: (Double, Double, Double), bottom: (Double, Double, Double)) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(srgbRed: bottom.0, green: bottom.1, blue: bottom.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        context.setFillColor(CGColor(srgbRed: top.0, green: top.1, blue: top.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 50, width: 100, height: 50))
        return try #require(context.makeImage())
    }

    @Test("Luma percentiles, saturation, tint per band, clipped and crushed shares")
    func stats() throws {
        let grey = ColorMeasure.stats(try picture(top: (0.5, 0.5, 0.5), bottom: (0.5, 0.5, 0.5)))
        #expect(abs(grey.mid - 50.2) < 0.5 && abs(grey.black - grey.white) < 0.01)
        #expect(grey.saturation == 0 && grey.tintMids == [0, 0] && grey.tintShadows == nil)
        let split = ColorMeasure.stats(try picture(top: (1, 1, 1), bottom: (0, 0, 0)))
        #expect(abs(split.clipped - 0.5) < 0.02 && abs(split.crushed - 0.5) < 0.02)
        #expect(split.black < 1 && split.white > 99)
        // Warm mids: R−B 0.4, G−(R+B)/2 −0.05.
        let warm = ColorMeasure.stats(try picture(top: (0.7, 0.45, 0.3), bottom: (0.7, 0.45, 0.3)))
        let tint = try #require(warm.tintMids)
        #expect(abs(tint[0] - 40) < 1 && abs(tint[1] + 5) < 1)
        #expect(warm.saturation > 50)
    }

    @Test("The median of frames, the change a grade makes, and ΔE")
    func compare() throws {
        let before = try picture(top: (0.5, 0.5, 0.5), bottom: (0.2, 0.2, 0.2))
        let after = try picture(top: (0.6, 0.5, 0.4), bottom: (0.25, 0.22, 0.2))
        let a = ColorMeasure.stats(before), b = ColorMeasure.stats(after)
        let change = ColorMeasure.compare(source: a, graded: b, deltaE: ColorMeasure.deltaE(after, before)).object
        #expect((change["black"]?.double ?? 0) > 0 && change["blackLift"] == change["black"])
        #expect((change["meanDeltaE"]?.double ?? 0) > 3)
        #expect(ColorMeasure.deltaE(before, before) == 0)
        let median = try #require(ColorMeasure.median([a, b, b]))
        #expect(median.mid == b.mid)
    }
}
