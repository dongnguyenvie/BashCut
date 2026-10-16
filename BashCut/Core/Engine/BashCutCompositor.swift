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
    /// The build's failure log; the exporter reads it when AVFoundation reports only a generic error.
    public let failures: RenderFailures?
    /// The project frame rate, to name the frame that failed.
    public let fps: Double

    public init(range: CMTimeRange, layers: [VisualLayer], failures: RenderFailures? = nil, fps: Double = 30) {
        timeRange = range
        self.layers = layers
        self.failures = failures
        self.fps = fps
        containsTweening = layers.contains {
            switch $0 {
            case .video(let layer):
                layer.transition != nil || layer.motion != nil || layer.style != nil || layer.appearance != nil
            case .text(let text): text.motion != nil || text.wordStarts != nil || text.style != nil || text.appearance != nil
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
    /// The item's entrance and exit (`enter`, `exit`), played inside the text box.
    public let appearance: ItemAppearance?
    /// `TextRenderer.cacheKey(item)`, made once instead of on every frame.
    let cacheKey: String
    private let anchors = AnchorCache()
    public init(item: Item, motion: LayerMotion? = nil, fps: Double = 30) {
        self.item = item
        self.motion = motion
        self.fps = fps
        appearance = ItemAppearance(item: item)
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
    /// The decoded size and orientation the crop is cut in, when `crop.*` keys change it over time.
    public let animatedCrop: (naturalSize: CGSize, orientation: CGAffineTransform)?
    /// What fills the frame around the picture (`backdrop`); nil leaves it to the layers below.
    public let backdrop: ClipBackdrop?
    /// Keyed `color.*` fields.
    public let style: StyleMotion?
    /// The item and media this layer shows, named when its frame cannot be read.
    public let source: LayerSource?
    /// The item's entrance and exit (`enter`, `exit`), played inside the placed picture.
    public let appearance: ItemAppearance?
    public init(
        trackID: CMPersistentTrackID, transform: CGAffineTransform,
        properties: [String: JSONValue] = [:], transition: RenderTransition? = nil,
        lut: CubeLUT? = nil, motion: (LayerMotion, ClipPlacement)? = nil, crop: SourceCrop? = nil,
        style: StyleMotion? = nil, animatedCrop: (naturalSize: CGSize, orientation: CGAffineTransform)? = nil,
        backdrop: ClipBackdrop? = nil, source: LayerSource? = nil, appearance: ItemAppearance? = nil
    ) {
        self.appearance = appearance
        self.style = style
        self.backdrop = backdrop
        self.animatedCrop = animatedCrop
        self.source = source
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
        guard let instruction = request.videoCompositionInstruction as? FrameInstruction else {
            request.finish(with: NSError(domain: "BashCutCompositor", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Render failed at \(request.compositionTime.seconds) s: no BashCut instruction",
            ]))
            return
        }
        let frame = Int((request.compositionTime.seconds * instruction.fps + 0.001).rounded(.down))
        guard let output = request.renderContext.newPixelBuffer() else {
            fail(request, instruction, RenderFrameError(frame: frame, reason: "no output pixel buffer"), code: 1)
            return
        }
        let size = request.renderContext.size
        let bounds = CGRect(origin: .zero, size: size)
        var image = CIImage(color: .black).cropped(to: bounds)
        for layer in instruction.layers {
            switch layer {
            case .video(let video):
                guard let source = request.sourceFrame(byTrackID: video.trackID) else {
                    fail(request, instruction, RenderFrameError(
                        frame: frame, reason: "source frame missing", source: video.source), code: 2)
                    return
                }
                image = Self.picture(
                    video, source: source, time: request.compositionTime.seconds, bounds: bounds, fps: instruction.fps)
                    .composited(over: image)
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

    /// One clip's picture at `time`: cut (crop, keyed or not), placed, over its backdrop, through its transition,
    /// graded and faded.
    static func picture(_ video: FrameLayer, source: CVPixelBuffer, time: Double, bounds: CGRect, fps: Double = 30)
        -> CIImage
    {
        let motion = video.motion?.0.sample(at: time)
        let transform = video.motion.flatMap { layer in motion?.transform(layer.1) } ?? video.transform
        let decoded = CIImage(cvPixelBuffer: source)
        var sourceImage = decoded
        let properties = video.style?.fields(video.properties, at: time) ?? video.properties
        if let geometry = video.animatedCrop {
            if let crop = SourceCrop(
                fields: properties, naturalSize: geometry.naturalSize, orientation: geometry.orientation) {
                sourceImage = crop.apply(to: sourceImage)
            }
        } else if let crop = video.crop {
            sourceImage = crop.apply(to: sourceImage)
        }
        // `pixelate`, `blur` and `feather` act on what is left after the crop (a cropped copy hides one area of a
        // picture: a mosaic or blur over text, its edges fading into the picture around it).
        sourceImage = Self.obscured(sourceImage, properties: properties, side: min(decoded.extent.width, decoded.extent.height))
        sourceImage = sourceImage.transformed(by: transform)
        // The backdrop is part of the clip's picture: transitions, grade and opacity apply to both.
        if let backdrop = video.backdrop { sourceImage = sourceImage.composited(over: backdrop.image(source: decoded)) }
        var transitionOpacity = 1.0
        if let transition = video.transition {
            (sourceImage, transitionOpacity) = applyTransition(
                to: sourceImage, transition: transition, time: time, bounds: bounds)
        }
        var appearanceOpacity = 1.0
        if let side = video.appearance?.side(at: time * fps) {
            // The picture's own frame: what is placed on the canvas (the whole canvas with a backdrop).
            let frame = sourceImage.extent.intersection(bounds)
            if !frame.isEmpty {
                (sourceImage, appearanceOpacity) = applyMotion(to: sourceImage, bounds: frame) { side.value($0, at: time * fps) }
            }
        }
        sourceImage = Self.graded(sourceImage, properties: properties, lut: video.lut)
        let opacity = (motion?.opacity ?? video.properties["opacity"]?.double ?? 1)
            * transitionOpacity * appearanceOpacity
        if opacity != 1 {
            sourceImage = sourceImage.applyingFilter(
                "CIColorMatrix",
                parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
        }
        return sourceImage
    }

    /// Records `error` in the build's failure log and finishes the request with it.
    private func fail(
        _ request: AVAsynchronousVideoCompositionRequest, _ instruction: FrameInstruction, _ error: RenderFrameError,
        code: Int
    ) {
        instruction.failures?.record(error)
        let domain = code == 2 ? "BashCutCompositor.MissingFrame" : "BashCutCompositor"
        request.finish(with: NSError(domain: domain, code: code, userInfo: error.userInfo))
    }

    /// A text overlay through its entrance or exit inside its own box, then moved by its keyframes: zoom and rotation
    /// around the text's own position, pan and tilt, opacity.
    static func animated(_ overlay: CIImage, text: TextLayer, size: CGSize, time: Double) -> CIImage {
        var overlay = overlay
        let frame = time * text.fps
        if let side = text.appearance?.side(at: frame), !overlay.extent.isEmpty {
            let (shown, opacity) = applyMotion(to: overlay, bounds: overlay.extent) { side.value($0, at: frame) }
            overlay = opacity < 1 ? shown.applyingFilter(
                "CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, opacity))]) : shown
        }
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

    /// The transition's motion at this time (C5: every kind is data). Preview and export share it.
    private static func applyTransition(
        to input: CIImage, transition: RenderTransition, time: Double, bounds: CGRect
    ) -> (CIImage, Double) {
        let progress = transition.progress(at: time)
        let motion = transition.motion ?? TransitionMotion.resolved(kind: transition.kind, motion: nil)
        return applyMotion(to: input, bounds: bounds) { motion.value($0, incoming: transition.incoming, at: progress) }
    }

    /// Transition motion inside `bounds` (the frame for a cut, the item's own frame for its entrance or exit), with
    /// `value` giving each property now: exposure, halftone dots, the RGB split, the blurs, colour and kaleidoscope,
    /// then zoom, horizontal squeeze and rotation around the centre with the pan, the perspective swing about the left
    /// edge, then the reveals and shapes. Returns the picture and the opacity to give it.
    static func applyMotion(
        to input: CIImage, bounds: CGRect, value: (String) -> Double?
    ) -> (CIImage, Double) {
        // Only what is in the frame moves: a filled picture wider than the frame would otherwise still cover it
        // after a whip of one frame width, and a picture zoomed out would show its cut-off sides.
        var image = input.extent.width.isFinite ? input.cropped(to: bounds) : input
        if let exposure = value("exposure"), exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
        }
        if let halftone = value("halftone"), halftone * bounds.width >= 2 {
            image = Self.halftoned(image, spacing: halftone * bounds.width)
        }
        if let split = value("rgbSplit"), split * bounds.width >= 0.5 {
            image = Self.splitChannels(image, offset: split * bounds.width)
        }
        image = Self.blurred(
            image, soft: (value("blur") ?? 0) * bounds.width, x: (value("blurX") ?? 0) * bounds.width,
            y: (value("blurY") ?? 0) * bounds.width)
        image = Self.styled(image, bounds: bounds, value: value)
        let zoom = value("zoom") ?? 1, squeeze = max(0.001, value("scaleX") ?? 1)
        let rotation = (value("rotation") ?? 0) * .pi / 180
        let pan = CGPoint(x: (value("panX") ?? 0) * bounds.width, y: (value("panY") ?? 0) * bounds.height)
        if zoom != 1 || squeeze != 1 || rotation != 0 || pan != .zero {
            image = image.transformed(
                by: CGAffineTransform(translationX: bounds.midX + pan.x, y: bounds.midY + pan.y)
                    .rotated(by: rotation).scaledBy(x: zoom * squeeze, y: zoom)
                    .translatedBy(x: -bounds.midX, y: -bounds.midY))
        }
        if let swing = value("swing"), swing != 0 {
            image = Self.swung(image, degrees: swing, bounds: bounds)
        }
        if let reveal = value("reveal") {
            image = image.cropped(to: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width * reveal, height: bounds.height))
        }
        image = Self.revealed(image, bounds: bounds, value: value)
        let opacity = value("opacity") ?? 1
        return (image, opacity)
    }

    /// Colour print dots `spacing` pixels apart over the picture, cut back to its extent.
    static func halftoned(_ image: CIImage, spacing: Double) -> CIImage {
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite else { return image }
        return image.applyingFilter("CICMYKHalftone", parameters: [
            kCIInputWidthKey: spacing, kCIInputSharpnessKey: 0.7, kCIInputAngleKey: 0.35,
            kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
        ]).cropped(to: extent)
    }

    /// Red moved `offset` pixels right and blue left of green, joined by their maximum (an RGB-split glitch): each
    /// image holds one channel at full alpha, so the maximum is the picture itself where they line up. Adding them
    /// would sum the alphas too and darken the picture to a third.
    static func splitChannels(_ image: CIImage, offset: Double) -> CIImage {
        func channel(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, shift: Double) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: red, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: green, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: blue, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]).transformed(by: CGAffineTransform(translationX: shift, y: 0))
        }
        return channel(1, 0, 0, shift: offset)
            .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: channel(0, 1, 0, shift: 0)])
            .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: channel(0, 0, 1, shift: -offset)])
            .cropped(to: image.extent)
    }

    /// The frame turned `degrees` about its left edge, seen in perspective from a camera 1.5 frame sizes away:
    /// positive takes the right edge away from the viewer, negative brings it closer.
    static func swung(_ image: CIImage, degrees: Double, bounds: CGRect) -> CIImage {
        let angle = min(89, max(-89, degrees)) * .pi / 180
        let distance = 1.5 * max(bounds.width, bounds.height)
        func corner(_ x: CGFloat, _ y: CGFloat) -> CIVector {
            let along = x - bounds.minX, depth = along * sin(angle)
            let scale = distance / (distance + depth)
            return CIVector(x: bounds.minX + along * cos(angle) * scale, y: bounds.midY + (y - bounds.midY) * scale)
        }
        return image.applyingFilter("CIPerspectiveTransformWithExtent", parameters: [
            "inputExtent": CIVector(cgRect: bounds),
            "inputTopLeft": corner(bounds.minX, bounds.maxY), "inputTopRight": corner(bounds.maxX, bounds.maxY),
            "inputBottomLeft": corner(bounds.minX, bounds.minY), "inputBottomRight": corner(bounds.maxX, bounds.minY),
        ])
    }
}
