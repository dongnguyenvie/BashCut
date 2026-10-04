import BashCutProject
import CoreGraphics
import Foundation

/// Where a clip's picture sits in the output frame: its oriented size, the base scale (fit or fill) and the item's
/// zoom, pan, tilt and rotation. The compositor asks for the transform at each frame when the item has keyframes.
public struct ClipPlacement: Sendable, Equatable {
    /// Source orientation (the track's preferred transform) moved so the oriented picture starts at the origin.
    public let orientation: CGAffineTransform
    public let size: CGSize
    public let baseScale: Double
    public let canvas: CGSize

    public init(orientation: CGAffineTransform, size: CGSize, baseScale: Double, canvas: CGSize) {
        self.orientation = orientation
        self.size = size
        self.baseScale = baseScale
        self.canvas = canvas
    }

    /// Scaled by `zoom`, centred and offset by `pan`/`tilt` (tilt is up), rotated `rotation` degrees around the frame
    /// centre.
    public func transform(zoom: Double, pan: Double, tilt: Double, rotation: Double) -> CGAffineTransform {
        let scale = CGFloat(baseScale * zoom)
        let x: CGFloat = (canvas.width - size.width * scale) / 2 + CGFloat(pan)
        let y: CGFloat = (canvas.height - size.height * scale) / 2 + CGFloat(tilt)
        var transform = orientation
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y))
        if rotation != 0 {
            transform = transform.concatenating(Self.rotation(rotation, around: CGPoint(x: canvas.width / 2, y: canvas.height / 2)))
        }
        return transform
    }

    static func rotation(_ degrees: Double, around center: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }
}

/// An item's keyframes with what the compositor needs to evaluate them at a composition time.
public struct LayerMotion: Sendable {
    public let motion: ItemMotion
    public let startFrame: Int
    public let duration: Int
    public let fps: Double
    /// The item's static values, for properties without keys.
    public let base: [String: Double]
    private let zoom: PreparedKeyframes
    private let pan: PreparedKeyframes
    private let tilt: PreparedKeyframes
    private let rotation: PreparedKeyframes
    private let opacity: PreparedKeyframes

    public init(motion: ItemMotion, item: Item, fps: Double) {
        self.motion = motion
        startFrame = item.at
        duration = item.duration
        self.fps = fps
        let transform = item["transform"]?.object ?? [:]
        base = [
            "zoom": transform["zoom"]?.double ?? 1, "pan": transform["pan"]?.double ?? 0,
            "tilt": transform["tilt"]?.double ?? 0, "rotation": transform["rotation"]?.double ?? 0,
            "opacity": item["opacity"]?.double ?? 1,
        ]
        zoom = PreparedKeyframes(motion.keys["zoom"] ?? [], fallback: base["zoom"] ?? 1)
        pan = PreparedKeyframes(motion.keys["pan"] ?? [], fallback: base["pan"] ?? 0)
        tilt = PreparedKeyframes(motion.keys["tilt"] ?? [], fallback: base["tilt"] ?? 0)
        rotation = PreparedKeyframes(motion.keys["rotation"] ?? [], fallback: base["rotation"] ?? 0)
        opacity = PreparedKeyframes(motion.keys["opacity"] ?? [], fallback: base["opacity"] ?? 1)
    }

    /// The item's own frame at `seconds` of composition time, kept inside the item (a transition's hold after the
    /// end shows the last frame's values).
    public func frame(at seconds: Double) -> Double {
        min(Double(max(0, duration - 1)), max(0, seconds * fps - Double(startFrame)))
    }

    public func value(_ property: String, at seconds: Double) -> Double {
        let frame = frame(at: seconds)
        switch property {
        case "zoom": return zoom.value(at: frame)
        case "pan": return pan.value(at: frame)
        case "tilt": return tilt.value(at: frame)
        case "rotation": return rotation.value(at: frame)
        case "opacity": return opacity.value(at: frame)
        default: return motion.value(property, at: frame) ?? base[property] ?? 0
        }
    }

    /// Clamp composition time once, with no property-name dictionary lookups in the compositor.
    public func sample(at seconds: Double) -> PictureMotionValues {
        let frame = frame(at: seconds)
        return PictureMotionValues(zoom: zoom.value(at: frame), pan: pan.value(at: frame),
                                   tilt: tilt.value(at: frame), rotation: rotation.value(at: frame),
                                   opacity: opacity.value(at: frame))
    }

    public func transform(_ placement: ClipPlacement, at seconds: Double) -> CGAffineTransform {
        sample(at: seconds).transform(placement)
    }
}

public struct PictureMotionValues: Sendable {
    public let zoom: Double
    public let pan: Double
    public let tilt: Double
    public let rotation: Double
    public let opacity: Double

    public func transform(_ placement: ClipPlacement) -> CGAffineTransform {
        placement.transform(zoom: zoom, pan: pan, tilt: tilt, rotation: rotation)
    }
}
