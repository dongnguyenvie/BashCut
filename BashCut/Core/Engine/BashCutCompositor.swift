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
            switch $0 {
            case .video(let layer): layer.transition != nil || layer.motion != nil
            case .text(let text): text.motion != nil || text.wordStarts != nil
            case .adjustment: false
            }
        }
        requiredSourceTrackIDs = layers.compactMap {
            guard case .video(let layer) = $0 else { return nil }
            return NSNumber(value: layer.trackID)
        }
    }
}

public enum VisualLayer: @unchecked Sendable {
    case video(FrameLayer)
    /// Grades everything composited below it; `properties` holds the item's `color`.
    case adjustment(AdjustmentLayer)
    case text(TextLayer)
}

/// A caption or title, and its keyframes when it has any.
public struct TextLayer: @unchecked Sendable {
    public let item: Item
    public let motion: LayerMotion?
    /// Word starts (frames from the item's start) when the item shows its words as they are spoken.
    public let wordStarts: [Int]?
    public let fps: Double
    /// `TextRenderer.cacheKey(item)`, made once instead of on every frame.
    let cacheKey: String
    private let anchors = AnchorCache()
    public init(item: Item, motion: LayerMotion? = nil, fps: Double = 30) {
        self.item = item
        self.motion = motion
        self.fps = fps
        wordStarts = item.wordStyle == nil ? nil : item.wordTimings.map(\.at)
        cacheKey = TextRenderer.cacheKey(item)
    }

    /// Where keyframes scale and rotate the text (`TextRenderer.anchor`), laid out once per render size.
    func anchor(size: CGSize) -> CGPoint {
        anchors.value(size: size) { TextRenderer.anchor(item, size: size) }
    }

    /// The word being spoken at `seconds` of composition time.
    func spokenWord(at seconds: Double) -> Int? {
        guard let wordStarts else { return nil }
        let frame = Int((seconds * fps - Double(item.at) + 0.001).rounded(.down))
        return wordStarts.lastIndex { $0 <= frame }
    }
}

/// The last text anchor and the render size it was laid out for; frames render on several threads.
private final class AnchorCache: @unchecked Sendable {
    private let lock = NSLock()
    private var size: CGSize?
    private var point = CGPoint.zero

    func value(size: CGSize, _ make: () -> CGPoint) -> CGPoint {
        lock.lock()
        defer { lock.unlock() }
        if self.size != size {
            point = make()
            self.size = size
        }
        return point
    }
}

public struct AdjustmentLayer: @unchecked Sendable {
    public let properties: [String: JSONValue]
    public let lut: CubeLUT?
    public init(properties: [String: JSONValue], lut: CubeLUT? = nil) {
        self.properties = properties
        self.lut = lut
    }
}

public struct FrameLayer: @unchecked Sendable {
    public let trackID: CMPersistentTrackID
    public let transform: CGAffineTransform
    public let properties: [String: JSONValue]
    public let transition: RenderTransition?
    public let lut: CubeLUT?
    /// Keyframes and the placement they move; `transform` is then only the first frame's.
    public let motion: (LayerMotion, ClipPlacement)?
    public init(
        trackID: CMPersistentTrackID, transform: CGAffineTransform,
        properties: [String: JSONValue] = [:], transition: RenderTransition? = nil,
        lut: CubeLUT? = nil, motion: (LayerMotion, ClipPlacement)? = nil
    ) {
        self.trackID = trackID
        self.transform = transform
        self.properties = properties
        self.transition = transition
        self.lut = lut
        self.motion = motion
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
                let time = request.compositionTime.seconds
                var sourceImage = CIImage(cvPixelBuffer: source).transformed(
                    by: video.motion.map { $0.0.transform($0.1, at: time) } ?? video.transform)
                var transitionOpacity = 1.0
                if let transition = video.transition {
                    (sourceImage, transitionOpacity) = applyTransition(
                        to: sourceImage, transition: transition,
                        time: request.compositionTime.seconds, bounds: bounds)
                }
                sourceImage = Self.graded(sourceImage, properties: video.properties, lut: video.lut)
                let opacity = (video.motion?.0.value("opacity", at: time) ?? video.properties["opacity"]?.double ?? 1)
                    * transitionOpacity
                if opacity != 1 {
                    sourceImage = sourceImage.applyingFilter(
                        "CIColorMatrix",
                        parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
                }
                image = sourceImage.composited(over: image)
            case .adjustment(let adjustment):
                image = Self.graded(image, properties: adjustment.properties, lut: adjustment.lut).cropped(to: bounds)
            case .text(let text):
                let spoken = text.spokenWord(at: request.compositionTime.seconds)
                if let overlay = TextRenderer.image(text.item, size: size, spoken: spoken, itemKey: text.cacheKey) {
                    image = Self.animated(CIImage(cgImage: overlay), text: text, size: size,
                                          time: request.compositionTime.seconds).composited(over: image)
                }
            }
        }
        context.render(
            image.cropped(to: bounds), to: output, bounds: bounds,
            colorSpace: CGColorSpaceCreateDeviceRGB())
        request.finish(withComposedVideoFrame: output)
    }

    /// A text overlay moved by its keyframes: zoom and rotation around the text's own position, pan and tilt, opacity.
    static func animated(_ overlay: CIImage, text: TextLayer, size: CGSize, time: Double) -> CIImage {
        guard let motion = text.motion else { return overlay }
        let anchor = text.anchor(size: size)
        let zoom = motion.value("zoom", at: time), rotation = motion.value("rotation", at: time)
        var transform = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
            .concatenating(CGAffineTransform(rotationAngle: rotation * .pi / 180))
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
        transform = transform.concatenating(CGAffineTransform(
            translationX: motion.value("pan", at: time), y: motion.value("tilt", at: time)))
        var image = overlay.transformed(by: transform)
        let opacity = motion.value("opacity", at: time)
        if opacity < 1 {
            image = image.applyingFilter(
                "CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, opacity))])
        }
        return image
    }

    /// Applies an item's `color` (exposure, saturation, contrast) and its LUT; shared by clips and adjustments.
    static func graded(_ input: CIImage, properties: [String: JSONValue], lut: CubeLUT?) -> CIImage {
        var image = input
        let color = properties["color"]?.object ?? [:]
        let exposure = color["exposure"]?.double ?? 0
        let saturation = color["saturation"]?.double ?? 1
        let contrast = color["contrast"]?.double ?? 1
        if exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
        }
        if saturation != 1 || contrast != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: saturation, kCIInputContrastKey: contrast
            ])
        }
        if let lut { image = lut.apply(to: image, strength: color["lutStrength"]?.double ?? 1) }
        return image
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
