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
    }

    /// The item's own frame at `seconds` of composition time, kept inside the item (a transition's hold after the
    /// end shows the last frame's values).
    public func frame(at seconds: Double) -> Double {
        min(Double(max(0, duration - 1)), max(0, seconds * fps - Double(startFrame)))
    }

    public func value(_ property: String, at seconds: Double) -> Double {
        motion.value(property, at: frame(at: seconds)) ?? base[property] ?? 0
    }

    public func transform(_ placement: ClipPlacement, at seconds: Double) -> CGAffineTransform {
        placement.transform(
            zoom: value("zoom", at: seconds), pan: value("pan", at: seconds), tilt: value("tilt", at: seconds),
            rotation: value("rotation", at: seconds))
    }
}
