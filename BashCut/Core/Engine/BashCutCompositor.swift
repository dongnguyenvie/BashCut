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
            case .video(let layer): layer.transition != nil || layer.motion != nil || layer.style != nil
            case .text(let text): text.motion != nil || text.wordStarts != nil || text.style != nil
            case .adjustment(let adjustment): adjustment.style != nil
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
    /// Keyed `textStyle.*` fields; the text is then drawn again for each frame's style.
    public let style: StyleMotion?
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
        style = StyleMotion(item: item, fps: fps)
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
    /// Keyed `color.*` fields.
    public let style: StyleMotion?
    public init(properties: [String: JSONValue], lut: CubeLUT? = nil, style: StyleMotion? = nil) {
        self.properties = properties
        self.lut = lut
        self.style = style
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
    /// The visible part of the source frame, cut before the transform.
    public let crop: SourceCrop?
    /// Keyed `color.*` fields.
    public let style: StyleMotion?
    public init(
        trackID: CMPersistentTrackID, transform: CGAffineTransform,
        properties: [String: JSONValue] = [:], transition: RenderTransition? = nil,
        lut: CubeLUT? = nil, motion: (LayerMotion, ClipPlacement)? = nil, crop: SourceCrop? = nil,
        style: StyleMotion? = nil
    ) {
        self.style = style
        self.trackID = trackID
        self.transform = transform
        self.properties = properties
        self.transition = transition
        self.lut = lut
        self.motion = motion
        self.crop = crop
    }
}

public struct RenderTransition: Sendable, Equatable {
    public let kind: String
    public let startFrame: Int
    public let duration: Int
    public let incoming: Bool
    public let fps: Double
    /// `TimelineTransition.easing`; linear is the straight tween.
    public var easing = TimelineTransition.defaultEasing
    /// `TimelineTransition.motion`; nil draws the built-in row of `kind`.
    public var motion: TransitionMotion?

    /// How far the tween is at `time` seconds, from 0 to 1, shaped by the easing.
    public func progress(at time: Double) -> Double {
        let linear = (time * fps - Double(startFrame)) / Double(duration)
        return TimelineTransition.eased(linear, easing: easing)
    }
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
                let motion = video.motion?.0.sample(at: time)
                let transform = video.motion.flatMap { layer in motion?.transform(layer.1) } ?? video.transform
                var sourceImage = CIImage(cvPixelBuffer: source)
                if let crop = video.crop { sourceImage = crop.apply(to: sourceImage) }
                sourceImage = sourceImage.transformed(by: transform)
                var transitionOpacity = 1.0
                if let transition = video.transition {
                    (sourceImage, transitionOpacity) = applyTransition(
                        to: sourceImage, transition: transition,
                        time: request.compositionTime.seconds, bounds: bounds)
                }
                let properties = video.style?.fields(video.properties, at: time) ?? video.properties
                sourceImage = Self.graded(sourceImage, properties: properties, lut: video.lut)
                let opacity = (motion?.opacity ?? video.properties["opacity"]?.double ?? 1)
                    * transitionOpacity
                if opacity != 1 {
                    sourceImage = sourceImage.applyingFilter(
                        "CIColorMatrix",
                        parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
                }
                image = sourceImage.composited(over: image)
            case .adjustment(let adjustment):
                let properties = adjustment.style?.fields(adjustment.properties, at: request.compositionTime.seconds)
                    ?? adjustment.properties
                image = Self.graded(image, properties: properties, lut: adjustment.lut).cropped(to: bounds)
            case .text(let text):
                let spoken = text.spokenWord(at: request.compositionTime.seconds)
                let styled = text.style.map { Item(fields: $0.fields(text.item.fields, at: request.compositionTime.seconds)) }
                if let overlay = TextRenderer.overlay(
                    styled ?? text.item, size: size, spoken: spoken, itemKey: styled == nil ? text.cacheKey : nil) {
                    image = Self.animated(overlay, text: text, size: size,
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
        let values = motion.sample(at: time)
        let zoom = values.zoom, rotation = values.rotation
        var transform = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
            .concatenating(CGAffineTransform(rotationAngle: rotation * .pi / 180))
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
        transform = transform.concatenating(CGAffineTransform(
            translationX: values.pan, y: values.tilt))
        var image = overlay.transformed(by: transform)
        let opacity = values.opacity
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

    /// The transition's motion at this time (C5: every kind is data): exposure, then zoom, horizontal squeeze and
    /// rotation around the frame centre with the pan, then the reveal from the left. Preview and export share it.
    private func applyTransition(
        to input: CIImage, transition: RenderTransition, time: Double, bounds: CGRect
    ) -> (CIImage, Double) {
        let progress = transition.progress(at: time)
        let motion = transition.motion ?? TransitionMotion.resolved(kind: transition.kind, motion: nil)
        let value = { (property: String) in motion.value(property, incoming: transition.incoming, at: progress) }
        var image = input
        if let exposure = value("exposure"), exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
        }
        let zoom = value("zoom") ?? 1, squeeze = max(0.001, value("scaleX") ?? 1)
        let rotation = (value("rotation") ?? 0) * .pi / 180
        let pan = CGPoint(x: (value("panX") ?? 0) * bounds.width, y: (value("panY") ?? 0) * bounds.height)
        if zoom != 1 || squeeze != 1 || rotation != 0 || pan != .zero {
            image = image.transformed(
                by: CGAffineTransform(translationX: bounds.midX + pan.x, y: bounds.midY + pan.y)
                    .rotated(by: rotation).scaledBy(x: zoom * squeeze, y: zoom)
                    .translatedBy(x: -bounds.midX, y: -bounds.midY))
        }
        if let reveal = value("reveal") {
            image = image.cropped(to: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width * reveal, height: bounds.height))
        }
        let opacity = value("opacity") ?? 1
        return (image, opacity)
    }
}
