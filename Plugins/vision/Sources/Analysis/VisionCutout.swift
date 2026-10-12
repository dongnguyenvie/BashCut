import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// The subject of a picture with its background made transparent (Apple Vision's foreground instance mask): a
/// mascot or product shot becomes a sticker. Facts only: how many subjects Vision separated and how much of the
/// picture they cover.
public enum VisionCutout {
    public struct Result: Sendable, Equatable {
        public let width: Int
        public let height: Int
        public let instances: Int
        /// Share of the output's pixels the subject covers (mean alpha, 0…1).
        public let coverage: Double
    }

    /// Writes the cutout of the image at `input` to `output` as PNG; with `crop`, cropped to the subjects.
    public static func cutout(input: URL, output: URL, crop: Bool) throws -> Result {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
        else { throw VisionError("Cannot read the picture") }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation(source))
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw VisionError("No subject was found in the picture")
        }
        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: crop)
        let masked = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(masked, from: masked.extent),
            let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw VisionError("Cannot write the cutout") }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw VisionError("Cannot write the cutout") }
        return Result(
            width: cgImage.width, height: cgImage.height, instances: observation.allInstances.count,
            coverage: meanAlpha(masked, context: context))
    }

    static func orientation(_ source: CGImageSource) -> CGImagePropertyOrientation {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        return CGImagePropertyOrientation(rawValue: raw) ?? .up
    }

    static func meanAlpha(_ image: CIImage, context: CIContext) -> Double {
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent),
        ])
        guard let average = filter?.outputImage else { return 0 }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
            colorSpace: nil)
        return (Double(pixel[3]) / 255 * 1_000).rounded() / 1_000
    }
}
