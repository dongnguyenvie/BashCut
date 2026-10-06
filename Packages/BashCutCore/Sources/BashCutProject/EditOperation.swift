import Foundation

public enum Edge: String, Codable, Sendable { case start, end }
/// `agent` is an agent outside the app (CLI or MCP with the automation token file), not a Claude/Codex tab.
public enum Author: String, Codable, Sendable { case user, claude, codex, external, model, agent, plugin }

public indirect enum EditOperation: Codable, Sendable, Equatable {
    case insert(track: String, item: Item)
    case delete(item: String, ripple: Bool)
    case split(item: String, atFrame: Int, newID: String)
    case trim(item: String, edge: Edge, toFrame: Int, ripple: Bool)
    case move(item: String, toTrack: String, atFrame: Int)
    case reorder(item: String, before: String?)
    case slip(item: String, sourceIn: Int)
    case roll(item: String, edge: Edge, toFrame: Int)
    case setSpeed(item: String, speed: Double, keepDuration: Bool)  // see EditOperation+Speed.swift
    case setSpeedCurve(item: String, curve: SpeedCurve?, keepDuration: Bool)
    case setSource(item: String, media: String, sourceIn: Int, reversed: JSONValue?)
    case setProperties(item: String, patch: [String: JSONValue])
    case setLinkedAudio(video: String, audio: String?)
    case addMedia(Media)
    case addTrack(track: Track, atIndex: Int)
    case deleteTrack(track: String)
    case moveTrack(track: String, toIndex: Int)
    case setTrackProperties(track: String, patch: [String: JSONValue])
    case setProjectProperties(patch: [String: JSONValue])
    /// Output size (canvas): portrait, landscape or square at any resolution; see EditOperation+Format.swift.
    case setFormat(width: Int, height: Int)
    case setProviderPreference(capability: String, provider: String?)
    case setBeatGrid(
        media: String, bpm: Double, frames: [Int], provenance: [String: JSONValue]?)
    case upsertSection(id: String, label: String, atFrame: Int)
    case deleteSection(id: String)
    /// `easing` nil or `linear` is the default straight tween (see `TimelineTransition.easings`).
    case upsertTransition(id: String, kind: String, from: String, to: String, duration: Int, easing: String? = nil)
    case deleteTransition(id: String)
    case addColorLUT(ColorLUT)
    case deleteColorLUT(id: String)
    case group(label: String, author: Author, ops: [EditOperation])
    /// Exact inverse snapshots retain unknown fields and ripple positions without rounding again.
    case restore(Project)
}

public struct EditResult: Sendable {
    public let project: Project
    public let inverse: EditOperation
    /// False when the operation left the project as it was: `project` is then the input, revision included.
    public var changed = true
}

extension Project {
    public func applying(_ operation: EditOperation, baseRevision: Int? = nil) throws -> EditResult {
        try validate()
        if let baseRevision, baseRevision != revision {
            throw ProjectError.staleRevision(expected: baseRevision, actual: revision)
        }
        var next = self
        try next.perform(operation)
        try enforceLocks(after: next, operation: operation)
        next.removeInvalidTransitions()
        var before = self
        before.markValid()
        // A restore that only moves the revision (an external reload) still counts, so revisions stay monotonic.
        if next == self { return EditResult(project: before, inverse: .restore(before), changed: false) }
        guard max(revision, next.revision) < Int.max - 1 else {
            throw ProjectError.invalid("Revision counter exhausted")
        }
        next.revision = max(revision, next.revision) + 1
        try next.validate()
        next.markValid()
        return EditResult(project: next, inverse: .restore(before))
    }
}

