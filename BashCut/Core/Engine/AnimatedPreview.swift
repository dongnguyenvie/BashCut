import CoreGraphics
import Foundation
import ImageIO

/// A library item's looping preview file (an effect preset's saved GIF, P2-B3): its first frame for the still tile,
/// and every frame with the time each shows for the loop a tile plays on hover.
public enum AnimatedPreview {
    /// The first frame, without decoding the rest.
    public static func firstFrame(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Every frame and how long it shows, in seconds (the GIF's delay; 0.1 s when it has none or one under 0.02 s,
    /// as browsers do). A still picture is one frame.
    public static func frames(_ url: URL) -> (images: [CGImage], delay: Double) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return ([], defaultDelay) }
        let images = (0..<CGImageSourceGetCount(source)).compactMap { CGImageSourceCreateImageAtIndex(source, $0, nil) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? defaultDelay
        return (images, delay < 0.02 ? defaultDelay : delay)
    }

    static let defaultDelay = 0.1
}
