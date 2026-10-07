import Foundation

public enum ProjectError: Error, LocalizedError, Equatable {
    case invalid(String)
    case staleRevision(expected: Int, actual: Int)
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .staleRevision(let expected, let actual):
            return "staleRevision: expected \(expected), current \(actual)"
        }
    }
}

extension Project {
    // Validation stays centralized so every edit, save and import enforces the same invariants.
    public func validate() throws {
        guard !isKnownValid else { return }
        func require(_ valid: Bool, _ message: String) throws {
            guard valid else { throw ProjectError.invalid(message) }
        }
        try require(self["schema"] == .string(Self.schema), "schema: unsupported version")
        try require(!(self["id"]?.string ?? "").isEmpty && !name.isEmpty, "id/name: required")
        try require(revision >= 0 && revision < Int.max, "rev: invalid revision")
        try require(
            width > 0 && width <= 16384 && height > 0 && height <= 16384, "format: invalid dimensions")
        try require(
            fps.numerator > 0 && fps.numerator <= 1_000_000 && fps.denominator > 0
                && fps.denominator <= 1_000_000,
            "format.fps: expected positive rational")
        try require(!tracks.isEmpty && tracks.count <= 256, "tracks: expected 1–256 layers")
        try require(Set(tracks.map(\.id)).count == tracks.count, "tracks: duplicate IDs")
        try require(Set(media.map(\.id)).count == media.count, "media: duplicate IDs")
        for asset in media {
            try validateMediaPath(asset)
            try require(
                asset.fps.numerator > 0 && asset.fps.numerator <= 1_000_000 && asset.fps.denominator > 0
                    && asset.fps.denominator <= 1_000_000 && asset.frames > 0
                    && asset.frames <= 2_000_000_000,
                "media.\(asset.id): invalid frame metadata")
            try validateMetadata(asset)
        }
        if let grid = self["beatGrid"]?.object {
            let frames = grid["frames"]?.array.compactMap(\.int) ?? []
            let bpm = grid["bpm"]?.double ?? .nan
            let end = duration
            try require(
                media.contains(where: { $0.id == grid["media"]?.string }),
                "beatGrid: unknown media")
            try require(
                bpm.isFinite && (20...400).contains(bpm) && !frames.isEmpty
                    && frames.count <= 100_000 && frames == Array(Set(frames)).sorted()
                    && frames.allSatisfy({ (0...end).contains($0) }),
                "beatGrid: invalid timing")
        } else if self["beatGrid"] != nil {
            throw ProjectError.invalid("beatGrid: expected object")
        }
        try validateProjectFlags()
        try validateAudioSettings()
        try validateOutputSettings()
        try validateReviewSettings()
        try validateSelects()
        try validateOutputCaptions()
        try validateMarkers()
        try validateColorLUTs()
        let lutIDs = Set(colorLUTs.map(\.id))
        let mediaByID = Dictionary(media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ids = Set<String>()
        for track in tracks {
            try require(
                !track.id.isEmpty && TrackKind.all.contains(track.kind),
                "track.\(track.id): invalid kind")
            try require(!track.role.isEmpty, "track.\(track.id): role required")
            try require(!track.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "track.\(track.id): name required")
            if let value = track["magnetic"], case .bool = value {
            } else if track["magnetic"] != nil {
                throw ProjectError.invalid("track.\(track.id): magnetic must be boolean")
            }
            try track.validateDuckingProperties()
            try track.validateStates()
            for item in track.items.sorted(by: { $0.at < $1.at }) {
                try require(
                    !item.id.isEmpty && ids.insert(item.id).inserted, "items: empty or duplicate ID")
                try require(
                    item.at >= 0 && item.duration > 0 && item.at <= 2_000_000_000 - item.duration,
                    "item.\(item.id): invalid timeline range")
                try require(
                    item.sourceIn >= 0 && item.sourceIn <= 2_000_000_000 && item.speed.isFinite
                        && item.speed > 0,
                    "item.\(item.id): invalid source/speed")
                try item.validateRenderProperties()
                try item.validateKeyframes(on: track)
                try item.validateWords()
                if let color = item.fields["color"]?.object {
                    // A LUT is referenced by catalog ID; anything else would be silently ignored by the engine.
                    try ColorGrade.validate(color, path: "item.\(item.id).color", lutIDs: lutIDs)
                }
                try validateContent(item, on: track, media: mediaByID)
            }
        }
        try validateLayers()
        try validateLinkedItems()
        try validateTransitions()
    }
}

extension Project {
    /// `output.presets` (#441): at most 8 known export presets.
    fileprivate func validateOutputSettings() throws {
        guard let value = self["output"] else { return }
        guard case .object(let output) = value else { throw ProjectError.invalid("output: expected object") }
        if let targets = output["targets"], targets != .null {
            guard case .object(let map) = targets, map.keys.allSatisfy(OutputPresetName.all.contains),
                map.values.allSatisfy({ target in
                    let fields = target.object
                    return (fields["integratedLUFS"]?.double).map { (-30 ... -5).contains($0) } ?? (fields["integratedLUFS"] == nil)
                        && ((fields["truePeakDbTP"]?.double).map { (-12...0).contains($0) } ?? (fields["truePeakDbTP"] == nil))
                })
            else { throw ProjectError.invalid("output.targets: preset → {integratedLUFS −30…−5, truePeakDbTP −12…0}") }
        }
        guard let presets = output["presets"] else { return }
        guard case .array(let names) = presets, names.count <= 8,
            names.allSatisfy({ $0.string.map(OutputPresetName.all.contains) == true })
        else {
            throw ProjectError.invalid(
                "output.presets: expected at most 8 of \(OutputPresetName.all.joined(separator: ", "))")
        }
    }

