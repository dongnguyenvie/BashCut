import CoreImage
import Foundation
import Testing
@testable import BashCutEngine

/// The pixel effects of the swing, glitch, halftone, blur, wipe and shape transitions.
struct TransitionFilterTests {
    private let context = CIContext()
    private let bounds = CGRect(x: 0, y: 0, width: 64, height: 64)

    private func pixel(_ image: CIImage, x: CGFloat, y: CGFloat) -> [Int] {
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return pixel.map(Int.init)
    }

    @Test("An RGB split joins the channels back into the same picture where they line up, and tears them apart at edges")
    func splitChannels() {
        let image = CIImage(color: CIColor(red: 0.75, green: 0.35, blue: 0.5)).cropped(to: bounds)
        let reference = pixel(image, x: 32, y: 32)
        let split = BashCutCompositor.splitChannels(image, offset: 4)
        // Inside: every channel is still there at full brightness (adding them used to darken it to a third).
        #expect(zip(pixel(split, x: 32, y: 32), reference).allSatisfy { abs($0 - $1) <= 1 })
        // The left edge has lost its red (moved right) but keeps green and blue.
        let edge = pixel(split, x: 1, y: 32)
        #expect(edge[0] < 10 && abs(edge[1] - reference[1]) <= 1 && abs(edge[2] - reference[2]) <= 1)
        #expect(split.extent == bounds)
    }

    @Test("A swing keeps the left edge and narrows the frame as it turns away; no turn changes nothing")
    func swing() {
        let image = CIImage(color: .white).cropped(to: bounds)
        let flat = BashCutCompositor.swung(image, degrees: 0, bounds: bounds)
        #expect(abs(flat.extent.width - bounds.width) < 0.5)
        let away = BashCutCompositor.swung(image, degrees: 60, bounds: bounds)
        #expect(abs(away.extent.minX - bounds.minX) < 0.5 && away.extent.width < bounds.width * 0.5)
        #expect(pixel(away, x: 2, y: 32)[3] == 255 && pixel(away, x: 50, y: 32)[3] == 0)
    }

    @Test("Wipes from each edge, the barn door and the shapes show only their share of the frame")
    func reveals() {
        let image = CIImage(color: .white).cropped(to: bounds)
        func alpha(_ property: String, _ share: Double, x: CGFloat, y: CGFloat) -> Int {
            let shown = BashCutCompositor.revealed(image, bounds: bounds) { $0 == property ? share : nil }
            return pixel(shown, x: x, y: y)[3]
        }
        #expect(alpha("revealFromRight", 0.25, x: 60, y: 32) == 255 && alpha("revealFromRight", 0.25, x: 4, y: 32) == 0)
        // Core Image's y runs up: the top edge is maxY.
        #expect(alpha("revealFromTop", 0.25, x: 32, y: 60) == 255 && alpha("revealFromTop", 0.25, x: 32, y: 4) == 0)
        #expect(alpha("revealFromBottom", 0.25, x: 32, y: 4) == 255 && alpha("revealFromBottom", 0.25, x: 32, y: 60) == 0)
        #expect(alpha("revealCenter", 0.25, x: 32, y: 4) == 255 && alpha("revealCenter", 0.25, x: 4, y: 32) == 0)
        #expect(alpha("iris", 0.3, x: 32, y: 32) == 255 && alpha("iris", 0.3, x: 2, y: 2) == 0)
        #expect(alpha("iris", 1, x: 0, y: 0) == 255)
        #expect(alpha("diamond", 0.5, x: 32, y: 32) == 255 && alpha("diamond", 0.5, x: 2, y: 2) == 0)
        #expect(alpha("diamond", 1, x: 1, y: 1) == 255)
        #expect(BashCutCompositor.revealed(image, bounds: bounds) { _ in nil }.extent == bounds)
    }

    @Test("Blurs smear an edge, keep the picture's extent and leave a flat picture as it is")
    func blurs() {
        let half = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 64))
            .composited(over: CIImage(color: .black).cropped(to: bounds))
        let streaked = BashCutCompositor.blurred(half, soft: 0, x: 8, y: 0)
        #expect(streaked.extent == bounds)
        let edge = pixel(streaked, x: 33, y: 32)[0]
        #expect(edge > 20 && edge < 235)
        // Along the edge (vertical blur) nothing changes.
        #expect(pixel(BashCutCompositor.blurred(half, soft: 0, x: 0, y: 8), x: 34, y: 32)[0] < 5)
        #expect(BashCutCompositor.blurred(half, soft: 4, x: 0, y: 0).extent == bounds)
        #expect(BashCutCompositor.blurred(half, soft: 0, x: 0, y: 0) === half)
    }

    @Test("Hue, saturation, zoom blur and kaleidoscope keep the picture's extent; a turned hue changes the colour")
    func styled() {
        let image = CIImage(color: CIColor(red: 0.9, green: 0.2, blue: 0.1)).cropped(to: bounds)
        func styled(_ values: [String: Double]) -> CIImage {
            BashCutCompositor.styled(image, bounds: bounds) { values[$0] }
        }
        let turned = pixel(styled(["hue": 180]), x: 32, y: 32)
        #expect(turned[2] > turned[0])
        let grey = pixel(styled(["saturation": 0]), x: 32, y: 32)
        #expect(abs(grey[0] - grey[1]) <= 2 && abs(grey[1] - grey[2]) <= 2)
        for values in [["zoomBlur": 0.1], ["kaleidoscope": 0.5], [:]] { #expect(styled(values).extent == bounds) }
    }

    @Test("Halftone dots stay inside the picture")
    func halftone() {
        let image = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: bounds)
        let dots = BashCutCompositor.halftoned(image, spacing: 8)
        #expect(dots.extent == bounds)
    }
}
