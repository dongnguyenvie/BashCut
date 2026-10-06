import Foundation

/// What applying an effect recipe needs besides the project (#76).
public struct EffectApplication: Sendable {
    /// Parameter overrides by name.
    public var values: [String: Double] = [:]
    /// Timeline frames `[from, to)` inside the clip: the clip is split there in the same edit and only that part gets
    /// the effect. Nil applies to the whole clip.
    public var range: Range<Int>?
    /// Audio media for the `sfx` steps (new or already in the project), keyed by the step's `sfx` reference or by
    /// `EffectRecipe.ownSound` for the preset's own file.
    public var sounds: [String: Media] = [:]
    /// Reversed copies already rendered, keyed by `Media.reversedPath(sourceIn:frames:)`.
    public var reversed: [String: Media] = [:]
    /// Starts the IDs of the parts a range splits off.
    public var splitID = String(UUID().uuidString.prefix(8)).lowercased()

    public init(values: [String: Double] = [:], range: Range<Int>? = nil) {
        self.values = values
        self.range = range
    }
}

/// A `reverse` step needs a reversed copy of `frames` source frames of `media` from `sourceIn`, rendered to `path`
/// (relative to the project folder); render it, add it to `EffectApplication.reversed` and plan again.
public struct EffectReverseNeeded: Error, Sendable, Equatable {
    public let media: Media
    public let sourceIn: Int
    public let frames: Int
    public let path: String

    public init(media: Media, sourceIn: Int, frames: Int, path: String) {
        self.media = media
        self.sourceIn = sourceIn
        self.frames = frames
        self.path = path
    }
}

extension Media {
    /// Where a reversed copy of this media's frames `[sourceIn, sourceIn + frames)` goes: `reversed/` in the project,
    /// named after the original file so the clip still reads as it.
    public func reversedPath(sourceIn: Int, frames: Int) -> String {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let safe = String(stem.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }.prefix(60))
        return "reversed/\(safe.isEmpty ? id : safe)-reversed-\(sourceIn)-\(frames).mov"
    }
}

extension Project {
    /// The plan that applies `recipe` to the item `itemID` as one edit, and the ID of the item that got the effect
    /// (a new one when a range split the clip). Steps run in order, each on the clip as the steps before left it, so
    /// positions scale with the length a speed step gave it. Sounds and text a recipe placed for the same item before
    /// are replaced. Throws `EffectReverseNeeded` when a reversed copy still has to be rendered.
    public func effectRecipePlan(
        _ recipe: EffectRecipe, to itemID: String, _ application: EffectApplication = EffectApplication()
    ) throws -> (planner: LayerPlanner, itemID: String) {
        let steps = try recipe.resolvedSteps(application.values)
        guard let item = tracks.flatMap(\.items).first(where: { $0.id == itemID }) else {
            throw ProjectError.invalid("Unknown item \(itemID)")
        }
        var builder = EffectPlanBuilder(planner: LayerPlanner(self), target: itemID, application: application)
        if let range = application.range {
            guard range.lowerBound >= item.at, range.upperBound <= item.end, !range.isEmpty else {
                throw ProjectError.invalid("The range must be inside \(itemID): frames \(item.at) to \(item.end)")
            }
            try builder.split(item, range)
        }
        try builder.removePlaced(sounds: steps.contains { if case .sfx = $0 { true } else { false } },
                                 text: steps.contains { if case .text = $0 { true } else { false } })
        for step in steps { try builder.run(step) }
        return (builder.planner, builder.target)
    }
}

private struct EffectPlanBuilder {
    var planner: LayerPlanner
    var target: String
    let application: EffectApplication

    init(planner: LayerPlanner, target: String, application: EffectApplication) {
        self.planner = planner
        self.target = target
        self.application = application
    }

    private var project: Project { planner.project }

    private func current() throws -> (item: Item, track: Track) {
        guard let track = project.tracks.first(where: { $0.items.contains { $0.id == target } }),
            let item = track.items.first(where: { $0.id == target })
        else { throw ProjectError.invalid("Unknown item \(target)") }
        return (item, track)
    }

