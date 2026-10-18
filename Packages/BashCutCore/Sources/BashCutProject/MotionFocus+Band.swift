import Foundation

/// The visible band a focus frames into, and the zoom, pan and tilt keys of a focus that moves (`clip motion --focus`,
/// plan.cut `focus` and `focusKeys`).
extension MotionFocus {
    /// Where on the canvas the focused rectangle lands: `auto` (the part no opaque picture on a higher layer covers
    /// edge to edge, such as the bottom half under a camera overlay in a split layout; the whole canvas when nothing
    /// does), `full` (the whole canvas, ignoring overlays), or a region in canvas pixels or shares from the top left.
    public enum Within: Sendable, Equatable {
        case auto
        case full
        case region(Region, fractions: Bool)

        public static let shorthands: [String: Region] = [
            "top-half": Region(x: 0, y: 0, width: 1, height: 0.5),
            "bottom-half": Region(x: 0, y: 0.5, width: 1, height: 0.5),
            "left-half": Region(x: 0, y: 0, width: 0.5, height: 1),
            "right-half": Region(x: 0.5, y: 0, width: 0.5, height: 1),
        ]
        /// The accepted forms, for messages and descriptions.
        public static let summary = "auto, full, " + shorthands.keys.sorted().joined(separator: ", ")
            + " or x,y,width,height (shares 0–1 of the canvas, or canvas pixels)"

        /// `auto`, `full`, a shorthand or `x,y,w,h` (all at most 1: shares of the canvas; else canvas pixels).
        public init(_ text: String) throws {
            let text = text.trimmingCharacters(in: .whitespaces)
            switch text {
            case "auto", "": self = .auto
            case "full": self = .full
            default:
                if let region = Self.shorthands[text] {
                    self = .region(region, fractions: true)
                    return
                }
                let numbers = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                try self.init(numbers: numbers, given: text.split(separator: ",").count)
            }
        }

        /// A string as above, or `[x, y, w, h]`.
        public init(json: JSONValue) throws {
            if let text = json.string {
                try self.init(text)
            } else if case .array(let values) = json {
                try self.init(numbers: values.compactMap(\.double), given: values.count)
            } else {
                throw ProjectError.invalid("within must be \(Self.summary)")
            }
        }

        private init(numbers: [Double], given: Int) throws {
            guard numbers.count == 4, given == 4, numbers.allSatisfy({ $0.isFinite && $0 >= 0 }), numbers[2] > 0,
                numbers[3] > 0
            else { throw ProjectError.invalid("within must be \(Self.summary)") }
            let fractions = numbers.allSatisfy { $0 <= 1 }
            if fractions, numbers[0] + numbers[2] > 1.0001 || numbers[1] + numbers[3] > 1.0001 {
                throw ProjectError.invalid("within: x + width and y + height must stay within 1 (shares of the canvas)")
            }
            self = .region(Region(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]), fractions: fractions)
        }

