import Foundation

/// The one serialized form of an edit: `{"op": "split", "item": "c1", "atFrame": 30, ...}`.
/// Agents, model APIs and the history journal all use it, so adding an operation means one
/// `decode` case and one `json` case here plus its `applying` logic.
extension EditOperation {
    public static let maximumFrame = 2_000_000_000
    /// `addTrack`'s index for "in front of the layers of its kind": the top visual layer, or the last sound layer.
    public static let frontLayer = -1
    /// The operation names an agent may send, for error messages.
    public static let agentOperations = [
        "insert", "delete", "split", "trim", "move", "reorder", "slip", "roll", "setProperties", "setSpeed",
        "setSpeedCurve", "setSource", "setLinkedAudio", "addMedia", "addTrack", "deleteTrack", "moveTrack",
        "setTrackProperties", "setProjectProperties", "setFormat", "setProviderPreference", "setBeatGrid",
        "setMediaDescription", "setMediaRights", "setMediaData", "upsertSection", "deleteSection", "upsertTransition",
        "deleteTransition", "addColorLUT", "deleteColorLUT", "rippleDeleteRange",
    ]

    // Decoding stays one exhaustive switch so malformed variants fail at one boundary.
    // swiftlint:disable cyclomatic_complexity
    /// Decodes one operation. `internal` operations (`group`, `restore`) are accepted only from
    /// trusted sources such as the history journal, never from agents.
    public init(json value: JSONValue, allowInternal: Bool = false) throws {
        let fields = value.object
        let read = OperationFields(fields: fields)
        let ripple = fields["ripple"] == .bool(true)
        switch try read.string("op") {
        case "insert": self = .insert(track: try read.string("track"), item: Item(fields: try read.object("item")))
        case "delete": self = .delete(item: try read.string("item"), ripple: ripple)
        case "split":
            self = .split(
                item: try read.string("item"), atFrame: try read.frame("atFrame"),
                newID: fields["newID"]?.string ?? UUID().uuidString)
        case "trim":
            self = .trim(
                item: try read.string("item"), edge: try read.edge(), toFrame: try read.frame("toFrame"),
                ripple: ripple)
        case "move":
            self = .move(
                item: try read.string("item"), toTrack: try read.string("toTrack"), atFrame: try read.frame("atFrame"))
        case "reorder": self = .reorder(item: try read.string("item"), before: fields["before"]?.string)
        case "slip": self = .slip(item: try read.string("item"), sourceIn: try read.frame("sourceIn"))
        case "roll":
            self = .roll(item: try read.string("item"), edge: try read.edge(), toFrame: try read.frame("toFrame"))
        case "setProperties": self = .setProperties(item: try read.string("item"), patch: try read.object("patch"))
        case "setSpeed":
            guard let speed = fields["speed"]?.double else { throw ProjectError.invalid("setSpeed: speed is required") }
            self = .setSpeed(item: try read.string("item"), speed: speed, keepDuration: fields["keepDuration"] == .bool(true))
        case "setSpeedCurve":
            let curve = try fields["points"].flatMap { $0 == .null ? nil : try SpeedCurve(json: $0) }
                ?? fields["preset"]?.string.map { name in
                    guard let preset = SpeedCurve.preset(name) else { throw ProjectError.invalid("Unknown speed curve preset \(name)") }
                    return preset
                }
            self = .setSpeedCurve(item: try read.string("item"), curve: curve, keepDuration: fields["keepDuration"] == .bool(true))
        case "setSource":
            self = .setSource(
                item: try read.string("item"), media: try read.string("media"), sourceIn: try read.frame("sourceIn"),
                reversed: fields["reversed"].flatMap { $0 == .null ? nil : $0 })
        case "rippleDeleteRange": self = try read.rippleDeleteRange()
        case "setLinkedAudio": self = .setLinkedAudio(video: try read.string("video"), audio: fields["audio"]?.string)
        case "addMedia": self = .addMedia(Media(fields: try read.object("media")))
        case "addTrack":
            // Without atIndex the layer goes in front of its kind's layers (#507-19c).
            self = .addTrack(
                track: Track(fields: try read.object("track")),
                atIndex: fields["atIndex"] == nil ? EditOperation.frontLayer : try read.index("atIndex"))
        case "deleteTrack": self = .deleteTrack(track: try read.string("track"))
        case "moveTrack": self = .moveTrack(track: try read.string("track"), toIndex: try read.index("toIndex"))
        case "setTrackProperties":
            self = .setTrackProperties(track: try read.string("track"), patch: try read.object("patch"))
        case "setProjectProperties": self = .setProjectProperties(patch: try read.object("patch"))
        case "setFormat": self = .setFormat(width: try read.size("width"), height: try read.size("height"))
        case "setProviderPreference":
            self = .setProviderPreference(capability: try read.string("capability"), provider: fields["provider"]?.string)
        case "setBeatGrid":
            guard let bpm = fields["bpm"]?.double, case .array(let values) = fields["frames"],
                values.allSatisfy({ $0.int != nil })
            else { throw ProjectError.invalid("bpm and integer frames are required") }
            var provenance: [String: JSONValue]?
            if case .object(let value) = fields["generatedBy"] { provenance = value }
            self = .setBeatGrid(
                media: try read.string("media"), bpm: bpm, frames: values.compactMap(\.int), provenance: provenance)
        case "setMediaDescription":
            let description = fields["description"].flatMap { $0 == .null ? nil : $0 }
            self = .setMediaDescription(media: try read.string("media"), description: description)
        case "setMediaRights":
            self = .setMediaRights(media: try read.string("media"), license: fields["license"], provenance: fields["provenance"])
        case "setMediaData":
            guard case .object(let patch) = fields["patch"] else { throw ProjectError.invalid("patch object is required") }
            self = .setMediaData(media: try read.string("media"), patch: patch)
        case "upsertSection":
            self = .upsertSection(
                id: try read.string("id"), label: try read.string("label"), atFrame: try read.frame("atFrame"))
        case "deleteSection": self = .deleteSection(id: try read.string("id"))
        case "upsertTransition":
            // The id is optional (#507-18): without one the op updates the transition at that cut, or names a new
            // one after it. `between: [from, to]` is the same as from and to.
            let between = fields["between"]?.array.compactMap(\.string) ?? []
            guard fields["between"] == nil || between.count == 2 else {
                throw ProjectError.invalid("between must be the two item ids of the cut, [from, to]")
            }
            guard fields["duration"] != nil else { throw ProjectError.invalid("duration (frames) is required") }
            self = .upsertTransition(
                id: fields["id"]?.string ?? "", kind: try read.string("kind"),
                from: try between.first ?? read.string("from"), to: try between.last ?? read.string("to"),
                duration: try read.frame("duration"), easing: fields["easing"]?.string,
                motion: fields["motion"].flatMap { $0 == .null ? nil : $0 })
        case "deleteTransition": self = .deleteTransition(id: try read.string("id"))
        case "addColorLUT": self = .addColorLUT(ColorLUT(fields: try read.object("lut")))
        case "deleteColorLUT": self = .deleteColorLUT(id: try read.string("id"))
        case "group" where allowInternal:
            guard let author = Author(rawValue: try read.string("author")), case .array(let ops) = fields["ops"] else {
                throw ProjectError.invalid("group requires author and ops")
            }
            self = .group(
                label: try read.string("label"), author: author,
                ops: try ops.map { try EditOperation(json: $0, allowInternal: true) })
        case "restore" where allowInternal: self = .restore(Project(fields: try read.object("project")))
        case let name:
            let known = Self.agentOperations + ["patchItems"]
            let hint = NearestName.nearest(name, in: known).map { "did you mean \($0)? " } ?? ""
            throw ProjectError.invalid(
                "Unknown edit operation \(name): \(hint)use " + known.joined(separator: ", ")
                    + " (setProperties {item, patch} changes one item; patchItems {items or select, patch} many)")
        }
    }