    private func media(of item: Item, for step: String) throws -> Media {
        guard let id = item.mediaID, let media = project.media.first(where: { $0.id == id }) else {
            throw ProjectError.invalid("\(step) works on clips with media")
        }
        return media
    }

    /// Splits off `range` of `item` (and its linked sound); the middle part becomes the target.
    mutating func split(_ item: Item, _ range: Range<Int>) throws {
        if range.upperBound < item.end {
            try planner.add([.split(item: item.id, atFrame: range.upperBound, newID: "\(item.id)-\(application.splitID)-b")])
        }
        if range.lowerBound > item.at {
            let middle = "\(item.id)-\(application.splitID)-a"
            try planner.add([.split(item: item.id, atFrame: range.lowerBound, newID: middle)])
            target = middle
        }
    }

    /// Deletes the sounds and text an earlier apply placed for the target.
    mutating func removePlaced(sounds: Bool, text: Bool) throws {
        var fields: [String] = []
        if sounds { fields.append(EffectRecipe.soundField) }
        if text { fields.append(EffectRecipe.textField) }
        let earlier = project.tracks.flatMap(\.items).filter { item in fields.contains { item[$0]?.string == target } }
        for item in earlier { try planner.add([.delete(item: item.id, ripple: false)]) }
    }

    // One case per step kind.
    // swiftlint:disable:next cyclomatic_complexity
    mutating func run(_ step: EffectRecipe.Step) throws {
        switch step {
        case .motion(let preset):
            let (item, _) = try current()
            let motion = try MotionPreset.motion(
                preset, duration: item.duration, width: project.width, height: project.height, fps: project.fps)
            try setKeys(motion.keys)
        case .focus(let from, let to, let ease):
            try focus(from, to: to, ease: ease)
        case .keyframes(let keys):
            let (item, _) = try current()
            try setKeys(keys.mapValues { list in
                var byFrame: [Int: ItemMotion.Key] = [:]
                for key in list {
                    let frame = key.position.frame(length: item.duration)
                    byFrame[frame] = ItemMotion.Key(frame: frame, value: key.value, ease: key.ease)
                }
                return byFrame.values.sorted { $0.frame < $1.frame }
            })
        case .speed(let speed, let keepDuration):
            try planner.add([.setSpeed(item: target, speed: speed, keepDuration: keepDuration)])
        case .speedCurve(let curve, let keepDuration):
            try planner.add([.setSpeedCurve(item: target, curve: curve, keepDuration: keepDuration)])
        case .reverse:
            try reverse()
        case .freeze(let position):
            let (item, _) = try current()
            let media = try media(of: item, for: "freeze")
            let local = min(max(0, position.frame(length: item.duration)), item.duration - 1)
            let elapsed = item.sourceSeconds(afterFrames: local, fps: project.fps)
            let source = min(max(0, media.frames - 1), item.sourceIn + Int((elapsed * media.fps.value).rounded(.down)))
            try planner.add([.setProperties(item: target, patch: ["freezeFrame": .integer(source)])])
        case .patch(let patch):
            try planner.add([.setProperties(item: target, patch: patch)])
        case .sfx(let source, let position, let volume):
            try sound(source, at: position, volumeDb: volume)
        case .text(let text, let preset, let position, let duration):
            let (item, _) = try current()
            let start = min(max(0, position.frame(length: item.duration)), item.duration - 1)
            var overlay = Item(at: item.at + start, duration: max(1, duration ?? item.duration - start))
            overlay["text"] = .string(text)
            overlay["textPreset"] = .string(preset)
            overlay[EffectRecipe.textField] = .string(target)
            try planner.place(overlay, on: project.requireTrack(role: TrackRole.captions).id)
        }
    }

