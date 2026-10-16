import BashCutProject
import CoreImage
import Foundation

/// Hiding part of a clip (`clip.blur`, `clip.mosaic`): pixelate, blur and feathered edges.
extension BashCutCompositor {
    /// The item's `pixelate` (square cells), then `blur`, then `feather` (edges fading out), each a share of the
    /// picture's short side `side`; kept inside the picture.
    static func obscured(_ image: CIImage, properties: [String: JSONValue], side: Double) -> CIImage {
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite, !extent.isEmpty else { return image }
        var result = image
        if let pixelate = properties["pixelate"]?.double, pixelate * side >= 2 {
            // Shrunk to one pixel a cell (each the average of its area, so thin letters leave no bright cells that
            // still spell them), then grown back without smoothing. CIPixellate takes a cell's middle pixel, and
            // after a blur Core Image halves its cells.
            let cell = min(0.1, pixelate) * side
            let small = result.clampedToExtent()
                .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 1 / cell, kCIInputAspectRatioKey: 1])
                .cropped(to: CGRect(x: 0, y: 0, width: (extent.width / cell).rounded(.up), height: (extent.height / cell).rounded(.up)))
            result = small.samplingNearest().transformed(by: CGAffineTransform(scaleX: cell, y: cell))
                .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)).cropped(to: extent)
        }
        if let blur = properties["blur"]?.double, blur > 0 {
            result = blurred(result, soft: min(0.2, blur) * side, x: 0, y: 0)
        }
        if let feather = properties["feather"]?.double, feather > 0 {
            // A mask that is opaque inside and fades to clear over `feather` of the picture's shorter side.
            let width = min(0.5, feather) * min(extent.width, extent.height)
            let inner = extent.insetBy(dx: width / 2, dy: width / 2)
            if width >= 1, !inner.isEmpty {
                let mask = CIImage(color: .white).cropped(to: inner)
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: width / 5]).cropped(to: extent)
                result = result.applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
                ]).cropped(to: extent)
            }
        }
        return result
    }
}