    // swiftlint:enable cyclomatic_complexity

    public var json: JSONValue {
        func op(_ name: String, _ fields: [String: JSONValue]) -> JSONValue {
            .object(fields.merging(["op": .string(name)]) { current, _ in current })
        }
        switch self {
        case .insert(let track, let item): return op("insert", ["track": .string(track), "item": .object(item.fields)])
        case .delete(let item, let ripple): return op("delete", ["item": .string(item), "ripple": .bool(ripple)])
        case .split(let item, let frame, let newID):
            return op("split", ["item": .string(item), "atFrame": .integer(frame), "newID": .string(newID)])
        case .trim(let item, let edge, let frame, let ripple):
            return op("trim", [
                "item": .string(item), "edge": .string(edge.rawValue), "toFrame": .integer(frame), "ripple": .bool(ripple),
            ])
        case .move(let item, let track, let frame):
            return op("move", ["item": .string(item), "toTrack": .string(track), "atFrame": .integer(frame)])
        case .reorder(let item, let before):
            return op("reorder", ["item": .string(item), "before": before.map(JSONValue.string) ?? .null])
        case .slip(let item, let sourceIn): return op("slip", ["item": .string(item), "sourceIn": .integer(sourceIn)])
        case .roll(let item, let edge, let frame):
            return op("roll", ["item": .string(item), "edge": .string(edge.rawValue), "toFrame": .integer(frame)])
        case .setProperties(let item, let patch):
            return op("setProperties", ["item": .string(item), "patch": .object(patch)])
        case .setSpeed(let item, let speed, let keepDuration):
            return op("setSpeed", ["item": .string(item), "speed": .number(speed), "keepDuration": .bool(keepDuration)])
        case .setSpeedCurve(let item, let curve, let keepDuration):
            return op("setSpeedCurve", [
                "item": .string(item), "points": curve?.json ?? .null, "keepDuration": .bool(keepDuration),
            ])
        case .setSource(let item, let media, let sourceIn, let reversed):
            return op("setSource", [
                "item": .string(item), "media": .string(media), "sourceIn": .integer(sourceIn), "reversed": reversed ?? .null,
            ])
        case .rippleDeleteRange(let from, let to, let tracks, let continuous):
            var fields: [String: JSONValue] = ["from": .integer(from), "to": .integer(to)]
            if let tracks { fields["tracks"] = .array(tracks.map(JSONValue.string)) }
            if let continuous { fields["continuous"] = .array(continuous.map(JSONValue.string)) }
            return op("rippleDeleteRange", fields)
        case .setLinkedAudio(let video, let audio):
            return op("setLinkedAudio", ["video": .string(video), "audio": audio.map(JSONValue.string) ?? .null])
        case .addMedia(let media): return op("addMedia", ["media": .object(media.fields)])
        case .addTrack(let track, let index):
            var fields: [String: JSONValue] = ["track": .object(track.fields)]
            if index != EditOperation.frontLayer { fields["atIndex"] = .integer(index) }
            return op("addTrack", fields)
        case .deleteTrack(let track): return op("deleteTrack", ["track": .string(track)])
        case .moveTrack(let track, let index): return op("moveTrack", ["track": .string(track), "toIndex": .integer(index)])
        case .setTrackProperties(let track, let patch):
            return op("setTrackProperties", ["track": .string(track), "patch": .object(patch)])
        case .setProjectProperties(let patch): return op("setProjectProperties", ["patch": .object(patch)])
        case .setFormat(let width, let height):
            return op("setFormat", ["width": .integer(width), "height": .integer(height)])
        case .setProviderPreference(let capability, let provider):
            return op("setProviderPreference", [
                "capability": .string(capability), "provider": provider.map(JSONValue.string) ?? .null,
            ])
        case .setBeatGrid(let media, let bpm, let frames, let provenance):
            return op("setBeatGrid", [
                "media": .string(media), "bpm": .number(bpm), "frames": .array(frames.map(JSONValue.integer)),
                "generatedBy": provenance.map(JSONValue.object) ?? .null,
            ])
        case .setMediaDescription(let media, let description):
            return op("setMediaDescription", ["media": .string(media), "description": description ?? .null])
        case .setMediaRights(let media, let license, let provenance):
            var fields: [String: JSONValue] = ["media": .string(media)]
            if let license { fields["license"] = license }
            if let provenance { fields["provenance"] = provenance }
            return op("setMediaRights", fields)
        case .setMediaData(let media, let patch):
            return op("setMediaData", ["media": .string(media), "patch": .object(patch)])
        case .upsertSection(let id, let label, let frame):
            return op("upsertSection", ["id": .string(id), "label": .string(label), "atFrame": .integer(frame)])
        case .deleteSection(let id): return op("deleteSection", ["id": .string(id)])
        case .upsertTransition(let id, let kind, let from, let to, let duration, let easing, let motion):
            var fields: [String: JSONValue] = [
                "kind": .string(kind), "from": .string(from), "to": .string(to), "duration": .integer(duration),
            ]
            if !id.isEmpty { fields["id"] = .string(id) }
            if let easing { fields["easing"] = .string(easing) }
            if let motion { fields["motion"] = motion }
            return op("upsertTransition", fields)
        case .deleteTransition(let id): return op("deleteTransition", ["id": .string(id)])
        case .addColorLUT(let lut): return op("addColorLUT", ["lut": .object(lut.fields)])
        case .deleteColorLUT(let id): return op("deleteColorLUT", ["id": .string(id)])
        case .group(let label, let author, let ops):
            return op("group", ["label": .string(label), "author": .string(author.rawValue), "ops": .array(ops.map(\.json))])
        case .restore(let project): return op("restore", ["project": .object(project.fields)])
        }
    }