    fileprivate func validateAudioSettings() throws {
        guard let value = self["audio"] else { return }
        guard case .object(let audio) = value else {
            throw ProjectError.invalid("audio: expected object")
        }
        func number(_ key: String, range: ClosedRange<Double>) throws {
            guard let value = audio[key] else { return }
            guard let number = value.double, number.isFinite, range.contains(number) else {
                throw ProjectError.invalid("audio.\(key): expected a number in \(range)")
            }
        }
        try number("targetLUFS", range: -30 ... -5)
        try number("mixGainDb", range: -60...24)
        try number("measuredLUFS", range: -100...10)
        try number("truePeakDbTP", range: -100...20)
        try number("loudnessRangeLU", range: 0...100)
        if let enabled = audio["normalizeEnabled"], case .bool = enabled {
        } else if audio["normalizeEnabled"] != nil {
            throw ProjectError.invalid("audio.normalizeEnabled: expected boolean")
        }
        if let verified = audio["measurementVerified"], case .bool = verified {
        } else if audio["measurementVerified"] != nil {
            throw ProjectError.invalid("audio.measurementVerified: expected boolean")
        }
    }
}

extension Track {
    fileprivate func validateDuckingProperties() throws {
        let keys = ["duckUnderSpeechDb", "duckingEnabled", "duckAttackFrames", "duckReleaseFrames"]
        if keys.contains(where: { self[$0] != nil }), kind != "audio" || role != "music" {
            throw ProjectError.invalid("track.\(id): ducking is only valid on Music audio tracks")
        }
        if let value = self["duckUnderSpeechDb"],
            !(value.double.map { $0.isFinite && (-60...0).contains($0) } ?? false)
        {
            throw ProjectError.invalid("track.\(id).duckUnderSpeechDb: expected -60...0 dB")
        }
        if let value = self["duckingEnabled"], case .bool = value {
        } else if self["duckingEnabled"] != nil {
            throw ProjectError.invalid("track.\(id).duckingEnabled: expected boolean")
        }
        for key in ["duckAttackFrames", "duckReleaseFrames"] {
            if let value = self[key], !(value.int.map { (0...10_000).contains($0) } ?? false) {
                throw ProjectError.invalid("track.\(id).\(key): expected nonnegative integer frames")
            }
        }
    }
}

extension Project {
    private func validateMetadata(_ asset: Media) throws {
        if let description = asset.fields["description"], description != .null {
            do { _ = try MediaDescription(json: description, duration: asset.durationSeconds) } catch {
                throw ProjectError.invalid("media.\(asset.id).\(error.localizedDescription)")
            }
        }
        if asset.fields["width"] != nil || asset.fields["height"] != nil {
            guard asset.width.map({ (1...16384).contains($0) }) == true,
                asset.height.map({ (1...16384).contains($0) }) == true
            else { throw ProjectError.invalid("media.\(asset.id): invalid dimensions") }
        }
        if let license = asset.fields["license"] { try LicenseTerms.validate(license, label: "media.\(asset.id)") }
        if let provenance = asset.fields["provenance"] { try Provenance.validate(provenance, label: "media.\(asset.id)") }
        if let value = asset.fields["hasAudio"], case .bool = value { return }
        guard asset.fields["hasAudio"] == nil else {
            throw ProjectError.invalid("media.\(asset.id): hasAudio must be boolean")
        }
    }

    private func validateMediaPath(_ asset: Media) throws {
        guard !asset.id.isEmpty, !asset.path.isEmpty, !asset.path.hasPrefix("/") else {
            throw ProjectError.invalid("media: relative path required")
        }
        guard asset.path.hasPrefix("@") else { return }
        let prefix = "@assets/"
        guard asset.path.hasPrefix(prefix),
            MediaPathResolver.validSharedPath(String(asset.path.dropFirst(prefix.count)))
        else { throw ProjectError.invalid("media.\(asset.id): invalid shared path") }
    }

