import Foundation
import ImageIO

/// A sticker item's params (#64). `stickerKind` is `emoji` (`emoji`, drawn as text with `textPreset`), `image` (a
/// PNG, JPEG, HEIC, WebP… file; transparency kept), `animated` (a GIF, APNG or animated WebP; the engine shows its
/// first frame for now) or `video-alpha` (a movie with an alpha channel: HEVC with alpha or ProRes 4444). Without
/// `stickerKind`, an item with `emoji` is an emoji sticker and one with a file is told by the file's extension.
///
/// Optional placing defaults: `size` (the sticker's width as a fraction of the frame width), `position` (a named
/// spot inside the safe area, `StickerPosition.names`, or `{x, y}`, the sticker's centre in 0–1 of the frame from the
/// top left), `animation` (a `MotionPreset` id) and `seconds` (how long it stays). `width`, `height` and `frames` record
/// what `library add` measured. Other keys round-trip.
public struct LibrarySticker: Sendable, Equatable {
    public static let kinds = ["emoji", "image", "animated", "video-alpha"]
    public static let sizeRange = 0.01...1.0
    public static let secondsRange = 0.05...3_600.0
    /// The width a sticker without a size takes, as a fraction of the frame width.
    public static let defaultSize = 0.3
    /// How long an image sticker without `seconds` stays.
    public static let defaultSeconds = Media.imageDefaultSeconds
    /// The project folder placed stickers are copied into.
    public static let projectFolder = "stickers"

    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp"]
    /// Files that may hold more than one frame.
    public static let animatedExtensions: Set<String> = ["gif", "png", "apng", "webp"]
    public static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    public static let lottieExtensions: Set<String> = ["json", "lottie"]
    public static let lottieMessage =
        "Lottie stickers are not supported; export the animation as a GIF, an animated WebP or a movie with alpha"

    public var stickerKind: String
    public var emoji: String?
    public var size: Double?
    public var position: StickerPosition?
    public var animation: String?
    public var seconds: Double?

    public init(
        stickerKind: String, emoji: String? = nil, size: Double? = nil, position: StickerPosition? = nil,
        animation: String? = nil, seconds: Double? = nil
    ) {
        self.stickerKind = stickerKind
        self.emoji = emoji
        self.size = size
        self.position = position
        self.animation = animation
        self.seconds = seconds
    }

    /// Reads and checks `params` for an item whose file is `file` (a path or name; nil without one).
    public init(params: [String: JSONValue], file: String?, label: String = "sticker") throws {
        let fileKind = try file.map { try Self.kind(ofFile: $0, label: label) }
        if let value = params["stickerKind"] {
            guard let kind = value.string, Self.kinds.contains(kind) else {
                throw ProjectError.invalid("\(label): params.stickerKind must be one of \(Self.kinds.joined(separator: ", "))")
            }
            stickerKind = kind
        } else {
            stickerKind = params["emoji"]?.string?.isEmpty == false ? "emoji" : fileKind ?? "emoji"
        }
        emoji = try Self.checkContent(stickerKind, params: params, fileKind: fileKind, label: label)
        try readDefaults(params, label: label)
    }

    /// Checks that the sticker has what its kind needs: the emoji (returned) and a valid text preset, or a file that
    /// fits the kind.
    private static func checkContent(
        _ stickerKind: String, params: [String: JSONValue], fileKind: String?, label: String
    ) throws -> String? {
        if stickerKind == "emoji" {
            guard let emoji = params["emoji"]?.string, !emoji.isEmpty, emoji.count <= 32 else {
                throw ProjectError.invalid("\(label): an emoji sticker needs params.emoji (1–32 characters)")
            }
            if let preset = params["textPreset"], preset.string.map(TextPreset.all.contains) != true {
                throw ProjectError.invalid(
                    "\(label): params.textPreset must be one of \(TextPreset.all.joined(separator: ", "))")
            }
            return emoji
        }
        guard let fileKind else { throw ProjectError.invalid("\(label): a \(stickerKind) sticker needs a file") }
        // A static image saved as `animated`, or the other way round, is fine: frames tell them apart.
        let fits = stickerKind == "video-alpha" ? fileKind == "video-alpha" : fileKind != "video-alpha"
        guard fits else {
            throw ProjectError.invalid("\(label): a \(stickerKind) sticker cannot use a \(fileKind) file")
        }
        return nil
    }

