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
    /// A text item's preset from `TextPreset.all`; nil draws Bold Outline.
    public var textPreset: String? { fields["textPreset"]?.string }
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
    /// A still image: held for as long as its items last, up to `Media.imageMaximumSeconds` (its `frames`).
    public var isImage: Bool { kind == "image" }
    public static let imageMaximumSeconds = 3600.0
    /// How long a new placement of an image lasts.
    public static let imageDefaultSeconds = 3.0
    /// Timeline frames a new placement lasts: the whole file, or `imageDefaultSeconds` for an image.
    public func placementFrames(in projectFPS: FrameRate) -> Int {
        if isImage { return Int((Self.imageDefaultSeconds * projectFPS.value).rounded()) }
        return Int((Double(frames) / fps.value * projectFPS.value).rounded(.down))
    }
}

public struct Track: JSONObject, Identifiable {
    /// Every field except a valid `items` array, which is kept typed so item edits mutate in place
    /// instead of re-encoding the whole track.
    private(set) var storage: [String: JSONValue]
    private(set) var hasItems: Bool
    public var items: [Item] { didSet { hasItems = true } }
    init(storage: [String: JSONValue], hasItems: Bool, items: [Item]) {
        self.storage = storage
        self.hasItems = hasItems
        self.items = items
    }
    public init(fields: [String: JSONValue]) {
        var fields = fields
        if case .array(let values) = fields["items"] {
            fields["items"] = nil
            items = values.map { Item(fields: $0.object) }
            hasItems = true
        } else {
            items = []
            hasItems = false
        }
        storage = fields
    }
    /// The track as JSON. Building it encodes every item; read single fields through the subscript.
    public var fields: [String: JSONValue] {
        get {
            var fields = storage
            if hasItems { fields["items"] = .array(items.map { .object($0.fields) }) }
            return fields
        }
        set { self = Track(fields: newValue) }
    }
    public subscript(key: String) -> JSONValue? {
        get { key == "items" ? fields[key] : storage[key] }
        set {
            if key == "items" {
                var fields = fields
                fields[key] = newValue
                self = Track(fields: fields)
            } else {
                storage[key] = newValue
            }
        }
    }
    public init(id: String, kind: String, role: String, magnetic: Bool = false) {
        self.init(fields: [
            "id": .string(id), "kind": .string(kind), "role": .string(role), "name": .string(role.capitalized),
            "magnetic": .bool(magnetic), "items": .array([]),
        ])
    }
    public var id: String { storage["id"]?.string ?? "" }
    public var kind: String { storage["kind"]?.string ?? "" }
    public var role: String { storage["role"]?.string ?? "" }
    public var magnetic: Bool {
        guard case .bool(let value) = storage["magnetic"] else { return false }
        return value
    }
    public var name: String {
        get { storage["name"]?.string ?? "" }
        set { storage["name"] = .string(newValue) }
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
    /// The only schema so far. A breaking change bumps it and adds a migration in `decode`.
    public static let schema = "bashcut.project/1"
    /// Every field except a valid `tracks` array, which is kept typed (down to the items) so an edit
    /// mutates one item in place instead of re-encoding the timeline.
    private(set) var storage: [String: JSONValue] { didSet { knownValid = false } }
    private(set) var hasTracks: Bool
    public var tracks: [Track] {
        didSet {
            hasTracks = true
            knownValid = false
        }
    }
    /// Set once this exact value passed `validate()`; any change clears it, so validating an unchanged
    /// project again (before an edit, when building the preview, when saving) costs nothing.
    private var knownValid = false
    init(storage: [String: JSONValue], hasTracks: Bool, tracks: [Track]) {
        self.storage = storage
        self.hasTracks = hasTracks
        self.tracks = tracks
    }
    public init(fields: [String: JSONValue]) {
        var fields = fields
        if case .array(let values) = fields["tracks"] {
            fields["tracks"] = nil
            tracks = values.map { Track(fields: $0.object) }
            hasTracks = true
        } else {
            tracks = []
            hasTracks = false
        }
        storage = fields
    }
    /// The project as JSON. Building it encodes the whole timeline; read single fields through the subscript.
    public var fields: [String: JSONValue] {
        get {
            var fields = storage
            if hasTracks { fields["tracks"] = .array(tracks.map { .object($0.fields) }) }
            return fields
        }
        set { self = Project(fields: newValue) }
    }
    public static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.hasTracks == rhs.hasTracks && lhs.tracks == rhs.tracks && lhs.storage == rhs.storage
    }
    var isKnownValid: Bool { knownValid }
    mutating func markValid() { knownValid = true }
    public subscript(key: String) -> JSONValue? {
        get { key == "tracks" ? fields[key] : storage[key] }
        set {
            if key == "tracks" {
                var fields = fields
                fields[key] = newValue
                self = Project(fields: fields)
            } else {
                storage[key] = newValue
            }
        }
    }
    public init(name: String, fps: FrameRate = FrameRate(), contentLanguage: String = "vi") {
        self.init(fields: [
            "schema": .string(Self.schema), "id": .string(UUID().uuidString),
            "name": .string(name), "rev": .integer(0),
            "contentLanguage": .string(contentLanguage), "media": .array([]),
            "format": .object([
                "width": .integer(1080), "height": .integer(1920),
                "fps": fps.json, "sampleRate": .integer(48000),
            ]),
            "transitions": .array([]), "markers": .array([]), "targets": .object([:]),
            "audio": .object(["targetLUFS": .integer(-14), "normalizeEnabled": .bool(true)]),
        ])
        var music = Track(id: "a3", kind: "audio", role: "music")
        music["duckingEnabled"] = .bool(true)
        music["duckUnderSpeechDb"] = .integer(-14)
        music["duckAttackFrames"] = .integer(3)
        music["duckReleaseFrames"] = .integer(8)
        hasTracks = true  // `didSet` does not run inside an initializer
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
    public var name: String { storage["name"]?.string ?? "" }
    public var revision: Int {
        get { storage["rev"]?.int ?? -1 }
        set { storage["rev"] = .integer(newValue) }
    }
    public var fps: FrameRate { FrameRate(json: storage["format"]?.object["fps"]) }
    public var width: Int { storage["format"]?.object["width"]?.int ?? 0 }
    public var height: Int { storage["format"]?.object["height"]?.int ?? 0 }
    public var media: [Media] {
        get { storage["media"]?.array.map { Media(fields: $0.object) } ?? [] }
        set { storage["media"] = .array(newValue.map { .object($0.fields) }) }
    }
    public var markers: [TimelineMarker] {
        get { storage["markers"]?.array.map { TimelineMarker(fields: $0.object) } ?? [] }
        set { storage["markers"] = .array(newValue.map { .object($0.fields) }) }
    }
    public var transitions: [TimelineTransition] {
        get { storage["transitions"]?.array.map { TimelineTransition(fields: $0.object) } ?? [] }
        set { storage["transitions"] = .array(newValue.map { .object($0.fields) }) }
    }
    public var colorLUTs: [ColorLUT] {
        get { storage["luts"]?.array.map { ColorLUT(fields: $0.object) } ?? [] }
        set { storage["luts"] = .array(newValue.map { .object($0.fields) }) }
    }
    public var sectionMarkers: [TimelineMarker] {
        markers.filter { $0.kind == "section" }.sorted { lhs, rhs in
            lhs.at == rhs.at ? lhs.id < rhs.id : lhs.at < rhs.at
        }
    }
    public var duration: Int { tracks.flatMap(\.items).map(\.end).max() ?? 0 }
    public func preferredProvider(for capability: String) -> String? {
        storage["providers"]?.object[capability]?.string
    }
    public var beatFrames: [Int] {
        storage["beatGrid"]?.object["frames"]?.array.compactMap(\.int) ?? []
    }
    public var beatBPM: Double? { storage["beatGrid"]?.object["bpm"]?.double }
    /// Whether clips fill the frame (cropping) by default instead of fitting inside it; a clip's `fill` overrides it.
    /// Projects from before the setting existed fill.
    public var clipsFill: Bool { storage["clipFill"] != .bool(false) }
    public func fills(_ item: Item) -> Bool {
        if case .bool(let fill)? = item["fill"] { return fill }
        return clipsFill
    }
    public var targetLUFS: Double { storage["audio"]?.object["targetLUFS"]?.double ?? -14 }
    public var mixGainDb: Double { storage["audio"]?.object["mixGainDb"]?.double ?? 0 }
    public func data() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) throws -> Project {
        var project = try JSONDecoder().decode(Project.self, from: data)
        try ProjectMigration.upgrade(&project)
        project = project.normalizingLayers()
        try project.validate()
        project.markValid()
        return project
    }
}

/// Track kinds. Visual kinds stack back to front above the audio kinds; adding a kind starts here.
public enum TrackKind {
    public static let video = "video"
    public static let adjustment = "adjustment"
    public static let text = "text"
    public static let audio = "audio"
    public static let all = [video, adjustment, text, audio]
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
    public static let adjustment = "adjustment"
    /// The roles BashCut assigns; any other nonempty role is allowed.
    public static let known = [main, overlay, adjustment, captions, dialogue, voiceover, music, sfx]
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
