import Foundation

public struct FrameRate: Sendable, Equatable {
    public let numerator: Int
    public let denominator: Int
    public init(_ numerator: Int = 30_000, _ denominator: Int = 1_001) {
        self.numerator = numerator
        self.denominator = denominator
    }
    public var value: Double { Double(numerator) / Double(denominator) }
    public var json: JSONValue { .array([.integer(numerator), .integer(denominator)]) }
    public init(json: JSONValue?) {
        let values = json?.array ?? []
        numerator = values.first?.int ?? 0
        denominator = values.count == 2 ? values[1].int ?? 0 : 0
    }
}

extension Project {
    /// Returns an ephemeral preview copy with color adjustments and LUT references bypassed.
    /// Timing, identities, unknown fields and the stored project remain unchanged.
    public func withoutColorEffects() -> Project {
        var copy = self
        var tracks = copy.tracks
        for trackIndex in tracks.indices {
            var items = tracks[trackIndex].items
            for itemIndex in items.indices {
                items[itemIndex]["color"] = nil
            }
            tracks[trackIndex].items = items
        }
        copy.tracks = tracks
        return copy
    }
}

public struct ReframePreset: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let zoom: Double
    public let pan: Double
    public let tilt: Double

    public static let all: [ReframePreset] = [
        .init(id: "wide", title: "Wide", zoom: 1, pan: 0, tilt: 0),
        .init(id: "medium", title: "Medium", zoom: 1.15, pan: 0, tilt: 0),
        .init(id: "close", title: "Close", zoom: 1.3, pan: 0, tilt: 0),
        .init(id: "left", title: "Left emphasis", zoom: 1.22, pan: -120, tilt: 0),
        .init(id: "right", title: "Right emphasis", zoom: 1.22, pan: 120, tilt: 0),
    ]

    public static func current(for item: Item) -> ReframePreset? {
        let identifier = item["reframePreset"]?.string
        return all.first { $0.id == identifier }
    }

    public static func next(after item: Item) -> ReframePreset {
        guard let current = current(for: item), let index = all.firstIndex(of: current) else {
            return all[0]
        }
        return all[(index + 1) % all.count]
    }

    public var patch: [String: JSONValue] {
        [
            "reframePreset": .string(id),
            "transform": .object([
                "zoom": .number(zoom), "pan": .number(pan), "tilt": .number(tilt),
            ]),
        ]
    }
}

public struct Item: JSONObject, Identifiable {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }
    public init(
        id: String = UUID().uuidString, media: String? = nil, at: Int, duration: Int, sourceIn: Int = 0
    ) {
        fields = [
            "id": .string(id), "at": .integer(at), "dur": .integer(duration), "in": .integer(sourceIn),
        ]
        if let media { fields["media"] = .string(media) }
    }
    public var id: String { fields["id"]?.string ?? "" }
    public var mediaID: String? { fields["media"]?.string }
    public var at: Int {
        get { fields["at"]?.int ?? -1 }
        set { fields["at"] = .integer(newValue) }
    }
    public var duration: Int {
        get { fields["dur"]?.int ?? 0 }
        set { fields["dur"] = .integer(newValue) }
    }
    public var sourceIn: Int {
        get { fields["in"]?.int ?? 0 }
        set { fields["in"] = .integer(newValue) }
    }
    public var end: Int { at + duration }
    public var speed: Double { fields["speed"]?.double ?? 1 }
    public var text: String { fields["text"]?.string ?? "" }
    public var linkedItemID: String? {
        fields["linkedAudio"]?.string ?? fields["linkedVideo"]?.string
    }
}

public struct Media: JSONObject, Identifiable {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }
    public var id: String { fields["id"]?.string ?? "" }
    public var path: String { fields["path"]?.string ?? "" }
    public var kind: String { fields["kind"]?.string ?? "" }
    public var fps: FrameRate { FrameRate(json: fields["fps"]) }
    public var frames: Int { fields["frames"]?.int ?? 0 }
    public var width: Int? { fields["width"]?.int }
    public var height: Int? { fields["height"]?.int }
    public var hasAudio: Bool? {
        guard case .bool(let value) = fields["hasAudio"] else { return nil }
        return value
    }
    public var durationSeconds: Double { Double(frames) / fps.value }
}

