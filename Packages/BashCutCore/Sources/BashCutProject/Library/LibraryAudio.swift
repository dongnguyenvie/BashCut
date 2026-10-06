import Foundation

/// An audio item's params (#78): what the track is for and what analysis measured. Every field is optional;
/// mood, genre and use are tags.
///
/// `role` is `music`, `sfx` or `ambience`; music and ambience place on the Music layer, sound effects on the SFX layer.
/// Without a role, a file shorter than `sfxSeconds` places as a sound effect and a longer one as music. `seconds` is
/// the file's length, `bpm` its tempo (`beats detect`), `lufs` its integrated loudness and `truePeak` its true peak
/// in dBTP (`audio measure`), and `loopable` says the end joins its start, so placing it longer than the file repeats
/// it. Other keys round-trip.
public struct LibraryAudio: Sendable, Equatable {
    public static let roles = ["music", "sfx", "ambience"]
    public static let bpmRange = 20.0...400.0
    public static let lufsRange = -100.0...10.0
    public static let truePeakRange = -100.0...20.0
    public static let maximumSeconds = 86_400.0
    /// Below this length an item without a role places as a sound effect.
    public static let sfxSeconds = 10.0
    /// The most copies a loopable sound is repeated to fill a placement.
    public static let maximumLoops = 500

    public var role: String?
    public var seconds: Double?
    public var bpm: Double?
    public var loopable: Bool?
    public var lufs: Double?
    public var truePeak: Double?

    public init(
        role: String? = nil, seconds: Double? = nil, bpm: Double? = nil, loopable: Bool? = nil, lufs: Double? = nil,
        truePeak: Double? = nil
    ) {
        self.role = role
        self.seconds = seconds
        self.bpm = bpm
        self.loopable = loopable
        self.lufs = lufs
        self.truePeak = truePeak
    }