    /// Reads the optional placing defaults and the measured sizes.
    private mutating func readDefaults(_ params: [String: JSONValue], label: String) throws {
        size = try Self.number(params, "size", in: Self.sizeRange, label: label)
        seconds = try Self.number(params, "seconds", in: Self.secondsRange, label: label)
        if let value = params["position"] {
            position = try StickerPosition(json: value, label: label)
        }
        if let value = params["animation"] {
            guard let id = value.string, id == "none" || MotionPreset.all.contains(where: { $0.id == id }) else {
                let ids = MotionPreset.all.map(\.id).joined(separator: ", ")
                throw ProjectError.invalid("\(label): params.animation must be none or one of \(ids)")
            }
            animation = id == "none" ? nil : id
        }
        for key in ["width", "height", "frames"] {
            guard let value = params[key] else { continue }
            guard let number = value.int, number >= 1, number <= 100_000 else {
                throw ProjectError.invalid("\(label): params.\(key) must be a whole number of 1 or more")
            }
        }
    }

    private static func number(
        _ params: [String: JSONValue], _ key: String, in range: ClosedRange<Double>, label: String
    ) throws -> Double? {
        guard let value = params[key] else { return nil }
        guard let number = value.double, number.isFinite, range.contains(number) else {
            throw ProjectError.invalid("\(label): params.\(key) must be a number in \(range)")
        }
        return number
    }

    /// The sticker kind a file's extension suggests: `image` (also for a GIF, APNG or WebP until its frames are
    /// counted) or `video-alpha`. Lottie and other files are refused.
    public static func kind(ofFile path: String, label: String = "sticker") throws -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if imageExtensions.contains(ext) || ext == "apng" { return "image" }
        if videoExtensions.contains(ext) { return "video-alpha" }
        if lottieExtensions.contains(ext) { throw ProjectError.invalid("\(label): \(lottieMessage)") }
        throw ProjectError.invalid(
            "\(label): a sticker file must be an image (PNG, JPEG, HEIC, WebP, GIF) or a movie with alpha (.mov, .mp4)")
    }

    /// The pixel size and frame count of an image file, or nil when it cannot be read.
    public static func probeImage(_ url: URL) -> (width: Int, height: Int, frames: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let size = orientation >= 5 ? (height, width) : (width, height)
        return (size.0, size.1, CGImageSourceGetCount(source))
    }

    /// The params for an image file: its kind (`animated` when it has more than one frame), size and frame count,
    /// merged over `params`. Throws when the file is not an image or the given kind does not fit it.
    public static func imageParams(_ params: [String: JSONValue], file: URL) throws -> [String: JSONValue] {
        guard let probe = probeImage(file) else {
            throw ProjectError.invalid("\(file.lastPathComponent) is not an image BashCut can read")
        }
        var params = params
        let kind = probe.frames > 1 ? "animated" : "image"
        if let given = params["stickerKind"]?.string, given != "image", given != "animated" {
            throw ProjectError.invalid("\(file.lastPathComponent) is an image, not a \(given) sticker")
        }
        params["stickerKind"] = .string(kind)
        params["width"] = .integer(probe.width)
        params["height"] = .integer(probe.height)
        params["frames"] = probe.frames > 1 ? .integer(probe.frames) : nil
        return params
    }

    /// Whether the sticker is placed as media (not text).
    public var isMedia: Bool { stickerKind != "emoji" }

    /// The params as a library item stores them, merged over `params` so unknown keys stay.
    public func params(merging params: [String: JSONValue] = [:]) -> [String: JSONValue] {
        var params = params
        for key in ["stickerKind", "emoji", "size", "position", "animation", "seconds"] { params[key] = nil }
        params["stickerKind"] = .string(stickerKind)
        if let emoji { params["emoji"] = .string(emoji) }
        if let size { params["size"] = Self.rounded(size) }
        if let position { params["position"] = position.json }
        if let animation { params["animation"] = .string(animation) }
        if let seconds { params["seconds"] = Self.rounded(seconds) }
        return params
    }

    static func rounded(_ value: Double, places: Double = 4) -> JSONValue {
        let scale = pow(10, places)
        let rounded = (value * scale).rounded() / scale
        return rounded == rounded.rounded() && abs(rounded) < 1e15 ? .integer(Int(rounded)) : .number(rounded)
    }
}

