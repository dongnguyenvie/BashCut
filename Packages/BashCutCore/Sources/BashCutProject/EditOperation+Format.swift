import Foundation

/// `setFormat`: change the output size (for example portrait 1080×1920 to landscape 1920×1080) in an open project.
/// Frame timing, media and items stay as they are. Clip framing offsets (`transform` pan and tilt, in output pixels)
/// scale with the new width and height so each clip keeps the same relative framing; text is already relative.
extension Project {
    public static let formatSizeRange: ClosedRange<Int> = 16...8_192

    mutating func applyFormat(width: Int, height: Int) throws {
        for value in [width, height] {
            guard Self.formatSizeRange.contains(value), value % 2 == 0 else {
                throw ProjectError.invalid(
                    "Width and height must be even numbers of pixels from \(Self.formatSizeRange.lowerBound) to "
                        + "\(Self.formatSizeRange.upperBound)")
            }
        }
        let oldWidth = Double(self.width), oldHeight = Double(self.height)
        var format = self["format"]?.object ?? [:]
        format["width"] = .integer(width)
        format["height"] = .integer(height)
        self["format"] = .object(format)
        guard oldWidth > 0, oldHeight > 0 else { return }
        let scaleX = Double(width) / oldWidth, scaleY = Double(height) / oldHeight
        var tracks = self.tracks
        for track in tracks.indices {
            for item in tracks[track].items.indices {
                guard var transform = tracks[track].items[item]["transform"]?.object else { continue }
                if let pan = transform["pan"]?.double { transform["pan"] = .number((pan * scaleX).rounded()) }
                if let tilt = transform["tilt"]?.double { transform["tilt"] = .number((tilt * scaleY).rounded()) }
                tracks[track].items[item]["transform"] = .object(transform)
            }
        }
        self.tracks = tracks
    }
}

extension ProjectSetup.Canvas {
    /// Width and height of this canvas with `shortSide` pixels on its short side (16:9 for portrait and landscape).
    public func dimensions(shortSide: Int) -> (width: Int, height: Int) {
        let long = shortSide * 16 / 9
        switch self {
        case .portrait: return (shortSide, long)
        case .landscape: return (long, shortSide)
        case .square: return (shortSide, shortSide)
        }
    }
}
