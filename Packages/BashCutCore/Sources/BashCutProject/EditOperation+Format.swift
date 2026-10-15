import Foundation

/// `setFormat`: change the output size (for example portrait 1080×1920 to landscape 1920×1080) in an open project.
/// Frame timing, media and items stay as they are. Clip framing offsets (`transform` pan and tilt and their keyframes,
/// in output pixels) scale with the new width and height so each clip keeps the same relative framing; text is already relative.
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
        // A canvas set by hand or by the first clip is final; later clips never change it.
        self["canvasFromFirstClip"] = nil
        guard oldWidth > 0, oldHeight > 0 else { return }
        scaleFramingOffsets(x: Double(width) / oldWidth, y: Double(height) / oldHeight)
    }

    /// Scales every offset kept in output pixels, `transform` pan and tilt and their keyframes, so each picture keeps
    /// its place relative to the frame. An export at another size than the canvas (720p quick draft of a 1080p edit)
    /// applies it too: unscaled, a corner picture-in-picture panned 763 px sat outside a 1280 px frame.
    public mutating func scaleFramingOffsets(x scaleX: Double, y scaleY: Double) {
        guard scaleX != 1 || scaleY != 1, scaleX.isFinite, scaleY.isFinite else { return }
        var tracks = self.tracks
        for track in tracks.indices {
            for item in tracks[track].items.indices {
                if var transform = tracks[track].items[item]["transform"]?.object {
                    if let pan = transform["pan"]?.double { transform["pan"] = .number((pan * scaleX).rounded()) }
                    if let tilt = transform["tilt"]?.double { transform["tilt"] = .number((tilt * scaleY).rounded()) }
                    tracks[track].items[item]["transform"] = .object(transform)
                }
                guard var keyframes = tracks[track].items[item]["keyframes"]?.object else { continue }
                for (property, scale) in [("pan", scaleX), ("tilt", scaleY)] {
                    guard case .array(let keys)? = keyframes[property] else { continue }
                    keyframes[property] = .array(keys.map { key in
                        guard case .object(var fields) = key, let value = fields["value"]?.double else { return key }
                        fields["value"] = .number((value * scale).rounded())
                        return .object(fields)
                    })
                }
                tracks[track].items[item]["keyframes"] = .object(keyframes)
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

extension ProjectSetup.Canvas {
    /// The canvas a picture of this size fits: square within 5%, else landscape or portrait.
    public init(width: Int, height: Int) {
        let ratio = Double(width) / Double(max(1, height))
        self = abs(ratio - 1) < 0.05 ? .square : (ratio > 1 ? .landscape : .portrait)
    }
}

/// The first clip sets the canvas: when an edit puts the first picture (video or image) on a timeline that had none,
/// the project takes that clip's shape, as in Final Cut and Premiere. Only while `canvasFromFirstClip` is set: New
/// Project's Auto frame sets it, and any canvas change clears it, so a canvas chosen on purpose is never replaced.
extension Project {
    /// Whether a video or image clip is on a visual layer; cheap enough to check before every edit.
    public var hasPictureClip: Bool { !placedPictureMedia.isEmpty }

    /// The media of every clip with a picture on a visual layer.
    private var placedPictureMedia: [(item: Item, media: Media)] {
        let media = Dictionary(self.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return tracks.filter(\.isVisual).flatMap(\.items).compactMap { item in
            guard let asset = item.mediaID.flatMap({ media[$0] }), asset.kind != "audio",
                (asset.width ?? 0) > 0, (asset.height ?? 0) > 0
            else { return nil }
            return (item, asset)
        }
    }

    /// The canvas size `next` should take when it holds the first picture clip of this project (the earliest one if
    /// it adds several), keeping this project's short side; nil when the canvas was set on purpose (no
    /// `canvasFromFirstClip`), this project already had a picture clip, or the shape already matches.
    public func formatForFirstClip(in next: Project) -> (canvas: ProjectSetup.Canvas, width: Int, height: Int)? {
        guard canvasFromFirstClip, placedPictureMedia.isEmpty,
            let first = next.placedPictureMedia.min(by: { $0.item.at < $1.item.at }),
            let width = first.media.width, let height = first.media.height
        else { return nil }
        let canvas = ProjectSetup.Canvas(width: width, height: height)
        guard canvas != ProjectSetup.Canvas(width: next.width, height: next.height) else { return nil }
        let size = canvas.dimensions(shortSide: min(next.width, next.height))
        return (canvas, size.width, size.height)
    }
}