/// Where a sticker goes: a named spot inside the safe area, or its centre in 0–1 of the frame from the top left.
public enum StickerPosition: Sendable, Equatable {
    case named(String)
    case point(x: Double, y: Double)

    public static let names = [
        "center", "top", "bottom", "left", "right", "top-left", "top-right", "bottom-left", "bottom-right",
    ]

    public init(json: JSONValue, label: String = "sticker") throws {
        switch json {
        case .string(let text): self = try Self(text: text, label: label)
        case .object(let fields):
            guard let x = fields["x"]?.double, let y = fields["y"]?.double, (0...1).contains(x), (0...1).contains(y) else {
                throw ProjectError.invalid("\(label): params.position {x, y} must be numbers from 0 to 1")
            }
            self = .point(x: x, y: y)
        default:
            throw ProjectError.invalid(Self.message(label))
        }
    }

    /// A name, or `x,y` in 0–1 (`library place --position`).
    public init(text: String, label: String = "sticker") throws {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if Self.names.contains(trimmed) {
            self = .named(trimmed)
            return
        }
        let numbers = trimmed.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 2, let x = numbers[0], let y = numbers[1], (0...1).contains(x), (0...1).contains(y) else {
            throw ProjectError.invalid(Self.message(label))
        }
        self = .point(x: x, y: y)
    }

    private static func message(_ label: String) -> String {
        "\(label): position must be one of \(names.joined(separator: ", ")), or x,y from 0 to 1 (the centre, from the top left)"
    }

    public var json: JSONValue {
        switch self {
        case .named(let name): .string(name)
        case .point(let x, let y): .object(["x": LibrarySticker.rounded(x), "y": LibrarySticker.rounded(y)])
        }
    }

    /// The safe area as 0–1 of the frame (left, top, right, bottom), as the viewer's Safe area overlay draws it:
    /// the central 90% of a landscape or square frame; a vertical frame also leaves the bottom 16% and the right 14%
    /// to the app's buttons and captions.
    public static func safeArea(width: Int, height: Int) -> (left: Double, top: Double, right: Double, bottom: Double) {
        width < height ? (0.05, 0.05, 0.86, 0.84) : (0.05, 0.05, 0.95, 0.95)
    }

    /// The sticker's centre in 0–1 of a `width`×`height` frame for a sticker `stickerWidth`×`stickerHeight` (in 0–1
    /// of the frame): a named spot keeps the sticker inside the safe area, at that edge or corner.
    public func center(stickerWidth: Double, stickerHeight: Double, width: Int, height: Int) -> (x: Double, y: Double) {
        switch self {
        case .point(let x, let y): return (x, y)
        case .named(let name):
            let safe = Self.safeArea(width: width, height: height)
            // The frame's middle unless that would push the sticker out of the safe area.
            func along(_ low: Double, _ high: Double, _ extent: Double, start: Bool, end: Bool) -> Double {
                guard extent < high - low else { return (low + high) / 2 }
                if start { return low + extent / 2 }
                if end { return high - extent / 2 }
                return min(max(0.5, low + extent / 2), high - extent / 2)
            }
            let x = along(safe.left, safe.right, stickerWidth, start: name.hasSuffix("left"), end: name.hasSuffix("right"))
            let y = along(safe.top, safe.bottom, stickerHeight, start: name.hasPrefix("top"), end: name.hasPrefix("bottom"))
            return (x, y)
        }
    }
}

