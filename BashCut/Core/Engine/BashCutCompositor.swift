@preconcurrency import AVFoundation
import BashCutProject
import CoreImage
import CoreText

public final class FrameInstruction: NSObject, AVVideoCompositionInstructionProtocol,
    @unchecked Sendable
{
    public let timeRange: CMTimeRange
    public let enablePostProcessing = true
    public let containsTweening: Bool
    public let requiredSourceTrackIDs: [NSValue]?
    public let passthroughTrackID = kCMPersistentTrackID_Invalid
    public let layers: [VisualLayer]

    public init(range: CMTimeRange, layers: [VisualLayer]) {
        timeRange = range
        self.layers = layers
        containsTweening = layers.contains {
            guard case .video(let layer) = $0 else { return false }
            return layer.transition != nil
        }
        requiredSourceTrackIDs = layers.compactMap {
            guard case .video(let layer) = $0 else { return nil }
            return NSNumber(value: layer.trackID)
        }
    }
}

public enum VisualLayer: @unchecked Sendable {
    case video(FrameLayer)
    case text(Item)
}

public struct FrameLayer: @unchecked Sendable {
    public let trackID: CMPersistentTrackID
    public let transform: CGAffineTransform
    public let properties: [String: JSONValue]
    public let transition: RenderTransition?
    public let lut: CubeLUT?
    public init(
        trackID: CMPersistentTrackID, transform: CGAffineTransform,
        properties: [String: JSONValue] = [:], transition: RenderTransition? = nil,
        lut: CubeLUT? = nil
    ) {
        self.trackID = trackID
        self.transform = transform
        self.properties = properties
        self.transition = transition
        self.lut = lut
    }
}

public struct RenderTransition: Sendable, Equatable {
    public let kind: String
    public let startFrame: Int
    public let duration: Int
    public let incoming: Bool
    public let fps: Double
}

/// The compositor owns no UI state. Each request carries an immutable instruction snapshot.
public final class BashCutCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    public let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    public let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
    ]

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? FrameInstruction,
            let output = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: NSError(domain: "BashCutCompositor", code: 1))
            return
        }
        let size = request.renderContext.size
        let bounds = CGRect(origin: .zero, size: size)
        var image = CIImage(color: .black).cropped(to: bounds)
        for layer in instruction.layers {
            switch layer {
            case .video(let video):
                guard let source = request.sourceFrame(byTrackID: video.trackID) else {
                    request.finish(with: NSError(domain: "BashCutCompositor.MissingFrame", code: 2))
                    return
                }
                var sourceImage = CIImage(cvPixelBuffer: source).transformed(by: video.transform)
                var transitionOpacity = 1.0
                if let transition = video.transition {
                    (sourceImage, transitionOpacity) = applyTransition(
                        to: sourceImage, transition: transition,
                        time: request.compositionTime.seconds, bounds: bounds)
                }
                let color = video.properties["color"]?.object ?? [:]
                if !color.isEmpty {
                    sourceImage = sourceImage.applyingFilter(
                        "CIExposureAdjust", parameters: [kCIInputEVKey: color["exposure"]?.double ?? 0]
                    )
                    .applyingFilter(
                        "CIColorControls",
                        parameters: [
                            kCIInputSaturationKey: color["saturation"]?.double ?? 1,
                            kCIInputContrastKey: color["contrast"]?.double ?? 1,
                        ])
                }
                if let lut = video.lut {
                    sourceImage = lut.apply(
                        to: sourceImage, strength: color["lutStrength"]?.double ?? 1)
                }
                let opacity = (video.properties["opacity"]?.double ?? 1) * transitionOpacity
                if opacity != 1 {
                    sourceImage = sourceImage.applyingFilter(
                        "CIColorMatrix",
                        parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
                }
                image = sourceImage.composited(over: image)
            case .text(let text):
                if let overlay = TextRenderer.image(text, size: size) {
                    image = CIImage(cgImage: overlay).composited(over: image)
                }
            }
        }
        context.render(
            image.cropped(to: bounds), to: output, bounds: bounds,
            colorSpace: CGColorSpaceCreateDeviceRGB())
        request.finish(withComposedVideoFrame: output)
    }

    // Each case is intentionally isolated here so preview and export share identical tween math.
    // swiftlint:disable:next cyclomatic_complexity
    private func applyTransition(
        to input: CIImage, transition: RenderTransition, time: Double, bounds: CGRect
    ) -> (CIImage, Double) {
        let frame = time * transition.fps
        let progress = ((frame - Double(transition.startFrame)) / Double(transition.duration))
            .clamped(to: 0...1)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var image = input
        var opacity = 1.0
        func scale(_ value: Double) {
            image = image.transformed(
                by: CGAffineTransform(translationX: center.x, y: center.y)
                    .scaledBy(x: value, y: value).translatedBy(x: -center.x, y: -center.y))
        }
        switch transition.kind {
        case "whip":
            let offset = transition.incoming ? (1 - progress) * bounds.width : -progress * bounds.width
            image = image.transformed(by: CGAffineTransform(translationX: offset, y: 0))
        case "blink":
            image = image.applyingFilter(
                "CIExposureAdjust", parameters: [kCIInputEVKey: sin(.pi * progress) * 4])
            if transition.incoming { opacity = progress }
        case "zoom":
            scale(transition.incoming ? 1.25 - 0.25 * progress : 1 - 0.1 * progress)
            if transition.incoming { opacity = progress }
        case "spin":
            let angle = transition.incoming ? (1 - progress) * .pi / 2 : -progress * .pi / 2
            image = image.transformed(
                by: CGAffineTransform(translationX: center.x, y: center.y)
                    .rotated(by: angle).translatedBy(x: -center.x, y: -center.y))
            if transition.incoming { opacity = progress }
        case "shutter":
            let amount = max(0.001, transition.incoming ? progress : 1 - progress)
            image = image.transformed(
                by: CGAffineTransform(translationX: center.x, y: 0)
                    .scaledBy(x: amount, y: 1).translatedBy(x: -center.x, y: 0))
        case "wipe":
            if transition.incoming {
                image = image.cropped(
                    to: CGRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height))
            }
        default:
            if transition.incoming { opacity = progress }
        }
        return (image, opacity)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