    /// Media items need known media and a source range that fits; text items need text; adjustment items
    /// carry neither.
    private func validateContent(_ item: Item, on track: Track, media: [String: Media]) throws {
        if track.isAdjustment {
            guard item.mediaID == nil, item.fields["text"] == nil else {
                throw ProjectError.invalid("item.\(item.id): adjustment items take no media or text")
            }
        } else if track.kind != "text" {
            guard let asset = item.mediaID.flatMap({ media[$0] }) else {
                throw ProjectError.invalid("item.\(item.id): unknown media")
            }
            try validateSourceRange(item, on: track, media: asset)
        } else if item.fields["text"]?.string == nil {
            throw ProjectError.invalid("item.\(item.id): text required")
        } else if let preset = item.fields["textPreset"], preset.string.map({ (1...80).contains($0.count) }) != true {
            // Open (Phase 2 restyle): a built-in name picks its defaults; any other name renders with the first
            // preset's defaults plus the item's textStyle.
            throw ProjectError.invalid("item.\(item.id).textPreset: expected a name of 1–80 characters")
        }
    }

    private func validateSourceRange(_ item: Item, on track: Track, media asset: Media) throws {
        if let value = item.fields["speedCurve"] {
            let curve: SpeedCurve
            do { curve = try SpeedCurve(json: value) } catch {
                throw ProjectError.invalid("item.\(item.id).speedCurve: \(error.localizedDescription)")
            }
            guard abs(curve.average - item.speed) < 0.0001 else {
                throw ProjectError.invalid("item.\(item.id): speed must equal the speed curve's average")
            }
        }
        let freezeFrame = item.fields["freezeFrame"]?.int
        if item.fields["freezeFrame"] != nil {
            guard track.kind == "video", freezeFrame.map({ (0..<asset.frames).contains($0) }) == true else {
                throw ProjectError.invalid("item.\(item.id): invalid freeze frame")
            }
        }
        let consumed = freezeFrame == nil
            ? Double(item.duration) / fps.value * asset.fps.value * item.speed : 1
        let sourceStart = freezeFrame ?? item.sourceIn
        guard item.sourceIn < asset.frames,
            Double(sourceStart) + consumed <= Double(asset.frames) + 0.0001
        else { throw ProjectError.invalid("item.\(item.id): trim past source end") }
    }

    private func validateMarkers() throws {
        guard let markerValue = self["markers"] else { return }
        guard case .array = markerValue else {
            throw ProjectError.invalid("markers: expected array")
        }
        let values = markers
        guard values.count <= 10_000, Set(values.map(\.id)).count == values.count else {
            throw ProjectError.invalid("markers: invalid count or duplicate IDs")
        }
        var sectionFrames = Set<Int>()
        let duration = duration
        for marker in values {
            let label = marker.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !marker.kind.isEmpty, !label.isEmpty, marker.label.count <= 120,
                (0...duration).contains(marker.at)
            else { throw ProjectError.invalid("marker.\(marker.id): invalid marker") }
            guard marker.kind != "section" || sectionFrames.insert(marker.at).inserted else {
                throw ProjectError.invalid("markers: duplicate section frame")
            }
        }
    }

    private func validateLinkedItems() throws {
        let located = Dictionary(
            uniqueKeysWithValues: tracks.flatMap { track in
                track.items.map { ($0.id, (track: track, item: $0)) }
            })
        for track in tracks {
            for item in track.items {
                let audioID = item.fields["linkedAudio"]?.string
                let videoID = item.fields["linkedVideo"]?.string
                guard audioID == nil || videoID == nil else {
                    throw ProjectError.invalid("item.\(item.id): cannot link as both picture and sound")
                }
                guard let linkedID = audioID ?? videoID else { continue }
                guard !linkedID.isEmpty, let linked = located[linkedID] else {
                    throw ProjectError.invalid("item.\(item.id): linked item is missing")
                }
                let expectsAudio = audioID != nil
                guard track.kind == (expectsAudio ? "video" : "audio"),
                    linked.track.kind == (expectsAudio ? "audio" : "video")
                else { throw ProjectError.invalid("item.\(item.id): invalid linked track kinds") }
                let reciprocalKey = expectsAudio ? "linkedVideo" : "linkedAudio"
                guard linked.item.fields[reciprocalKey]?.string == item.id else {
                    throw ProjectError.invalid("item.\(item.id): linked item must be reciprocal")
                }
                guard item.mediaID == linked.item.mediaID, item.at == linked.item.at,
                    item.duration == linked.item.duration, item.sourceIn == linked.item.sourceIn,
                    item.speed == linked.item.speed
                else { throw ProjectError.invalid("item.\(item.id): linked timing or media differs") }
            }
        }
    }

