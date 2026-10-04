import BashCutProject
import CoreImage
import BashCutTestSupport
import Foundation
import Testing
@testable import BashCutEngine

struct ColorFilterTests {
    private let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6)).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))

    @Test("Neutral grading graph benchmark")
    func neutralBenchmark() {
        let properties: [String: JSONValue] = ["color": .object(["exposure": .number(0), "saturation": .number(1), "contrast": .number(1)])]
        var times: [Double] = []
        for _ in 0..<5 {
            let start = ContinuousClock.now
            for _ in 0..<1_000 { _ = BashCutCompositor.graded(image, properties: properties, lut: nil).extent }
            let elapsed = start.duration(to: .now).components
            times.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        }
        TestMeasurement.report("NEUTRAL_FILTERS 1000_frames_median_ms=\(times.sorted()[2])")
    }

    @Test("Neutral color dictionaries retain the original image without filter nodes")
    func neutralIdentity() {
        for color: [String: JSONValue] in [
            [:], ["exposure": .number(0)], ["saturation": .number(1), "contrast": .number(1)],
            ["lut": .string("catalog-entry"), "lutStrength": .number(0.8)]
        ] {
            #expect(BashCutCompositor.graded(image, properties: ["color": .object(color)], lut: nil) === image)
        }
    }

    @Test("Skipping neutral filters preserves non-neutral grading pixels")
    func pixelParity() {
        let context = CIContext()
        for color: [String: JSONValue] in [
            ["exposure": .number(1.2)], ["saturation": .number(0.3)], ["contrast": .number(1.1)],
            ["exposure": .number(0.5), "saturation": .number(0.8), "contrast": .number(1.4)]
        ] {
            let reference = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: color["exposure"]?.double ?? 0])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: color["saturation"]?.double ?? 1,
                                                              kCIInputContrastKey: color["contrast"]?.double ?? 1])
            let actual = BashCutCompositor.graded(image, properties: ["color": .object(color)], lut: nil)
            var first = [UInt8](repeating: 0, count: 4), second = first
            for (input, target) in [(reference, 0), (actual, 1)] {
                var pixel = [UInt8](repeating: 0, count: 4)
                context.render(input, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                               format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                if target == 0 { first = pixel } else { second = pixel }
            }
            #expect(zip(first, second).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
        }
    }
}