public struct Track: JSONObject, Identifiable {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }
    public init(id: String, kind: String, role: String, magnetic: Bool = false) {
        fields = [
            "id": .string(id), "kind": .string(kind), "role": .string(role),
            "magnetic": .bool(magnetic), "items": .array([]),
        ]
    }
    public var id: String { fields["id"]?.string ?? "" }
    public var kind: String { fields["kind"]?.string ?? "" }
    public var role: String { fields["role"]?.string ?? "" }
    public var magnetic: Bool {
        guard case .bool(let value) = fields["magnetic"] else { return false }
        return value
    }
    public var name: String {
        get { fields["name"]?.string ?? role.capitalized }
        set { fields["name"] = .string(newValue) }
    }
    public var items: [Item] {
        get { fields["items"]?.array.map { Item(fields: $0.object) } ?? [] }
        set { fields["items"] = .array(newValue.map { .object($0.fields) }) }
    }
}

public struct TimelineMarker: JSONObject, Identifiable {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }
    public init(id: String = UUID().uuidString, at: Int, kind: String, label: String) {
        fields = [
            "id": .string(id), "at": .integer(at), "kind": .string(kind),
            "label": .string(label),
        ]
    }
    public var id: String {
        fields["id"]?.string
            ?? "\(fields["kind"]?.string ?? "marker")-\(at)-\(label)"
    }
    public var at: Int { fields["at"]?.int ?? -1 }
    public var kind: String { fields["kind"]?.string ?? "" }
    public var label: String { fields["label"]?.string ?? "" }
}

public struct TimelineTransition: JSONObject, Identifiable {
    public static let renderedKinds = ["dissolve", "whip", "blink", "zoom", "spin", "shutter", "wipe"]
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }
    public init(id: String = UUID().uuidString, kind: String, from: String, to: String, duration: Int) {
        fields = [
            "id": .string(id), "kind": .string(kind), "from": .string(from),
            "to": .string(to), "duration": .integer(duration),
        ]
    }
    public var id: String { fields["id"]?.string ?? "" }
    public var kind: String { fields["kind"]?.string ?? "" }
    public var fromItemID: String { fields["from"]?.string ?? "" }
    public var toItemID: String { fields["to"]?.string ?? "" }
    public var duration: Int { fields["duration"]?.int ?? 0 }
}

public struct ColorLUT: JSONObject, Identifiable {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }
    public init(id: String = UUID().uuidString, name: String, path: String, size: Int) {
        fields = [
            "id": .string(id), "name": .string(name), "path": .string(path),
            "size": .integer(size),
        ]
    }
    public var id: String { fields["id"]?.string ?? "" }
    public var name: String { fields["name"]?.string ?? "" }
    public var path: String { fields["path"]?.string ?? "" }
    public var size: Int { fields["size"]?.int ?? 0 }
}