    private func validateTransitions() throws {
        guard let value = self["transitions"] else { return }
        guard case .array = value, transitions.count <= 10_000,
            Set(transitions.map(\.id)).count == transitions.count,
            Set(transitions.map(\.fromItemID)).count == transitions.count,
            Set(transitions.map(\.toItemID)).count == transitions.count
        else { throw ProjectError.invalid("transitions: invalid collection") }
        let cuts = VideoCuts(self)
        for transition in transitions {
            guard transitionIsValid(transition, cuts: cuts) else {
                throw ProjectError.invalid("transition.\(transition.id): invalid cut or duration")
            }
            if let easing = transition.fields["easing"], easing.string.map(TimelineTransition.easings.contains) != true {
                throw ProjectError.invalid(
                    "transition.\(transition.id): easing must be one of \(TimelineTransition.easings.joined(separator: ", "))")
            }
        }
    }

    private func validateColorLUTs() throws {
        guard let value = self["luts"] else { return }
        guard case .array = value, colorLUTs.count <= 1_000,
            Set(colorLUTs.map(\.id)).count == colorLUTs.count
        else { throw ProjectError.invalid("luts: invalid collection") }
        for lut in colorLUTs {
            let components = lut.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !lut.id.isEmpty, !lut.name.isEmpty, lut.name.count <= 120,
                (2...64).contains(lut.size), lut.path.hasPrefix("luts/"),
                lut.path.hasSuffix(".cube"), !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
            else { throw ProjectError.invalid("lut.\(lut.id): invalid catalog entry") }
        }
    }

    /// Drops transitions whose cut an edit removed or moved apart.
    mutating func removeInvalidTransitions() {
        let current = transitions
        guard !current.isEmpty else { return }
        let cuts = VideoCuts(self)
        let valid = current.filter { transitionIsValid($0, cuts: cuts) }
        if valid.count != current.count { transitions = valid }
    }

    func transitionIsValid(_ transition: TimelineTransition) -> Bool {
        transitionIsValid(transition, cuts: VideoCuts(self))
    }

    /// Checking many transitions shares one `VideoCuts`, so each check is a lookup instead of a sort.
    func transitionIsValid(_ transition: TimelineTransition, cuts: VideoCuts) -> Bool {
        guard !transition.id.isEmpty,
            transition.kind.range(
                of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil,
            transition.fromItemID != transition.toItemID,
            let from = cuts.positions[transition.fromItemID],
            let to = cuts.positions[transition.toItemID], to.track == from.track, to.index == from.index + 1
        else { return false }
        let left = cuts.tracks[from.track][from.index]
        let right = cuts.tracks[to.track][to.index]
        return left.end == right.at && transition.duration > 0
            && transition.duration <= min(left.duration, right.duration)
    }
}

/// Video items in timeline order on each video layer, and where each item sits.
struct VideoCuts {
    let tracks: [[Item]]
    let positions: [String: (track: Int, index: Int)]

    init(_ project: Project) {
        var tracks: [[Item]] = []
        var positions: [String: (track: Int, index: Int)] = [:]
        for track in project.tracks where track.kind == "video" {
            let items = track.items.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
            for (index, item) in items.enumerated() where positions[item.id] == nil {
                positions[item.id] = (tracks.count, index)
            }
            tracks.append(items)
        }
        self.tracks = tracks
        self.positions = positions
    }
}

extension Item {
    fileprivate func validateKeyframes(on track: Track) throws {
        guard let keyframes = fields["keyframes"] else { return }
        let motion: ItemMotion
        do { motion = try ItemMotion(json: keyframes) } catch {
            throw ProjectError.invalid("item.\(id).\(error.localizedDescription)")
        }
        let allowed = ItemMotion.properties(onTrackKind: track.kind)
        if let property = motion.keys.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw ProjectError.invalid(
                "item.\(id).keyframes.\(property): \(track.kind) items animate \(allowed.joined(separator: ", "))")
        }
    }

    fileprivate func validateRenderProperties() throws {
        if let value = fields["in"], value.int == nil {
            throw ProjectError.invalid("item.\(id).in: expected integer source frame")
        }
        try validateDeclaredProperties()
        if case .object(let crop) = fields["crop"] {
            let side = { (key: String) in crop[key]?.double ?? 0 }
            guard side("left") + side("right") < 0.95 + 1e-9, side("top") + side("bottom") < 0.95 + 1e-9 else {
                throw ProjectError.invalid("item.\(id).crop: left + right and top + bottom must each be at most 0.95")
            }
        }
    }
}

extension Project {
    /// Project-level switches that must be booleans when present.
    fileprivate func validateProjectFlags() throws {
        for key in ["clipFill", "canvasFromFirstClip"] {
            if let value = self[key], value.bool == nil { throw ProjectError.invalid("\(key): expected boolean") }
        }
    }
}
