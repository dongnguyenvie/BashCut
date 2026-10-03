import CoreGraphics
import Foundation
import Testing

@testable import BashCutEngine

struct ClipFitTests {
    @Test("A portrait clip fits a landscape frame by its height and fills it by its width")
    func portraitOnLandscape() {
        let portrait = CGSize(width: 1080, height: 1920), landscape = CGSize(width: 1920, height: 1080)
        let fit = CompositionBuilder.baseScale(source: portrait, canvas: landscape, fill: false)
        let fill = CompositionBuilder.baseScale(source: portrait, canvas: landscape, fill: true)
        #expect(abs(1920 * fit - 1080) < 0.001)  // whole height shown, bars at the sides
        #expect(abs(1080 * fill - 1920) < 0.001)  // whole width covered, top and bottom cropped
    }

    @Test("Footage of the frame's shape looks the same either way")
    func sameShape() {
        let size = CGSize(width: 3840, height: 2160), canvas = CGSize(width: 1920, height: 1080)
        #expect(CompositionBuilder.baseScale(source: size, canvas: canvas, fill: false)
            == CompositionBuilder.baseScale(source: size, canvas: canvas, fill: true))
    }
}
