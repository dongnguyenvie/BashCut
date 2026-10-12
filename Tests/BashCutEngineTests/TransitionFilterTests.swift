import CoreImage
import Foundation
import Testing
@testable import BashCutEngine

/// The pixel effects of the swing, glitch and halftone transitions.
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

    @Test("Halftone dots stay inside the picture")
    func halftone() {
        let image = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: bounds)
        let dots = BashCutCompositor.halftoned(image, spacing: 8)
        #expect(dots.extent == bounds)
    }
}