    /// Replaces the keys of the given properties, keeping the item's others.
    private mutating func setKeys(_ keys: [String: [ItemMotion.Key]]) throws {
        let (item, track) = try current()
        let allowed = ItemMotion.properties(onTrackKind: track.kind)
        if let property = keys.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw ProjectError.invalid("\(target) cannot animate \(property); its layer animates \(allowed.joined(separator: ", "))")
        }
        var motion = item.motion ?? ItemMotion(keys: [:])
        for (property, list) in keys { motion.keys[property] = list }
        try planner.add([.setProperties(item: target, patch: ["keyframes": motion.json])])
    }

    private mutating func focus(_ from: MotionFocus.Region, to: MotionFocus.Region?, ease: ItemMotion.Ease) throws {
        let (item, track) = try current()
        guard track.kind == TrackKind.video, let id = item.mediaID, let media = project.media.first(where: { $0.id == id }),
            let width = media.width, let height = media.height
        else { throw ProjectError.invalid("focus frames a video clip or image whose media has a known size") }
        func framing(_ region: MotionFocus.Region) throws -> MotionFocus.Framing {
            let pixels = MotionFocus.Region(
                x: region.x * Double(width), y: region.y * Double(height), width: region.width * Double(width),
                height: region.height * Double(height))
            return try MotionFocus.framing(
                pixels, source: (Double(width), Double(height)), canvas: (Double(project.width), Double(project.height)),
                fill: project.fills(item))
        }
        let start = try framing(from)
        let end = try to.map(framing)
        let last = max(1, item.duration - 1)
        var keys: [String: [ItemMotion.Key]] = [:]
        for (property, value) in [("zoom", \MotionFocus.Framing.zoom), ("pan", \.pan), ("tilt", \.tilt)] {
            var list = [ItemMotion.Key(frame: 0, value: start[keyPath: value], ease: ease)]
            if let end { list.append(.init(frame: last, value: end[keyPath: value])) }
            keys[property] = list
        }
        try setKeys(keys)
    }

    /// Points the target at a reversed copy of the source it uses; a clip already reversed stays as it is.
    private mutating func reverse() throws {
        let (item, _) = try current()
        guard item.fields["freezeFrame"] == nil else { throw ProjectError.invalid("A freeze frame cannot be reversed") }
        let media = try media(of: item, for: "reverse")
        guard media.kind != "audio", !media.isImage else { throw ProjectError.invalid("Reverse works on video clips") }
        guard item.fields["reversed"] == nil else { return }
        let consumed = max(1, Int((item.sourceSeconds(afterFrames: item.duration, fps: project.fps) * media.fps.value)
            .rounded(.up)))
        let path = media.reversedPath(sourceIn: item.sourceIn, frames: consumed)
        guard let copy = application.reversed[path] else {
            throw EffectReverseNeeded(media: media, sourceIn: item.sourceIn, frames: consumed, path: path)
        }
        if !project.media.contains(where: { $0.id == copy.id }) { try planner.add([.addMedia(copy)]) }
        try planner.add([.setSource(
            item: target, media: copy.id, sourceIn: max(0, copy.frames - consumed),
            reversed: .object(["media": .string(media.id), "in": .integer(item.sourceIn), "frames": .integer(consumed)]))])
    }

    private mutating func sound(_ source: String?, at position: EffectRecipe.Position, volumeDb: Double?) throws {
        let (item, _) = try current()
        guard let sound = application.sounds[source ?? EffectRecipe.ownSound] else {
            throw ProjectError.invalid("The effect's sound \(source ?? "file") was not found")
        }
        guard sound.kind == "audio" else { throw ProjectError.invalid("An effect sound must be audio") }
        let length = sound.placementFrames(in: project.fps)
        guard length > 0 else { throw ProjectError.invalid("The effect sound is too short") }
        if !project.media.contains(where: { $0.id == sound.id }) { try planner.add([.addMedia(sound)]) }
        let layer = try planner.sfxTrack()
        let start = min(max(0, position.frame(length: item.duration)), item.duration - 1)
        var effect = Item(media: sound.id, at: item.at + start, duration: length)
        effect[EffectRecipe.soundField] = .string(target)
        if let volumeDb { effect["volumeDb"] = .number(volumeDb) }
        try planner.place(effect, on: layer)
    }
}
