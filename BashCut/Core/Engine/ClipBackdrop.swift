import BashCutProject
import CoreGraphics
import CoreImage
import Foundation

/// What fills the frame around a clip's picture (the item's `backdrop`, P3-J7): a blurred copy of the same frame
/// scaled to fill, or a colour, drawn under the picture and moving, fading and grading with it. Replaces the
/// duplicate-clip workaround for off-aspect photos and clips.
public struct ClipBackdrop: @unchecked Sendable {
    public enum Kind: Sendable { case blur, color }

    public let kind: Kind
    public let color: CIColor
    /// Blur radius in output pixels.
    public let radius: Double
    /// 0 unchanged … 1 black.
    public let dim: Double
    /// The source frame scaled to fill the canvas and centred.
    public let fill: CGAffineTransform
    public let canvas: CGRect

    /// From the item's fields; nil without a backdrop. `fill` is the source frame's fill placement.
    public init?(fields: [String: JSONValue], fill: CGAffineTransform, canvas: CGSize) {
        guard case .object(let backdrop) = fields["backdrop"] else { return nil }
        switch backdrop["kind"]?.string {
        case "blur": kind = .blur
        case "color": kind = .color
        default: return nil
        }
        let value = UInt32((backdrop["color"]?.string ?? "#000000").dropFirst(), radix: 16) ?? 0
        color = CIColor(
            red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255)
        radius = min(0.5, max(0, backdrop["blur"]?.double ?? 0.05)) * min(canvas.width, canvas.height)
        dim = min(1, max(0, backdrop["dim"]?.double ?? 0))
        self.fill = fill
        self.canvas = CGRect(origin: .zero, size: canvas)
    }

    /// The backdrop for one decoded `source` frame, covering the canvas.
    public func image(source: CIImage) -> CIImage {
        var image: CIImage
        switch kind {
        case .color:
            image = CIImage(color: color)
        case .blur:
            image = source.transformed(by: fill).clampedToExtent()
            if radius >= 0.5 {
                image = image.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).clampedToExtent()
            }
        }
        if dim > 0 {
            let keep = CGFloat(1 - dim)
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: keep, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: keep, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: keep, w: 0),
            ])
        }
        return image.cropped(to: canvas)
    }
}
