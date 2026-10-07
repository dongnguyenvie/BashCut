import Foundation

/// The one serialized form of an edit: `{"op": "split", "item": "c1", "atFrame": 30, ...}`.
/// Agents, model APIs and the history journal all use it, so adding an operation means one
/// `decode` case and one `json` case here plus its `applying` logic.
extension EditOperation {
    public static let maximumFrame = 2_000_000_000

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
        case "setLinkedAudio": self = .setLinkedAudio(video: try read.string("video"), audio: fields["audio"]?.string)
        case "addMedia": self = .addMedia(Media(fields: try read.object("media")))
        case "addTrack":
            self = .addTrack(track: Track(fields: try read.object("track")), atIndex: try read.index("atIndex"))
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
        case "upsertSection":
            self = .upsertSection(
                id: try read.string("id"), label: try read.string("label"), atFrame: try read.frame("atFrame"))
        case "deleteSection": self = .deleteSection(id: try read.string("id"))
        case "upsertTransition":
            self = .upsertTransition(
                id: try read.string("id"), kind: try read.string("kind"), from: try read.string("from"),
                to: try read.string("to"), duration: try read.frame("duration"), easing: fields["easing"]?.string)
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
        default: throw ProjectError.invalid("Unknown edit operation")
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
        case .setLinkedAudio(let video, let audio):
            return op("setLinkedAudio", ["video": .string(video), "audio": audio.map(JSONValue.string) ?? .null])
        case .addMedia(let media): return op("addMedia", ["media": .object(media.fields)])
        case .addTrack(let track, let index):
            return op("addTrack", ["track": .object(track.fields), "atIndex": .integer(index)])
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
        case .upsertSection(let id, let label, let frame):
            return op("upsertSection", ["id": .string(id), "label": .string(label), "atFrame": .integer(frame)])
        case .deleteSection(let id): return op("deleteSection", ["id": .string(id)])
        case .upsertTransition(let id, let kind, let from, let to, let duration, let easing):
            var fields: [String: JSONValue] = [
                "id": .string(id), "kind": .string(kind), "from": .string(from), "to": .string(to),
                "duration": .integer(duration),
            ]
            if let easing { fields["easing"] = .string(easing) }
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
    func edge() throws -> Edge {
        guard let edge = Edge(rawValue: try string("edge")) else { throw ProjectError.invalid("Invalid edge") }
        return edge
    }
}