        /// The band in canvas pixels; nil for `auto` (inferred per frame with `visibleBand`).
        public func band(canvas: (width: Double, height: Double)) -> Region? {
            switch self {
            case .auto: return nil
            case .full: return Region(x: 0, y: 0, width: canvas.width, height: canvas.height)
            case .region(let region, let fractions):
                guard fractions else { return region }
                return Region(
                    x: region.x * canvas.width, y: region.y * canvas.height, width: region.width * canvas.width,
                    height: region.height * canvas.height)
            }
        }
    }

    /// The band of the canvas left visible at timeline `frame` for a picture on track `trackID`: opaque, unrotated
    /// pictures on visible video layers above it that span the canvas edge to edge in one direction and touch one
    /// side cut that side away (a camera across the top half leaves the bottom half). A picture covering the whole
    /// canvas (a full-screen graphic) or a picture-in-picture inside it does not count, and the whole canvas comes
    /// back when what is left is under a tenth of it.
    public static func visibleBand(in project: Project, track trackID: String, at frame: Int) -> Region {
        let width = Double(project.width), height = Double(project.height)
        let full = Region(x: 0, y: 0, width: width, height: height)
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return full }
        var band = Band(width: width, height: height)
        for track in project.tracks[(index + 1)...]
        where track.kind == TrackKind.video && !track.isHidden && !track.isAdjustment {
            for item in track.items where item.at <= frame && frame < item.end {
                if let shown = shownRect(item, in: project, at: Double(frame - item.at)) { band.cutAway(shown) }
            }
        }
        let (top, bottom, left, right) = (band.top, band.bottom, band.left, band.right)
        guard bottom - top >= height / 10, right - left >= width / 10 else { return full }
        func rounded(_ value: Double) -> Double { (value * 10).rounded() / 10 }
        return Region(x: rounded(left), y: rounded(top), width: rounded(right - left), height: rounded(bottom - top))
    }

    /// The canvas left visible while pictures spanning it edge to edge cut sides away.
    struct Band {
        let width: Double
        let height: Double
        var top = 0.0, left = 0.0
        var bottom: Double
        var right: Double
        let tolerance = 0.5

        init(width: Double, height: Double) {
            (self.width, self.height, bottom, right) = (width, height, height, width)
        }

        mutating func cutAway(_ shown: CGRectLike) {
            let spansWidth = shown.x <= tolerance && shown.x + shown.width >= width - tolerance
            let spansHeight = shown.y <= tolerance && shown.y + shown.height >= height - tolerance
            guard spansWidth != spansHeight else { return }
            if spansWidth {
                if shown.y <= tolerance {
                    top = max(top, shown.y + shown.height)
                } else if shown.y + shown.height >= height - tolerance {
                    bottom = min(bottom, shown.y)
                }
            } else if shown.x <= tolerance {
                left = max(left, shown.x + shown.width)
            } else if shown.x + shown.width >= width - tolerance {
                right = min(right, shown.x)
            }
        }
    }

    /// Where an opaque, unrotated picture item shows on the canvas at `local` frames into it (its crop applied),
    /// clipped to the canvas; nil for anything else.
    static func shownRect(_ item: Item, in project: Project, at local: Double) -> CGRectLike? {
        guard let media = project.media.first(where: { $0.id == item.mediaID }),
            media.kind == "video" || media.isImage,
            let placement = PicturePlacement(item, media: media, project: project)
        else { return nil }
        let motion = item.motion
        let transform = item["transform"]?.object ?? [:]
        func value(_ property: String, _ fallback: Double) -> Double {
            motion?.value(property, at: local) ?? transform[property]?.double ?? fallback
        }
        let opacity = motion?.value("opacity", at: local) ?? item["opacity"]?.double ?? 1
        guard opacity >= 0.99, abs(value("rotation", 0).truncatingRemainder(dividingBy: 360)) < 0.01 else { return nil }
        let crop = item["crop"]?.object ?? [:]
        func side(_ key: String) -> Double {
            min(0.95, max(0, motion?.value("crop." + key, at: local) ?? crop[key]?.double ?? 0))
        }
        let picture = placement.frameRect(
            MediaSubjects.Box(x: side("left"), y: side("top"), width: 1 - side("left") - side("right"),
                              height: 1 - side("top") - side("bottom")),
            zoom: value("zoom", 1), pan: value("pan", 0), tilt: value("tilt", 0))
        let left = max(0, picture.x), top = max(0, picture.y)
        let right = min(placement.canvasWidth, picture.x + picture.width)
        let bottom = min(placement.canvasHeight, picture.y + picture.height)
        guard right > left, bottom > top else { return nil }
        return CGRectLike(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// One framing of a focus that moves: held from the previous stop until `depart`, then moving to arrive at
    /// `arrive` (item frames from its start).
    public struct Stop: Sendable, Equatable {
        public var depart: Int
        public var arrive: Int
        public var framing: Framing

        public init(depart: Int, arrive: Int, framing: Framing) {
            self.depart = depart
            self.arrive = arrive
            self.framing = framing
        }
    }

    /// Zoom, pan and tilt keys through `stops` in order: the first framing from its arrival, each later one held
    /// until it departs and eased (`ease`) into the next. A stop departing before the one before it arrived departs
    /// on that arrival.
    public static func keys(_ stops: [Stop], ease: ItemMotion.Ease) -> [String: [ItemMotion.Key]] {
        var keys: [String: [ItemMotion.Key]] = [:]
        for (property, value) in [("zoom", \Framing.zoom), ("pan", \.pan), ("tilt", \.tilt)] {
            var list: [ItemMotion.Key] = []
            for stop in stops {
                guard let last = list.last else {
                    list.append(.init(frame: max(0, stop.arrive), value: stop.framing[keyPath: value], ease: ease))
                    continue
                }
                let depart = max(last.frame, stop.depart)
                if depart > last.frame {
                    list.append(.init(frame: depart, value: last.value, ease: ease))
                } else {
                    list[list.count - 1].ease = ease
                }
                list.append(.init(frame: max(depart + 1, stop.arrive), value: stop.framing[keyPath: value]))
            }
            keys[property] = list
        }
        return keys
    }
}

extension MotionFocus.Region {
    /// `[x, y, width, height]`, for results.
    public var json: JSONValue { .array([x, y, width, height].map(JSONValue.number)) }
}

extension Project {
    /// The focus framing of `rect` (source pixels) for a picture `item` on track `trackID`, inside `within`'s band at
    /// `local` frames into the item (`auto`: the band left visible there), and the band it framed into.
    public func focusFraming(
        _ rect: MotionFocus.Region, item: Item, track trackID: String, within: MotionFocus.Within, at local: Int
    ) throws -> (framing: MotionFocus.Framing, band: MotionFocus.Region) {
        guard let media = media.first(where: { $0.id == item.mediaID }), let mediaWidth = media.width,
            let mediaHeight = media.height
        else { throw ProjectError.invalid("focus frames a video clip or image whose media has a known size") }
        let canvas = (width: Double(width), height: Double(height))
        let band = within.band(canvas: canvas)
            ?? MotionFocus.visibleBand(in: self, track: trackID, at: item.at + min(max(0, local), max(0, item.duration - 1)))
        let framing = try MotionFocus.framing(
            rect, source: (Double(mediaWidth), Double(mediaHeight)), canvas: canvas, fill: fills(item), within: band)
        return (framing, band)
    }
}