    /// Reads and checks `params`; `label` starts each error message.
    public init(params: [String: JSONValue], label: String = "audio item") throws {
        if let value = params["role"] {
            guard let role = value.string, Self.roles.contains(role) else {
                throw ProjectError.invalid("\(label): params.role must be one of \(Self.roles.joined(separator: ", "))")
            }
            self.role = role
        }
        seconds = try Self.number(params, "seconds", in: 0.001...Self.maximumSeconds, label: label)
        bpm = try Self.number(params, "bpm", in: Self.bpmRange, label: label)
        lufs = try Self.number(params, "lufs", in: Self.lufsRange, label: label)
        truePeak = try Self.number(params, "truePeak", in: Self.truePeakRange, label: label)
        if let value = params["loopable"] {
            guard case .bool(let loopable) = value else {
                throw ProjectError.invalid("\(label): params.loopable must be true or false")
            }
            self.loopable = loopable
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

    /// The params as a library item stores them, merged over `params` so unknown keys stay.
    public func params(merging params: [String: JSONValue] = [:]) -> [String: JSONValue] {
        var params = params
        for key in ["role", "seconds", "bpm", "loopable", "lufs", "truePeak"] { params[key] = nil }
        if let role { params["role"] = .string(role) }
        if let seconds { params["seconds"] = Self.rounded(seconds, places: 3) }
        if let bpm { params["bpm"] = Self.rounded(bpm, places: 1) }
        if let loopable { params["loopable"] = .bool(loopable) }
        if let lufs { params["lufs"] = Self.rounded(lufs, places: 1) }
        if let truePeak { params["truePeak"] = Self.rounded(truePeak, places: 1) }
        return params
    }

    private static func rounded(_ value: Double, places: Int) -> JSONValue {
        let scale = pow(10, Double(places))
        let rounded = (value * scale).rounded() / scale
        return rounded == rounded.rounded() && abs(rounded) < 1e15 ? .integer(Int(rounded)) : .number(rounded)
    }

    /// The role a placement uses: the stored one, else by the sound's length.
    public func placementRole(seconds fileSeconds: Double?) -> String {
        if let role { return role }
        guard let length = fileSeconds ?? seconds else { return "music" }
        return length < Self.sfxSeconds ? "sfx" : "music"
    }

    /// The layer role a sound of `role` goes on: the SFX layer, or the Music layer for music and ambience.
    public static func trackRole(_ role: String) -> String { role == "sfx" ? TrackRole.sfx : TrackRole.music }

    /// The project folder a library sound of `role` is copied into.
    public static func projectFolder(_ role: String) -> String { role == "sfx" ? "sfx" : "music" }

    /// The changes `library analyze` saves as a new version: `measured` (seconds, bpm, lufs, truePeak; nil keeps
    /// the stored value) merged over the item's params.
    public static func analysisChanges(_ item: LibraryItem, measured: LibraryAudio) throws -> [String: JSONValue] {
        var audio = try LibraryAudio(params: item.params, label: item.reference)
        audio.seconds = measured.seconds ?? audio.seconds
        audio.bpm = measured.bpm ?? audio.bpm
        audio.lufs = measured.lufs ?? audio.lufs
        audio.truePeak = measured.truePeak ?? audio.truePeak
        return ["params": .object(audio.params(merging: item.params))]
    }

    // MARK: Project copies

    /// The folders library sounds are copied into; a copy in any of them is reused.
    public static let projectFolders = ["music", "sfx"]

    /// `file` when it is inside the project folder `root`, else its copy `<folder>/library-<hash>.<ext>`, named by its
    /// content (`sha256`, or hashed here) so using the same sound again, from any item, reuses one copy.
    public static func projectCopy(of file: URL, root: URL, folder: String, sha256: String? = nil) throws -> URL {
        let resolved = file.standardizedFileURL.resolvingSymlinksInPath().path
        if resolved.hasPrefix(root.standardizedFileURL.resolvingSymlinksInPath().path + "/") { return file }
        let digest = try sha256 ?? LibraryStore.sha256(of: file)
        let suffix = file.pathExtension.isEmpty ? "" : ".\(file.pathExtension.lowercased())"
        let name = "library-\(digest.prefix(16))\(suffix)"
        for existing in ([folder] + projectFolders.filter { $0 != folder }) {
            let candidate = root.appendingPathComponent(existing, isDirectory: true).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        let target = root.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(name)
        try LibraryStore.copy(file, to: target)
        return target
    }
}

/// Where `library place` put an audio item (#78).
public struct AudioPlacement {
    public var planner: LayerPlanner
    /// The timeline items, in order: one, or one per repeat of a loopable sound.
    public var itemIDs: [String]
    public var trackID: String
    /// Frames placed: the asked length, or the file's length when a sound that does not loop is shorter.
    public var duration: Int
    /// Repeated to fill a length longer than the file.
    public var looped: Bool
    /// Asked for longer than the file, but the sound does not loop, so it plays once.
    public var shortened: Bool
}

extension Project {
    /// The plan that places the audio media `sound` (new or already in the project) at `frame` as one edit: on
    /// `trackID`, or the Music layer (music, ambience) or SFX layer (sfx) for `role`, added when missing, or a free
    /// layer beside it. `duration` trims the sound; longer than the file, a `loopable` sound repeats back to back
    /// (the last copy trimmed) and any other sound plays once.
    public func audioPlacePlan(
        _ sound: Media, role: String, loopable: Bool = false, at frame: Int, duration: Int? = nil, trackID: String? = nil
    ) throws -> AudioPlacement {
        guard sound.kind == "audio" else { throw ProjectError.invalid("A library sound must be audio") }
        let length = sound.placementFrames(in: fps)
        guard length > 0 else { throw ProjectError.invalid("The sound is too short") }
        guard frame >= 0 else { throw ProjectError.invalid("The frame must be 0 or later") }
        let asked = duration ?? length
        guard asked > 0 else { throw ProjectError.invalid("The duration must be at least one frame") }
        let looped = asked > length && loopable
        let total = looped ? asked : min(asked, length)
        let copies = (total + length - 1) / length
        guard copies <= LibraryAudio.maximumLoops else {
            throw ProjectError.invalid("Repeating the sound \(copies) times is too many; choose a shorter duration")
        }
        var planner = LayerPlanner(self)
        if !media.contains(where: { $0.id == sound.id }) { try planner.add([.addMedia(sound)]) }
        let layer: String
        if let trackID {
            guard let track = track(id: trackID) else { throw ProjectError.invalid("Unknown track: \(trackID)") }
            guard track.kind == TrackKind.audio else { throw ProjectError.invalid("Layer \(trackID) is not an audio layer") }
            layer = trackID
        } else {
            layer = role == "sfx" ? try planner.sfxTrack() : try planner.musicTrack()
        }
        let target = try planner.freeTrack(near: layer, at: frame, duration: total)
        var itemIDs: [String] = []
        var operations: [EditOperation] = []
        for copy in 0..<copies {
            let start = copy * length
            let item = Item(media: sound.id, at: frame + start, duration: min(length, total - start))
            itemIDs.append(item.id)
            operations.append(.insert(track: target, item: item))
        }
        try planner.add(operations)
        return AudioPlacement(
            planner: planner, itemIDs: itemIDs, trackID: target, duration: total, looped: looped,
            shortened: asked > total)
    }
}

extension LayerPlanner {
    /// The first Music layer, added (named Music, with ducking under speech like a new project's) when the project
    /// has none.
    mutating func musicTrack() throws -> String {
        if let track = project.track(role: TrackRole.music, kind: TrackKind.audio) { return track.id }
        var track = Track(id: project.newTrackID(kind: TrackKind.audio), kind: TrackKind.audio, role: TrackRole.music)
        track.name = "Music"
        track["duckingEnabled"] = .bool(true)
        track["duckUnderSpeechDb"] = .integer(-14)
        track["duckAttackFrames"] = .integer(3)
        track["duckReleaseFrames"] = .integer(8)
        let index = project.track(role: TrackRole.sfx, kind: TrackKind.audio).flatMap { sfx in
            project.tracks.firstIndex { $0.id == sfx.id }
        } ?? project.defaultTrackIndex(kind: TrackKind.audio)
        try add([.addTrack(track: track, atIndex: index)])
        return track.id
    }
}