// MARK: Placing

/// Where `library place` put an image, animated or video sticker (#64).
public struct StickerPlacement {
    public var planner: LayerPlanner
    public var itemID: String
    public var trackID: String
    public var duration: Int
    /// Asked for longer than a sticker movie, which plays once.
    public var shortened: Bool
    public var zoom: Double
    public var pan: Double
    public var tilt: Double
}

/// The framing of a sticker picture on the frame, as `transform` zoom, pan and tilt on an item that fits (does not
/// fill) the frame, and back.
public struct StickerFraming: Sendable, Equatable {
    public var pictureWidth: Int
    public var pictureHeight: Int
    public var width: Int
    public var height: Int

    /// A `pictureWidth`×`pictureHeight` picture on a `width`×`height` frame.
    public init(pictureWidth: Int, pictureHeight: Int, width: Int, height: Int) {
        self.pictureWidth = pictureWidth
        self.pictureHeight = pictureHeight
        self.width = width
        self.height = height
    }

    /// How wide the fitted picture is at zoom 1: as wide as the frame, or as tall as it for a narrower picture.
    private var fittedWidth: Double {
        min(Double(width), Double(height) * Double(pictureWidth) / Double(max(1, pictureHeight)))
    }

    /// The sticker's height as a fraction of the frame height when it is `size` of the frame width wide.
    public func stickerHeight(size: Double) -> Double {
        size * Double(width) * Double(max(1, pictureHeight)) / Double(max(1, pictureWidth)) / Double(height)
    }

    /// Zoom, pan and tilt that show the picture `size` of the frame width wide with its centre at `center` (0–1 from
    /// the top left).
    public func transform(size: Double, center: (x: Double, y: Double)) -> (zoom: Double, pan: Double, tilt: Double) {
        let zoomRange = ItemMotion.ranges["zoom"] ?? 0.01...100
        let zoom = min(zoomRange.upperBound, max(zoomRange.lowerBound, size * Double(width) / fittedWidth))
        return (zoom, (center.x - 0.5) * Double(width), (0.5 - center.y) * Double(height))
    }

    /// The sticker's width (fraction of the frame width) and centre for an item's zoom, pan and tilt: the inverse of
    /// `transform`.
    public func placement(zoom: Double, pan: Double, tilt: Double) -> (size: Double, x: Double, y: Double) {
        (zoom * fittedWidth / Double(width), 0.5 + pan / Double(width), 0.5 - tilt / Double(height))
    }
}

