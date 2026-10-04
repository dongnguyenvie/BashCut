import BashCutProject
import CoreGraphics
import CoreImage
import Foundation

/// The part of a video clip's picture it shows (the item's `crop` group): a rectangle of the source frame with
/// optional rounded corners. Sides are fractions of the picture as it is seen (after the source's orientation);
/// the rectangle is kept in the decoded frame's own pixels so it is cut before the clip is placed, and the picture
/// keeps its place in the frame.
public struct SourceCrop: Sendable, Equatable {
    /// In decoded (natural, unoriented) pixels, Core Image coordinates.
    public let rect: CGRect
    /// In the same pixels.
    public let cornerRadius: Double

    /// `orientation` maps decoded pixels to the oriented picture starting at the origin (`ClipPlacement.orientation`);
    /// nil when the item shows the whole frame with square corners.
    public init?(fields: [String: JSONValue], naturalSize: CGSize, orientation: CGAffineTransform) {
        guard case .object(let crop) = fields["crop"] else { return nil }
        let side = { (key: String) in min(0.95, max(0, crop[key]?.double ?? 0)) }
        let radius = min(0.5, max(0, crop["radius"]?.double ?? 0))
        let left = side("left"), right = side("right"), top = side("top"), bottom = side("bottom")
        guard left + right > 0 || top + bottom > 0 || radius > 0 else { return nil }
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(orientation)
        let width = oriented.width, height = oriented.height
        // Core Image's y grows upward: `bottom` is cut from y = 0, `top` from the far edge.
        let visible = CGRect(
            x: oriented.minX + width * left, y: oriented.minY + height * bottom,
            width: width * max(0.05, 1 - left - right), height: height * max(0.05, 1 - top - bottom))
        rect = visible.applying(orientation.inverted()).standardized
        cornerRadius = radius * min(rect.width, rect.height)
    }

    public func apply(to image: CIImage) -> CIImage {
        let cropped = image.cropped(to: rect)
        guard cornerRadius > 0.5 else { return cropped }
        let mask = CIFilter(
            name: "CIRoundedRectangleGenerator",
            parameters: [
                "inputExtent": CIVector(cgRect: rect), "inputRadius": cornerRadius,
                "inputColor": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
            ])?.outputImage
        guard let mask else { return cropped }
        return cropped.applyingFilter(
            "CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask])
    }
}
