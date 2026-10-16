import BashCutProject
import CoreImage
import Foundation

/// The blurs, colour, kaleidoscope, wipes and shapes of the transitions (`TransitionMotion`): each is skipped while its value leaves the
/// picture as it is.
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

    /// A soft blur of `soft` pixels, then motion blurs of `x` and `y` pixels along each axis, kept inside the picture.
    static func blurred(_ image: CIImage, soft: Double, x: Double, y: Double) -> CIImage {
        guard soft >= 0.5 || x >= 0.5 || y >= 0.5 else { return image }
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite else { return image }
        var result = image.clampedToExtent()
        if soft >= 0.5 { result = result.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: soft]) }
        if x >= 0.5 {
            result = result.applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: x, kCIInputAngleKey: 0])
        }
        if y >= 0.5 {
            result = result.applyingFilter(
                "CIMotionBlur", parameters: [kCIInputRadiusKey: y, kCIInputAngleKey: Double.pi / 2])
        }
        return result.cropped(to: extent)
    }

    /// The zoom blur out from the centre (`zoomBlur`, a share of the width), the hue turn and saturation, and the
    /// kaleidoscope (six mirrors, turned once at 1, mixed in by its value), kept inside the picture.
    static func styled(_ image: CIImage, bounds: CGRect, value: (String) -> Double?) -> CIImage {
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite else { return image }
        var image = image
        let centre = CIVector(x: bounds.midX, y: bounds.midY)
        if let amount = value("zoomBlur"), amount * bounds.width >= 0.5 {
            image = image.clampedToExtent()
                .applyingFilter("CIZoomBlur", parameters: [kCIInputCenterKey: centre, "inputAmount": amount * bounds.width])
                .cropped(to: extent)
        }
        if let hue = value("hue"), hue != 0 {
            image = image.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: hue * .pi / 180])
        }
        if let saturation = value("saturation"), saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation])
        }
        if let mirror = value("kaleidoscope"), mirror > 0.001 {
            let folded = image.applyingFilter("CIKaleidoscope", parameters: [
                "inputCount": 6, kCIInputCenterKey: centre, kCIInputAngleKey: mirror * 2 * .pi,
            ]).cropped(to: extent)
            image = image.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: folded, kCIInputTimeKey: min(1, mirror * 3),
            ]).cropped(to: extent)
        }
        return image
    }

    /// The wipes from the right, top and bottom, the split from the centre, and the iris and diamond shapes, each a
    /// share of the frame shown (0 = none, 1 = all).
    static func revealed(_ image: CIImage, bounds: CGRect, value: (String) -> Double?) -> CIImage {
        var image = image
        func share(_ property: String) -> CGFloat? { value(property).map { CGFloat(min(1, max(0, $0))) } }
        if let shown = share("revealFromRight") {
            image = image.cropped(to: CGRect(
                x: bounds.maxX - bounds.width * shown, y: bounds.minY, width: bounds.width * shown, height: bounds.height))
        }
        if let shown = share("revealFromTop") {
            image = image.cropped(to: CGRect(
                x: bounds.minX, y: bounds.maxY - bounds.height * shown, width: bounds.width, height: bounds.height * shown))
        }
        if let shown = share("revealFromBottom") {
            image = image.cropped(to: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height * shown))
        }
        if let shown = share("revealCenter") {
            image = image.cropped(to: CGRect(
                x: bounds.midX - bounds.width * shown / 2, y: bounds.minY, width: bounds.width * shown, height: bounds.height))
        }
        // Half the diagonal: a circle or diamond of share 1 covers the corners.
        let reach = hypot(bounds.width, bounds.height) / 2
        if let shown = share("iris") { image = Self.masked(image, by: Self.circle(radius: reach * shown, in: bounds)) }
        if let shown = share("diamond") {
            // A square turned 45° whose half-diagonal reaches the corners when the share is 1.
            let half = (bounds.width + bounds.height) / 2 * shown / sqrt(2)
            let square = CIImage(color: .white).cropped(to: CGRect(x: -half, y: -half, width: 2 * half, height: 2 * half))
                .transformed(by: CGAffineTransform(translationX: bounds.midX, y: bounds.midY).rotated(by: .pi / 4))
            image = Self.masked(image, by: square)
        }
        return image
    }

    /// An opaque disc of `radius` pixels around the centre of `bounds`.
    static func circle(radius: CGFloat, in bounds: CGRect) -> CIImage {
        CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: bounds.midX, y: bounds.midY),
            "inputRadius0": max(0, radius - 0.5), "inputRadius1": max(0.5, radius + 0.5),
            "inputColor0": CIColor.white, "inputColor1": CIColor.clear,
        ])?.outputImage?.cropped(to: bounds) ?? CIImage.empty()
    }

    /// `image` only where `mask` is opaque.
    static func masked(_ image: CIImage, by mask: CIImage) -> CIImage {
        image.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: mask])
            .cropped(to: image.extent)
    }
}