extension Project {
    fileprivate func sum(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw ProjectError.invalid("Frame arithmetic overflow") }
        return result
    }
    func location(_ id: String) throws -> (Int, Int) {
        for (trackIndex, track) in tracks.enumerated() {
            if let index = track.items.firstIndex(where: { $0.id == id }) { return (trackIndex, index) }
        }
        throw ProjectError.invalid("Unknown item: \(id)")
    }
    fileprivate func sourceOffset(_ frames: Int, item: Item) throws -> Int {
        guard let asset = media.first(where: { $0.id == item.mediaID }) else { return 0 }
        // A cut at a fractional source frame rounds down so the right half cannot overrun the source.
        let offset = (item.sourceSeconds(afterFrames: frames, fps: fps) * asset.fps.value).rounded(.down)
        guard offset.isFinite, offset > Double(Int.min), offset < Double(Int.max) else {
            throw ProjectError.invalid("Source frame overflow")
        }
        return Int(offset)
    }
    // This exhaustive dispatcher delegates each operation's validation and mutation to a small helper.
    // swiftlint:disable:next cyclomatic_complexity
    fileprivate mutating func perform(_ operation: EditOperation) throws {
        switch operation {
        case .restore(let snapshot):
            try snapshot.validate()
            self = snapshot
        case .group(_, _, let operations):
            for operation in operations { try perform(operation) }
        case .addMedia(let asset): media.append(asset)
        case .addTrack(let track, let index):
            try addTrack(track, at: index)
        case .deleteTrack(let id):
            try deleteTrack(id)
        case .moveTrack(let id, let index):
            try moveTrack(id, to: index)
        case .setTrackProperties(let id, let patch):
            try setTrackProperties(id: id, patch: patch)
        case .setProjectProperties(let patch):
            try setProjectProperties(patch)
        case .setFormat(let width, let height):
            try applyFormat(width: width, height: height)
        case .setProviderPreference(let capability, let provider):
            try setProviderPreference(capability: capability, provider: provider)
        case .setBeatGrid(let media, let bpm, let frames, let provenance):
            try setBeatGrid(media: media, bpm: bpm, frames: frames, provenance: provenance)
        case .upsertSection(let id, let label, let frame):
            try upsertSection(id: id, label: label, frame: frame)
        case .deleteSection(let id):
            try deleteSection(id: id)
        case .upsertTransition(let id, let kind, let from, let to, let duration, let easing):
            try upsertTransition(
                TimelineTransition(id: id, kind: kind, from: from, to: to, duration: duration, easing: easing))
        case .deleteTransition(let id):
            try deleteTransition(id: id)
        case .addColorLUT(let lut):
            try addColorLUT(lut)
        case .deleteColorLUT(let id):
            try deleteColorLUT(id: id)
        case .insert(let track, let item):
            try insertItem(track: track, item: item)
        case .setProperties(let id, let patch):
            try setItemProperties(id: id, patch: patch)
        case .setLinkedAudio(let video, let audio):
            try setLinkedAudio(videoID: video, audioID: audio)
        case .delete(let id, let ripple):
            let linked = try linkedItemID(id)
            try deleteItem(id: id, ripple: ripple)
            if let linked { try deleteItem(id: linked, ripple: ripple) }
        case .split(let id, let frame, let newID):
            let linked = try linkedItemID(id)
            try splitItem(id: id, frame: frame, newID: newID)
            if let linked {
                let linkedNewID = newID + "-linked"
                try splitItem(id: linked, frame: frame, newID: linkedNewID)
                try linkItems(newID, linkedNewID)
            }
        case .trim(let id, let edge, let frame, let ripple):
            let linked = try linkedItemID(id)
            try trimItem(id: id, edge: edge, frame: frame, ripple: ripple)
            if let linked { try trimItem(id: linked, edge: edge, frame: frame, ripple: ripple) }
        case .move(let id, let destination, let frame):
            let linked = try linkedItemID(id)
            let linkedTrackID: String?
            if let linked {
                linkedTrackID = tracks[try location(linked).0].id
            } else {
                linkedTrackID = nil
            }
            try moveItem(id: id, destination: destination, frame: frame)
            if let linked, let linkedTrackID {
                try moveItem(id: linked, destination: linkedTrackID, frame: frame)
            }
        case .reorder(let id, let before):
            try reorderItem(id: id, before: before)
        case .slip(let id, let sourceIn):
            let linked = try linkedItemID(id)
            try slipItem(id: id, sourceIn: sourceIn)
            if let linked { try slipItem(id: linked, sourceIn: sourceIn) }
        case .roll(let id, let edge, let frame):
            let linked = try linkedItemID(id)
            try rollItem(id: id, edge: edge, frame: frame)
            if let linked { try rollItem(id: linked, edge: edge, frame: frame) }
        case .setSpeed(let id, let speed, let keepDuration): try applySpeed(id, speed: speed, keepDuration: keepDuration)
        case .setSpeedCurve(let id, let curve, let keepDuration):
            try applySpeedCurve(id, curve: curve, keepDuration: keepDuration)
        case .setSource(let id, let media, let sourceIn, let reversed):
            try applySource(id, media: media, sourceIn: sourceIn, reversed: reversed)
        }
    }

    func linkedItemID(_ id: String) throws -> String? {
        let (track, index) = try location(id)
        let item = tracks[track].items[index]
        return item.fields["linkedAudio"]?.string ?? item.fields["linkedVideo"]?.string
    }

    private mutating func linkItems(_ firstID: String, _ secondID: String) throws {
        let first = try location(firstID)
        let second = try location(secondID)
        let firstKind = tracks[first.0].kind
        let secondKind = tracks[second.0].kind
        guard Set([firstKind, secondKind]) == Set(["video", "audio"]) else {
            throw ProjectError.invalid("Linked items require one video and one audio item")
        }
        let video = firstKind == "video" ? first : second
        let audio = firstKind == "audio" ? first : second
        let videoID = tracks[video.0].items[video.1].id
        let audioID = tracks[audio.0].items[audio.1].id
        tracks[video.0].items[video.1].fields["linkedAudio"] = .string(audioID)
        tracks[audio.0].items[audio.1].fields["linkedVideo"] = .string(videoID)
    }

    private mutating func setLinkedAudio(videoID: String, audioID: String?) throws {
        let video = try location(videoID)
        guard tracks[video.0].kind == "video" else {
            throw ProjectError.invalid("Linked picture must be on a video track")
        }
        if let previous = tracks[video.0].items[video.1].fields["linkedAudio"]?.string,
            let old = try? location(previous)
        {
            tracks[old.0].items[old.1].fields.removeValue(forKey: "linkedVideo")
        }
        tracks[video.0].items[video.1].fields.removeValue(forKey: "linkedAudio")
        guard let audioID else { return }
        let audio = try location(audioID)
        guard tracks[audio.0].kind == "audio" else {
            throw ProjectError.invalid("Linked sound must be on an audio track")
        }
        let picture = tracks[video.0].items[video.1]
        let sound = tracks[audio.0].items[audio.1]
        guard picture.mediaID == sound.mediaID, picture.at == sound.at,
            picture.duration == sound.duration, picture.sourceIn == sound.sourceIn,
            picture.speed == sound.speed
        else { throw ProjectError.invalid("Linked picture and sound timing must match") }
        if let other = sound.fields["linkedVideo"]?.string, other != videoID {
            throw ProjectError.invalid("Audio item is already linked")
        }
        try linkItems(videoID, audioID)
    }

    private mutating func setProviderPreference(capability: String, provider: String?) throws {
        guard capability.range(
            of: "^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$", options: .regularExpression) != nil
        else { throw ProjectError.invalid("Invalid provider capability") }
        var values = self["providers"]?.object ?? [:]
        values[capability] = provider.map(JSONValue.string)
        self["providers"] = .object(values)
    }

    private mutating func setBeatGrid(
        media: String, bpm: Double, frames: [Int], provenance: [String: JSONValue]?
    ) throws {
        let end = duration
        guard self.media.contains(where: { $0.id == media }), bpm.isFinite, (20...400).contains(bpm),
            !frames.isEmpty, frames.count <= 100_000,
            frames.allSatisfy({ (0...end).contains($0) }),
            frames == Array(Set(frames)).sorted()
        else { throw ProjectError.invalid("Invalid beat grid") }
        var value: [String: JSONValue] = [
            "media": .string(media), "bpm": .number(bpm),
            "frames": .array(frames.map(JSONValue.integer)),
        ]
        if let provenance { value["generatedBy"] = .object(provenance) }
        self["beatGrid"] = .object(value)
    }

    private mutating func upsertSection(id: String, label: String, frame: Int) throws {
        let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !clean.isEmpty, clean.count <= 120, (0...duration).contains(frame) else {
            throw ProjectError.invalid("Invalid section marker")
        }
        var values = markers
        guard !values.contains(where: { $0.kind == "section" && $0.at == frame && $0.id != id }) else {
            throw ProjectError.invalid("A section already starts at this frame")
        }
        if let index = values.firstIndex(where: { $0.id == id }) {
            guard values[index].kind == "section" else {
                throw ProjectError.invalid("Marker is not a section")
            }
            values[index].fields["id"] = .string(id)
            values[index].fields["at"] = .integer(frame)
            values[index].fields["label"] = .string(clean)
        } else {
            values.append(TimelineMarker(id: id, at: frame, kind: "section", label: clean))
        }
        markers = values
    }

    private mutating func deleteSection(id: String) throws {
        var values = markers
        guard let index = values.firstIndex(where: { $0.id == id && $0.kind == "section" }) else {
            throw ProjectError.invalid("Unknown section: \(id)")
        }
        values.remove(at: index)
        markers = values
    }

    private mutating func addTrack(_ track: Track, at index: Int) throws {
        guard !track.id.isEmpty, !tracks.contains(where: { $0.id == track.id }),
            (0...tracks.count).contains(index)
        else { throw ProjectError.invalid("Invalid track insertion") }
        try requireBand(track, at: index, inserting: true)
        tracks.insert(track, at: index)
    }

    private mutating func deleteTrack(_ id: String) throws {
        guard tracks.count > 1, let index = tracks.firstIndex(where: { $0.id == id }) else {
            throw ProjectError.invalid("Unknown track or final remaining track")
        }
        guard tracks[index].role != TrackRole.main else {
            throw ProjectError.invalid("The main layer cannot be deleted")
        }
        guard tracks[index].items.isEmpty else {
            throw ProjectError.invalid("Move or delete items before removing a track")
        }
        tracks.remove(at: index)
    }

    private mutating func moveTrack(_ id: String, to index: Int) throws {
        guard let source = tracks.firstIndex(where: { $0.id == id }),
            tracks.indices.contains(index)
        else { throw ProjectError.invalid("Invalid track reorder") }
        try requireBand(tracks[source], at: index, inserting: false)
        let track = tracks.remove(at: source)
        tracks.insert(track, at: index)
    }

    private mutating func setTrackProperties(id: String, patch: [String: JSONValue]) throws {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else {
            throw ProjectError.invalid("Unknown track: \(id)")
        }
        let protected: Set<String> = ["id", "kind", "items"]
        guard protected.isDisjoint(with: patch.keys) else {
            throw ProjectError.invalid("Track identity, kind and items cannot be patched")
        }
        for (key, value) in patch { tracks[index][key] = value }
    }

    private mutating func setProjectProperties(_ patch: [String: JSONValue]) throws {
        let protected: Set<String> = ["schema", "id", "rev", "format", "media", "tracks"]
        guard protected.isDisjoint(with: patch.keys) else {
            throw ProjectError.invalid("Project identity, format, media and tracks cannot be patched")
        }
        for (key, value) in patch { self[key] = value }
    }

    private mutating func insertItem(track: String, item: Item) throws {
        guard item.at >= 0, item.duration > 0, item.at <= 2_000_000_000 - item.duration else {
            throw ProjectError.invalid("Invalid inserted timeline range")
        }
        guard let index = tracks.firstIndex(where: { $0.id == track }) else {
            throw ProjectError.invalid("Unknown track: \(track)")
        }
        tracks[index].items.append(item)
    }

    private mutating func setItemProperties(id: String, patch: [String: JSONValue]) throws {
        let (track, index) = try location(id)
        let protected: Set<String> = ["id", "media", "at", "dur", "in", "linkedAudio", "linkedVideo"]
        guard protected.isDisjoint(with: patch.keys) else {
            throw ProjectError.invalid("Use timeline operations to change identity or timing")
        }
        for (key, value) in patch {
            if Item.removableFields.contains(key), value == .null {
                tracks[track].items[index].fields.removeValue(forKey: key)
            } else {
                tracks[track].items[index].fields[key] = value
            }
        }
    }

    private mutating func deleteItem(id: String, ripple: Bool) throws {
        let (track, index) = try location(id)
        let item = tracks[track].items.remove(at: index)
        if ripple { try shift(track: track, from: item.end, by: -item.duration) }
    }

    private mutating func splitItem(id: String, frame: Int, newID: String) throws {
        let (track, index) = try location(id)
        let original = tracks[track].items[index]
        guard frame > original.at && frame < original.end else {
            throw ProjectError.invalid("Split must be inside the item")
        }
        var right = original
        right.fields["id"] = .string(newID)
        right.at = frame
        right.duration = original.end - frame
        right.sourceIn = try sum(right.sourceIn, sourceOffset(frame - original.at, item: original))
        right.shiftTimedContent(by: original.at - frame)
        tracks[track].items[index].duration = frame - original.at
        if let curve = original.speedCurve {
            // Each half keeps its part of the ramp, and its own average speed.
            let cut = Double(frame - original.at) / Double(original.duration)
            tracks[track].items[index].setSpeedCurve(curve.cut(from: 0, to: cut))
            right.setSpeedCurve(curve.cut(from: cut, to: 1))
        }
        tracks[track].items.insert(right, at: index + 1)
    }

    mutating func trimItem(id: String, edge: Edge, frame: Int, ripple: Bool) throws {
        let (track, index) = try location(id)
        let original = tracks[track].items[index]
        var trimmed = original
        guard frame >= 0, frame <= 2_000_000_000 else {
            throw ProjectError.invalid("Invalid trim frame")
        }
        switch edge {
        case .start:
            guard frame < original.end else { throw ProjectError.invalid("Empty trim") }
            trimmed.sourceIn = try sum(
                trimmed.sourceIn, sourceOffset(frame - original.at, item: original))
            trimmed.duration = original.end - frame
            trimmed.at = ripple ? original.at : frame
            trimmed.shiftTimedContent(by: original.at - frame)
        case .end:
            guard frame > original.at else { throw ProjectError.invalid("Empty trim") }
            trimmed.duration = frame - original.at
        }
        if let curve = original.speedCurve {
            trimmed.setSpeedCurve(curve.trimmed(edge: edge, by: frame - (edge == .start ? original.at : original.end),
                                                duration: original.duration))
        }
        tracks[track].items[index] = trimmed
        if ripple {
            try shift(track: track, from: original.end, by: trimmed.duration - original.duration)
        }
    }

    private mutating func moveItem(id: String, destination: String, frame: Int) throws {
        guard frame >= 0, frame <= 2_000_000_000 else {
            throw ProjectError.invalid("Invalid move frame")
        }
        let (track, index) = try location(id)
        guard let target = tracks.firstIndex(where: { $0.id == destination }),
            tracks[target].kind == tracks[track].kind
        else {
            throw ProjectError.invalid("Move requires a compatible track")
        }
        var item = tracks[track].items.remove(at: index)
        item.at = frame
        tracks[target].items.append(item)
    }

    private mutating func reorderItem(id: String, before beforeID: String?) throws {
        let (trackIndex, _) = try location(id)
        guard tracks[trackIndex].magnetic else {
            throw ProjectError.invalid("Reorder requires a magnetic track")
        }
        var ordered = tracks[trackIndex].items.sorted {
            $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at
        }
        guard let source = ordered.firstIndex(where: { $0.id == id }) else {
            throw ProjectError.invalid("Unknown item: \(id)")
        }
        let item = ordered.remove(at: source)
        if let beforeID {
            guard beforeID != id, let destination = ordered.firstIndex(where: { $0.id == beforeID }) else {
                throw ProjectError.invalid("Invalid magnetic destination")
            }
            ordered.insert(item, at: destination)
        } else {
            ordered.append(item)
        }
        var frame = tracks[trackIndex].items.map(\.at).min() ?? 0
        var linkedFrames: [(String, Int)] = []
        for index in ordered.indices {
            ordered[index].at = frame
            if let linked = ordered[index].linkedItemID { linkedFrames.append((linked, frame)) }
            frame = try sum(frame, ordered[index].duration)
        }
        tracks[trackIndex].items = ordered
        for (linkedID, linkedFrame) in linkedFrames {
            let linked = try location(linkedID)
            tracks[linked.0].items[linked.1].at = linkedFrame
        }
    }

    mutating func shift(track: Int, from frame: Int, by delta: Int) throws {
        for index in tracks[track].items.indices where tracks[track].items[index].at >= frame {
            tracks[track].items[index].at = try sum(tracks[track].items[index].at, delta)
        }
    }
}
