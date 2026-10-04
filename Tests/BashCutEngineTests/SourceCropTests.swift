import BashCutProject
import CoreGraphics
import CoreImage
import Foundation
import Testing

@testable import BashCutEngine

struct SourceCropTests {
    private func crop(_ fields: [String: JSONValue], size: CGSize = CGSize(width: 1920, height: 1080),
                      orientation: CGAffineTransform = .identity) -> SourceCrop? {
        SourceCrop(fields: ["crop": .object(fields)], naturalSize: size, orientation: orientation)
    }

    @Test("Sides cut the picture as seen; top is the far edge in Core Image's upward y")
    func sides() throws {
        let cut = try #require(crop(["left": .number(0.25), "right": .number(0.25), "top": .number(0.1)]))
        #expect(cut.rect == CGRect(x: 480, y: 0, width: 960, height: 972))
        #expect(cut.cornerRadius == 0)
        #expect(crop([:]) == nil)
        #expect(SourceCrop(fields: [:], naturalSize: CGSize(width: 10, height: 10), orientation: .identity) == nil)
    }

    @Test("A rotated source is cut in its seen orientation")
    func rotated() throws {
        // A 1920×1080 frame shown portrait: rotate 90° and move back to the origin (1080 wide, 1920 tall when seen).
        let orientation = CGAffineTransform(rotationAngle: .pi / 2).concatenating(CGAffineTransform(translationX: 1080, y: 0))
        let cut = try #require(crop(["top": .number(0.5)], orientation: orientation))
        let seen = cut.rect.applying(orientation)
        #expect(abs(seen.minY) < 0.5 && abs(seen.height - 960) < 0.5 && abs(seen.width - 1080) < 0.5)
    }

    @Test("Rounded corners are transparent and the middle stays")
    func rounded() throws {
        let cut = try #require(crop(["radius": .number(0.5)], size: CGSize(width: 100, height: 100)))
        #expect(cut.cornerRadius == 50)
        let image = cut.apply(to: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100)))
        var pixels = [UInt8](repeating: 0, count: 100 * 100 * 4)
        CIContext().render(
            image, toBitmap: &pixels, rowBytes: 400, bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * 100 + x) * 4 + 3] }
        #expect(alpha(1, 1) == 0 && alpha(98, 98) == 0)
        #expect(alpha(50, 50) == 255)
    }
}
