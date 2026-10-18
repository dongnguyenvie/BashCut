import Foundation

/// Picture fields and overlays of plan.cut clip, cover and overlay rows (B3).
extension PlanCut {
    /// A picture over a clip on an overlay layer, built with the clip so it moves when the clip does: `media` (the
    /// clip's own by default) from source seconds `from` (for the clip's own media, in sync with the clip by
    /// default), starting `offset` seconds into the clip for `seconds` (the rest of the clip by default).
    public struct Overlay: Sendable {
        public var media: String
        public var from: Double?
        public var offset: Double
        public var seconds: Double?
        public var transform: [String: JSONValue] = [:]
        public var picture: [String: JSONValue] = [:]
        public var focus: Focus?
    }

    static let overlayKeys: Set<String> = ["media", "from", "offset", "seconds"]
    /// Item fields of a picture a clip, cover or overlay row may set (B3); a later apply keeps ones set by hand on
    /// the built items unless the row sets them.
    static let pictureKeys: Set<String> = ["backdrop", "crop", "keyframes", "fill", "color"]

    /// `backdrop`, `crop`, `keyframes`, `color` (objects), `fill` (a boolean) of a clip, cover or overlay; null, or
    /// false for the objects (which a patch keeps, where its null removes the key), is the wish to clear one set by
    /// hand. The item checks the values when it is built.
    static func decodePicture(_ row: [String: JSONValue], entry: String) throws -> [String: JSONValue] {
        var picture: [String: JSONValue] = [:]
        for key in pictureKeys.sorted() {
            guard let given = row[key] else { continue }
            let value: JSONValue = given == .bool(false) && key != "fill" ? .null : given
            let fits: Bool
            switch value {
            case .null: fits = true
            case .bool: fits = key == "fill"
            case .object: fits = key != "fill"
            default: fits = false
            }
            guard fits else {
                let wanted = key == "fill" ? "true, false or null" : "an object, or false or null to clear it"
                throw ProjectError.invalid("\(entry): \(key) must be \(wanted)")
            }
            picture[key] = value
        }
        return picture
    }

    static func decodeCover(_ shot: [String: JSONValue], clip id: String) throws -> Cover {
        guard let media = shot["media"]?.string, let from = shot["from"]?.double, from >= 0 else {
            throw ProjectError.invalid("Clip \(id): each cover needs media and from (source seconds)")
        }
        if let length = shot["seconds"]?.double, length <= 0 { throw ProjectError.invalid("Clip \(id): cover seconds above 0") }
        return Cover(
            media: media, from: from, seconds: shot["seconds"]?.double,
            transform: try decodeTransform(shot, entry: "Clip \(id) cover"), picture: try decodePicture(shot, entry: "Clip \(id) cover"),
            focus: try decodeFocus(shot, entry: "Clip \(id) cover"))
    }

    static func decodeOverlay(_ row: [String: JSONValue], clip id: String, media clipMedia: String) throws -> Overlay {
        let media = row["media"]?.string ?? clipMedia
        let from = row["from"]?.double, offset = row["offset"]?.double ?? 0, seconds = row["seconds"]?.double
        guard !media.isEmpty, from.map({ $0 >= 0 }) ?? (media == clipMedia), offset >= 0, seconds.map({ $0 > 0 }) ?? true else {
            throw ProjectError.invalid(
                "Clip \(id): each overlay needs from (source seconds) unless it shows the clip's own media; offset ≥ 0, seconds above 0")
        }
        return Overlay(
            media: media, from: from, offset: offset, seconds: seconds,
            transform: try decodeTransform(row, entry: "Clip \(id) overlay"), picture: try decodePicture(row, entry: "Clip \(id) overlay"),
            focus: try decodeFocus(row, entry: "Clip \(id) overlay"))
    }

    /// A clip row's overlays; a clip with overlays plays at 1×.
    static func decodeOverlays(_ row: [String: JSONValue], clip id: String, media: String, speed: Double) throws -> [Overlay] {
        let overlays = try (row["overlays"]?.array ?? []).map { try decodeOverlay($0.object, clip: id, media: media) }
        guard overlays.isEmpty || speed == 1 else { throw ProjectError.invalid("Clip \(id): a clip with overlays plays at 1×") }
        return overlays
    }
}
