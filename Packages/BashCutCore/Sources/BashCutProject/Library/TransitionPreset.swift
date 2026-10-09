import Foundation

/// A transition preset's params (#77): kind + duration + easing + an optional motion (C5, any kind as data) + an
/// optional sound effect at the cut.
///
/// `kind` is required. `duration` (timeline frames) falls back to the cut's current transition or a default length,
/// and is never longer than the shorter clip. `easing` is a `TimelineTransition` easing (linear when absent).
/// `sfx` names an audio library item (`id` or `scope:id`); without it, a preset's own `file` is its sound.
public struct TransitionPreset: Sendable, Equatable {
    public static let maximumDuration = 600
    /// The item field that marks a sound effect a preset placed, with the ID of its transition.
    public static let soundField = "transitionSFX"
    /// The media field naming the audio library item (`scope:id`) a preset's sound was copied from.
    public static let soundLibraryField = "libraryItem"

    public var kind: String
    public var duration: Int?
    public var easing: String?
    /// A `TransitionMotion` object; required for a kind that is not built in.
    public var motion: JSONValue?
    public var sfx: String?

    public init(kind: String, duration: Int? = nil, easing: String? = nil, motion: JSONValue? = nil, sfx: String? = nil) {
        self.kind = kind
        self.duration = duration
        self.easing = easing
        self.motion = motion
        self.sfx = sfx
    }

    /// Reads and checks `params`; `label` starts each error message.
    public init(params: [String: JSONValue], label: String = "transition preset") throws {
        guard let kind = params["kind"]?.string,
            kind.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil
        else { throw ProjectError.invalid("\(label): a transition preset needs params.kind, such as dissolve") }
        self.kind = kind
        if let value = params["duration"] {
            guard let frames = value.int, (1...Self.maximumDuration).contains(frames) else {
                throw ProjectError.invalid("\(label): params.duration must be 1–\(Self.maximumDuration) frames")
            }
            duration = frames
        }
        if let value = params["easing"] {
            guard let easing = value.string, TimelineTransition.isEasing(easing) else {
                throw ProjectError.invalid("\(label): params.easing must be one of \(TimelineTransition.easingSummary)")
            }
            self.easing = easing
        }
        if let value = params["motion"] {
            do { _ = try TransitionMotion(json: value) } catch let ProjectError.invalid(message) {
                throw ProjectError.invalid("\(label): params.\(message)")
            }
            motion = value
        }
        if let value = params["sfx"] {
            let id = value.string.map { $0.split(separator: ":", maxSplits: 1).last.map(String.init) ?? $0 }
            guard let id, id.range(of: StyleCatalog.idPattern, options: .regularExpression) != nil else {
                throw ProjectError.invalid("\(label): params.sfx must be an audio library item ID")
            }
            sfx = value.string
        }
    }

    /// The params as a library item stores them; a linear easing is left out.
    public var params: [String: JSONValue] {
        var params: [String: JSONValue] = ["kind": .string(kind)]
        if let duration { params["duration"] = .integer(duration) }
        if let easing, easing != TimelineTransition.defaultEasing { params["easing"] = .string(easing) }
        if let motion { params["motion"] = motion }
        if let sfx { params["sfx"] = .string(sfx) }
        return params
    }
}

extension Project {
    /// The cut beside the video clip `itemID`: before it, or else after it.
    public func videoCut(beside itemID: String) -> (from: Item, to: Item)? {
        for track in tracks where track.kind == "video" {
            let items = track.items.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { continue }
            if index > 0, items[index - 1].end == items[index].at {
                return (items[index - 1], items[index])
            }
            if index + 1 < items.count, items[index].end == items[index + 1].at {
                return (items[index], items[index + 1])
            }
        }
        return nil
    }

    /// The sound effect a preset placed for the transition `transitionID`, with its media.
    public func transitionSound(for transitionID: String) -> (item: Item, media: Media)? {
        for track in tracks where track.kind == "audio" {
            for item in track.items where item[TransitionPreset.soundField]?.string == transitionID {
                if let media = media.first(where: { $0.id == item.mediaID }) { return (item, media) }
            }
        }
        return nil
    }

    /// The plan that applies `preset` at the cut beside the video clip `itemID` as one edit: the transition and,
    /// with `sound` (audio media, new or already in the project), a sound effect from the cut on an SFX layer
    /// (added when the project has none). It replaces a sound an earlier preset placed at this cut.
    public func transitionPresetPlan(_ preset: TransitionPreset, at itemID: String, sound: Media? = nil) throws -> LayerPlanner {
        guard TimelineTransition.renderedKinds.contains(preset.kind) || preset.motion != nil else {
            throw ProjectError.invalid("The transition kind \(preset.kind) is not built in: give params.motion")
        }
        guard let cut = videoCut(beside: itemID) else {
            throw ProjectError.invalid("\(itemID) is not a video clip beside a cut")
        }
        let existing = transitions.first { $0.fromItemID == cut.from.id && $0.toItemID == cut.to.id }
        let longest = min(cut.from.duration, cut.to.duration)
        let duration = min(longest, max(1, preset.duration ?? existing?.duration ?? min(15, longest / 3)))
        let id = existing?.id ?? "transition-\(cut.from.id)-\(cut.to.id)"
        var planner = LayerPlanner(self)
        try planner.add([
            .upsertTransition(
                id: id, kind: preset.kind, from: cut.from.id, to: cut.to.id, duration: duration, easing: preset.easing,
                motion: preset.motion),
        ])
        guard let sound else { return planner }
        guard sound.kind == "audio" else { throw ProjectError.invalid("A transition sound must be audio") }
        let length = sound.placementFrames(in: fps)
        guard length > 0 else { throw ProjectError.invalid("The transition sound is too short") }
        if let earlier = transitionSound(for: id) { try planner.add([.delete(item: earlier.item.id, ripple: false)]) }
        if !media.contains(where: { $0.id == sound.id }) { try planner.add([.addMedia(sound)]) }
        let layer = try planner.sfxTrack()
        var item = Item(media: sound.id, at: cut.to.at, duration: length)
        item[TransitionPreset.soundField] = .string(id)
        try planner.place(item, on: layer)
        return planner
    }
}

extension LayerPlanner {
    /// The first SFX layer, added (named SFX) when the project has none.
    mutating func sfxTrack() throws -> String {
        if let track = project.track(role: TrackRole.sfx, kind: "audio") { return track.id }
        var track = Track(id: project.newTrackID(kind: "audio"), kind: "audio", role: TrackRole.sfx)
        track.name = "SFX"
        try add([.addTrack(track: track, atIndex: project.defaultTrackIndex(kind: "audio"))])
        return track.id
    }
}