extension Project {
    /// The plan that places the image or movie `media` of a sticker (new or already in the project) at `frame` as one
    /// edit: on `trackID`, or the Overlay layer (added when missing) or a free overlay layer beside it, `size` of the
    /// frame width wide at `position`, animated with the sticker's motion preset. An image stays `duration` frames
    /// (the sticker's seconds, or `LibrarySticker.defaultSeconds`); a movie plays once, at most its own length.
    public func stickerPlacePlan(
        _ media: Media, sticker: LibrarySticker, at frame: Int, duration: Int? = nil, position: StickerPosition? = nil,
        size: Double? = nil, trackID: String? = nil
    ) throws -> StickerPlacement {
        guard media.kind == "image" || media.kind == "video" else {
            throw ProjectError.invalid("A sticker's media must be an image or a movie")
        }
        guard frame >= 0 else { throw ProjectError.invalid("The frame must be 0 or later") }
        let length = media.isImage ? media.frames : media.placementFrames(in: fps)
        guard length > 0 else { throw ProjectError.invalid("The sticker is too short") }
        let preferred = sticker.seconds.map { max(1, Int(($0 * fps.value).rounded())) }
        let asked = duration ?? preferred
            ?? (media.isImage ? Int((LibrarySticker.defaultSeconds * fps.value).rounded()) : length)
        guard asked > 0 else { throw ProjectError.invalid("The duration must be at least one frame") }
        let total = min(asked, length)
        let size = size ?? sticker.size ?? LibrarySticker.defaultSize
        guard LibrarySticker.sizeRange.contains(size) else {
            throw ProjectError.invalid("size must be from \(LibrarySticker.sizeRange.lowerBound) to 1 (of the frame width)")
        }
        let picture = StickerFraming(
            pictureWidth: media.width ?? width, pictureHeight: media.height ?? height, width: width, height: height)
        let center = (position ?? sticker.position ?? .named("center"))
            .center(stickerWidth: size, stickerHeight: picture.stickerHeight(size: size), width: width, height: height)
        let framing = picture.transform(size: size, center: center)

        var planner = LayerPlanner(self)
        if !self.media.contains(where: { $0.id == media.id }) { try planner.add([.addMedia(media)]) }
        let layer: String
        if let trackID {
            guard let track = track(id: trackID) else { throw ProjectError.invalid("Unknown track: \(trackID)") }
            guard track.kind == TrackKind.video else { throw ProjectError.invalid("Layer \(trackID) is not a video layer") }
            layer = trackID
        } else {
            layer = try planner.overlayTrack()
        }
        var item = Item(media: media.id, at: frame, duration: total)
        item["fill"] = .bool(false)
        item["transform"] = .object([
            "zoom": LibrarySticker.rounded(framing.zoom), "pan": LibrarySticker.rounded(framing.pan, places: 2),
            "tilt": LibrarySticker.rounded(framing.tilt, places: 2),
        ])
        if let animation = sticker.animation {
            item["keyframes"] = try Self.stickerMotion(animation, duration: total, framing: framing, project: self).json
        }
        let target = try planner.place(item, on: layer)
        return StickerPlacement(
            planner: planner, itemID: item.id, trackID: target, duration: total, shortened: asked > total,
            zoom: framing.zoom, pan: framing.pan, tilt: framing.tilt)
    }

    /// A motion preset around the sticker's own framing: its zoom keys scale the sticker's size and its pan and tilt
    /// keys move it from where it sits, instead of from the frame's full size and centre.
    static func stickerMotion(
        _ id: String, duration: Int, framing: (zoom: Double, pan: Double, tilt: Double), project: Project
    ) throws -> ItemMotion {
        let motion = try MotionPreset.motion(id, duration: duration, width: project.width, height: project.height, fps: project.fps)
        let zoomRange = ItemMotion.ranges["zoom"] ?? 0.01...100
        return ItemMotion(keys: Dictionary(uniqueKeysWithValues: motion.keys.map { property, keys in
            (property, keys.map { key in
                var key = key
                switch property {
                case "zoom": key.value = min(zoomRange.upperBound, max(zoomRange.lowerBound, key.value * framing.zoom))
                case "pan": key.value += framing.pan
                case "tilt": key.value += framing.tilt
                default: break
                }
                return key
            })
        }))
    }
}

extension LayerPlanner {
    /// The first Overlay layer, added (named Overlay) in front of the other video layers when the project has none.
    mutating func overlayTrack() throws -> String {
        if let track = project.track(role: TrackRole.overlay, kind: TrackKind.video) { return track.id }
        var track = Track(id: project.newTrackID(kind: TrackKind.video), kind: TrackKind.video, role: TrackRole.overlay)
        track.name = "Overlay"
        try add([.addTrack(track: track, atIndex: project.defaultTrackIndex(kind: TrackKind.video))])
        return track.id
    }
}