    /// Codable uses the same `"op"` form so the journal and the wire format cannot drift.
    public init(from decoder: any Decoder) throws {
        self = try EditOperation(json: try decoder.singleValueContainer().decode(JSONValue.self), allowInternal: true)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(json)
    }
}

private struct OperationFields {
    let fields: [String: JSONValue]
    func string(_ key: String) throws -> String {
        guard let value = fields[key]?.string, !value.isEmpty else { throw ProjectError.invalid("Missing \(key)") }
        return value
    }
    func frame(_ key: String) throws -> Int {
        guard let value = fields[key]?.int, (0...EditOperation.maximumFrame).contains(value) else {
            throw ProjectError.invalid("\(key) must be an integer frame")
        }
        return value
    }
    func index(_ key: String) throws -> Int {
        guard let value = fields[key]?.int, value >= 0 else {
            throw ProjectError.invalid("\(key) must be a layer position, 0 or more (0 is the back layer)")
        }
        return value
    }
    func size(_ key: String) throws -> Int {
        guard let value = fields[key]?.int, Project.formatSizeRange.contains(value), value % 2 == 0 else {
            throw ProjectError.invalid(
                "\(key) must be an even number of pixels from \(Project.formatSizeRange.lowerBound) to "
                    + "\(Project.formatSizeRange.upperBound)")
        }
        return value
    }
    func object(_ key: String) throws -> [String: JSONValue] {
        guard case .object(let value) = fields[key] else { throw ProjectError.invalid("Missing \(key) object") }
        return value
    }
    func rippleDeleteRange() throws -> EditOperation {
        .rippleDeleteRange(from: try frame("from"), to: try frame("to"), tracks: try layers("tracks"),
                           continuous: try layers("continuous"))
    }
    /// An optional list of layer IDs; null or missing is nil.
    func layers(_ key: String) throws -> [String]? {
        switch fields[key] {
        case nil, .null?: return nil
        case .array(let values)? where values.allSatisfy({ $0.string?.isEmpty == false }):
            return values.compactMap(\.string)
        default: throw ProjectError.invalid("\(key) must be an array of layer IDs")
        }
    }
    func edge() throws -> Edge {
        guard let edge = Edge(rawValue: try string("edge")) else { throw ProjectError.invalid("Invalid edge") }
        return edge
    }
}