public struct Project: JSONObject {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }
    public init(name: String, fps: FrameRate = FrameRate(), contentLanguage: String = "vi") {
        fields = [
            "schema": .string("bashcut.project/2"), "id": .string(UUID().uuidString),
            "name": .string(name), "rev": .integer(0), "style": .string("food-review"),
            "contentLanguage": .string(contentLanguage), "media": .array([]),
            "format": .object([
                "width": .integer(1080), "height": .integer(1920),
                "fps": fps.json, "sampleRate": .integer(48000),
            ]),
            "transitions": .array([]), "markers": .array([]), "targets": .object([:]),
            "audio": .object(["targetLUFS": .integer(-14), "normalizeEnabled": .bool(true)]),
        ]
        var music = Track(id: "a3", kind: "audio", role: "music")
        music["duckingEnabled"] = .bool(true)
        music["duckUnderSpeechDb"] = .integer(-14)
        music["duckAttackFrames"] = .integer(3)
        music["duckReleaseFrames"] = .integer(8)
        tracks = [
            Track(id: "v1", kind: "video", role: "main", magnetic: true),
            Track(id: "v2", kind: "video", role: "overlay"),
            Track(id: "t1", kind: "text", role: "captions"),
            Track(id: "a1", kind: "audio", role: "dialogue"),
            Track(id: "a2", kind: "audio", role: "voiceover"),
            music,
            Track(id: "a4", kind: "audio", role: "sfx"),
        ]
    }
    public var name: String { fields["name"]?.string ?? "" }
    public var revision: Int {
        get { fields["rev"]?.int ?? -1 }
        set { fields["rev"] = .integer(newValue) }
    }
    public var fps: FrameRate { FrameRate(json: fields["format"]?.object["fps"]) }
    public var width: Int { fields["format"]?.object["width"]?.int ?? 0 }
    public var height: Int { fields["format"]?.object["height"]?.int ?? 0 }
    public var tracks: [Track] {
        get { fields["tracks"]?.array.map { Track(fields: $0.object) } ?? [] }
        set { fields["tracks"] = .array(newValue.map { .object($0.fields) }) }
    }
    public var media: [Media] {
        get { fields["media"]?.array.map { Media(fields: $0.object) } ?? [] }
        set { fields["media"] = .array(newValue.map { .object($0.fields) }) }
    }
    public var markers: [TimelineMarker] {
        get { fields["markers"]?.array.map { TimelineMarker(fields: $0.object) } ?? [] }
        set { fields["markers"] = .array(newValue.map { .object($0.fields) }) }
    }
    public var transitions: [TimelineTransition] {
        get { fields["transitions"]?.array.map { TimelineTransition(fields: $0.object) } ?? [] }
        set { fields["transitions"] = .array(newValue.map { .object($0.fields) }) }
    }
    public var colorLUTs: [ColorLUT] {
        get { fields["luts"]?.array.map { ColorLUT(fields: $0.object) } ?? [] }
        set { fields["luts"] = .array(newValue.map { .object($0.fields) }) }
    }
    public var sectionMarkers: [TimelineMarker] {
        markers.filter { $0.kind == "section" }.sorted { lhs, rhs in
            lhs.at == rhs.at ? lhs.id < rhs.id : lhs.at < rhs.at
        }
    }
    public var duration: Int { tracks.flatMap(\.items).map(\.end).max() ?? 0 }
    public func preferredProvider(for capability: String) -> String? {
        fields["providers"]?.object[capability]?.string
    }
    public var beatFrames: [Int] {
        fields["beatGrid"]?.object["frames"]?.array.compactMap(\.int) ?? []
    }
    public var beatBPM: Double? { fields["beatGrid"]?.object["bpm"]?.double }
    public var targetLUFS: Double { fields["audio"]?.object["targetLUFS"]?.double ?? -14 }
    public var mixGainDb: Double { fields["audio"]?.object["mixGainDb"]?.double ?? 0 }
    public func data() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) throws -> Project {
        var project = try JSONDecoder().decode(Project.self, from: data)
        if project.fields["schema"] == .string("bashcut.project/1") {
            project.fields["schema"] = .string("bashcut.project/2")
            var tracks = project.tracks
            for index in tracks.indices where tracks[index].fields["name"] == nil {
                tracks[index].name = tracks[index].role.capitalized
            }
            project.tracks = tracks
        }
        project = project.normalizingLayers()
        try project.validate()
        return project
    }
}

/// Semantic track roles. Roles are repeatable hints; features look tracks up by role instead of by
/// fixed IDs so renamed, reordered or added layers keep working.
public enum TrackRole {
    public static let main = "main"
    public static let overlay = "overlay"
    public static let captions = "captions"
    public static let dialogue = "dialogue"
    public static let voiceover = "voiceover"
    public static let music = "music"
    public static let sfx = "sfx"
}

extension Project {
    public func track(id: String) -> Track? { tracks.first { $0.id == id } }

    /// The first track with `role` (and `kind`, when given) in stacking order, back to front.
    public func track(role: String, kind: String? = nil) -> Track? {
        tracks.first { $0.role == role && (kind == nil || $0.kind == kind) }
    }

    public func requireTrack(role: String, kind: String? = nil) throws -> Track {
        guard let track = track(role: role, kind: kind) else {
            throw ProjectError.invalid("Add a \(role) track first")
        }
        return track
    }

    /// Magnetic tracks append after their last item; other tracks place at the playhead.
    public func insertionFrame(trackID: String, playhead: Int) -> Int {
        guard let track = track(id: trackID), track.magnetic else { return playhead }
        return track.items.map(\.end).max() ?? 0
    }

    /// Operations that place `media` on a track, spilling onto a free layer when the range is occupied.
    /// Video with sound on a video track also gets a reciprocal linked item on a dialogue layer.
    public func placementOperations(
        media: Media, trackID: String, at frame: Int, duration: Int, itemID: String = UUID().uuidString
    ) throws -> [EditOperation] {
        var planner = LayerPlanner(self)
        try planner.placeMedia(media, on: trackID, at: frame, duration: duration, itemID: itemID)
        return planner.operations
    }
}
