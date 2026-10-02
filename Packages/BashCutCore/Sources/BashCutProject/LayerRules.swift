import Foundation

// Layer rules, enforced by `Project.validate()`:
// - Visual layers (video, adjustment, text) come first in `tracks`, back to front; audio layers follow and are mixed.
// - Exactly one main video layer.
// - Items never overlap on one layer; overlapping content lives on separate layers.
// - Audio media never sits on a visual layer; audio layers take audio media or video media with sound.

extension Track {
    public var isVisual: Bool { kind != "audio" }

    /// Whether `[at, at + duration)` is free on this layer, ignoring `ignoring` item IDs.
    public func isFree(at: Int, duration: Int, ignoring: Set<String> = []) -> Bool {
        let end = at + duration
        return !items.contains { !ignoring.contains($0.id) && $0.at < end && at < $0.end }
    }
}

extension Project {
    func validateLayers() throws {
        if let firstAudio = tracks.firstIndex(where: { !$0.isVisual }),
            let misplaced = tracks[firstAudio...].first(where: \.isVisual)
        {
            throw ProjectError.invalid("track.\(misplaced.id): visual layers must stay above audio layers")
        }
        let mains = tracks.filter { $0.role == TrackRole.main }
        guard mains.count == 1, mains[0].kind == "video" else {
            throw ProjectError.invalid("tracks: expected exactly one main video layer")
        }
        let mediaByID = Dictionary(media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for track in tracks {
            let items = track.items.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
            for (previous, item) in zip(items, items.dropFirst()) where item.at < previous.end {
                throw ProjectError.invalid(
                    "item.\(item.id): overlaps \(previous.id) on layer \(track.id); place it on another layer")
            }
            guard track.kind == "video" || track.kind == "audio" else { continue }
            for item in items {
                guard let asset = item.mediaID.flatMap({ mediaByID[$0] }) else { continue }
                let fits = track.isVisual ? asset.kind != "audio" : asset.kind == "audio" || asset.hasAudio != false
                guard fits else {
                    throw ProjectError.invalid("item.\(item.id): \(asset.kind) media cannot go on a \(track.kind) layer")
                }
            }
        }
    }

    /// A unique ID for a new layer of `kind`, such as `v3`, `fx1`, `t2` or `a5`.
    public func newTrackID(kind: String) -> String {
        let prefix = ["video": "v", Track.adjustmentKind: "fx", "text": "t", "audio": "a"][kind] ?? "track"
        var number = tracks.filter { $0.kind == kind }.count + 1
        while tracks.contains(where: { $0.id == "\(prefix)\(number)" }) { number += 1 }
        return "\(prefix)\(number)"
    }

    /// An empty layer that takes overflow from `source`: same kind and settings, never magnetic, and the
    /// main layer overflows onto overlay layers.
    public func overflowTrack(from source: Track) -> Track {
        let role = source.role == TrackRole.main ? TrackRole.overlay : source.role
        var track = Track(id: newTrackID(kind: source.kind), kind: source.kind, role: role)
        for (key, value) in source.fields where !["id", "items", "name", "magnetic", "role"].contains(key) {
            track.fields[key] = value
        }
        track.name = "\(role.capitalized) \(tracks.filter { $0.role == role }.count + 1)"
        return track
    }

    /// The index where a new layer of `kind` goes by default: text at the front of the visual stack,
    /// video in front of the other video layers but behind adjustments and text, adjustments in front of the
    /// picture but behind text (so captions are not graded), audio at the bottom of the audio stack.
    public func defaultTrackIndex(kind: String) -> Int {
        let visualEnd = tracks.firstIndex(where: { !$0.isVisual }) ?? tracks.count
        switch kind {
        case "audio": return tracks.count
        case "video": return (tracks[..<visualEnd].lastIndex(where: { $0.kind == "video" }) ?? -1) + 1
        case Track.adjustmentKind:
            return (tracks[..<visualEnd].lastIndex(where: { $0.kind == "video" || $0.isAdjustment }) ?? -1) + 1
        default: return visualEnd
        }
    }

    /// Where an overflow layer for `source` goes: after the last layer of the same kind and role at or after
    /// `source`, so overflow layers keep their creation order.
    func overflowIndex(for source: Track, role: String) -> Int {
        guard let index = tracks.firstIndex(where: { $0.id == source.id }) else { return tracks.count }
        let last = tracks.indices.last { $0 >= index && tracks[$0].kind == source.kind && tracks[$0].role == role }
        return (last ?? index) + 1
    }

    /// Rejects a layer index outside the visual or audio band, naming the layer.
    func requireBand(_ track: Track, at index: Int, inserting: Bool) throws {
        let visual = tracks.filter(\.isVisual).count + (inserting && track.isVisual ? 1 : 0)
        let allowed = track.isVisual ? 0..<visual : visual..<(tracks.count + (inserting ? 1 : 0))
        guard allowed.contains(index) else {
            throw ProjectError.invalid(
                track.isVisual
                    ? "Layer \(track.id) is \(track.kind); visual layers stay above audio layers"
                    : "Layer \(track.id) is audio; audio layers stay below visual layers")
        }
    }

    /// The index range a layer of `kind` may move within.
    public func trackBand(kind: String) -> Range<Int> {
        let visual = tracks.filter(\.isVisual).count
        return kind == "audio" ? visual..<tracks.count : 0..<visual
    }

    /// Repairs projects saved before layer rules existed: visual layers first, one main layer, and
    /// overlapping items moved onto new layers next to their original layer. Valid projects are unchanged.
    public func normalizingLayers() -> Project {
        var project = self
        var tracks = self.tracks.filter(\.isVisual) + self.tracks.filter { !$0.isVisual }
        var sawMain = false
        for index in tracks.indices where tracks[index].role == TrackRole.main {
            if sawMain || tracks[index].kind != "video" {
                tracks[index].fields["role"] = .string(TrackRole.overlay)
                tracks[index].fields["magnetic"] = .bool(false)
            } else {
                sawMain = true
            }
        }
        project.tracks = tracks
        if !sawMain {
            project.tracks.insert(Track(id: project.newTrackID(kind: "video"), kind: "video", role: TrackRole.main, magnetic: true), at: 0)
        }
        var index = 0
        while index < project.tracks.count {
            var lanes: [[Item]] = []
            for item in project.tracks[index].items.sorted(by: { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }) {
                if let lane = lanes.firstIndex(where: { ($0.last?.end ?? 0) <= item.at }) {
                    lanes[lane].append(item)
                } else {
                    lanes.append([item])
                }
            }
            for lane in lanes.dropFirst().reversed() {
                var overflow = project.overflowTrack(from: project.tracks[index])
                overflow.items = lane
                project.tracks.insert(overflow, at: index + 1)
            }
            if let first = lanes.first, lanes.count > 1 { project.tracks[index].items = first }
            index += lanes.count > 1 ? lanes.count : 1
        }
        return project
    }
}

/// Plans placements CapCut-style: content dropped on an occupied range goes to the next free layer
/// with the same kind and role, or to a new layer right next to the target. Each step is applied to a
/// scratch copy, so several placements in one edit see each other.
public struct LayerPlanner {
    public private(set) var project: Project
    public private(set) var operations: [EditOperation] = []

    public init(_ project: Project) { self.project = project }

    /// Applies operations to the scratch project and records them; they are validated together.
    public mutating func add(_ operations: [EditOperation]) throws {
        guard !operations.isEmpty else { return }
        let step = operations.count == 1 ? operations[0] : .group(label: "Plan", author: .user, ops: operations)
        project = try project.applying(step).project
        self.operations += operations
    }

    /// A layer where `[at, at + duration)` is free, starting from `trackID`; adds a layer when needed.
    public mutating func freeTrack(near trackID: String, at: Int, duration: Int, ignoring: Set<String> = []) throws -> String {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else {
            throw ProjectError.invalid("Unknown track: \(trackID)")
        }
        let source = project.tracks[index]
        if source.isFree(at: at, duration: duration, ignoring: ignoring) { return source.id }
        let role = source.role == TrackRole.main ? TrackRole.overlay : source.role
        if let free = project.tracks[index...].first(where: {
            $0.kind == source.kind && $0.role == role && $0.isFree(at: at, duration: duration, ignoring: ignoring)
        }) {
            return free.id
        }
        let overflow = project.overflowTrack(from: source)
        try add([.addTrack(track: overflow, atIndex: project.overflowIndex(for: source, role: role))])
        return overflow.id
    }

    /// Places an item on `trackID`, or on a free layer next to it. Returns the layer used.
    @discardableResult
    public mutating func place(_ item: Item, on trackID: String) throws -> String {
        let target = try freeTrack(near: trackID, at: item.at, duration: item.duration)
        try add([.insert(track: target, item: item)])
        return target
    }

    /// Places media on a layer. Video with sound on a video layer also gets a reciprocal linked item on a
    /// dialogue layer, so picture and sound edit together.
    public mutating func placeMedia(
        _ media: Media, on trackID: String, at frame: Int, duration: Int, itemID: String = UUID().uuidString
    ) throws {
        if !project.media.contains(where: { $0.id == media.id }) {
            // Callers add the media in the same edit; the scratch copy needs it to validate placements.
            project = try project.applying(.addMedia(media)).project
        }
        var item = Item(id: itemID, media: media.id, at: frame, duration: duration)
        let target = try freeTrack(near: trackID, at: frame, duration: duration)
        guard project.track(id: target)?.kind == "video", media.hasAudio == true,
            let dialogue = project.track(role: TrackRole.dialogue, kind: "audio")
        else { return try add([.insert(track: target, item: item)]) }
        let audioID = itemID + "-audio"
        let audioTarget = try freeTrack(near: dialogue.id, at: frame, duration: duration)
        item.fields["linkedAudio"] = .string(audioID)
        var audio = Item(id: audioID, media: media.id, at: frame, duration: duration)
        audio.fields["linkedVideo"] = .string(itemID)
        try add([.insert(track: audioTarget, item: audio), .insert(track: target, item: item)])
    }

    /// Moves an item (and its linked partner) to `frame` on `trackID`, spilling onto free layers when the
    /// destination range is occupied.
    public mutating func move(_ itemID: String, to trackID: String, at frame: Int) throws {
        guard let item = project.tracks.flatMap(\.items).first(where: { $0.id == itemID }) else {
            throw ProjectError.invalid("Unknown item: \(itemID)")
        }
        let linkedID = item.linkedItemID
        let ignoring = Set([itemID] + (linkedID.map { [$0] } ?? []))
        let target = try freeTrack(near: trackID, at: frame, duration: item.duration, ignoring: ignoring)
        var operations: [EditOperation] = [.move(item: itemID, toTrack: target, atFrame: frame)]
        if let linkedID, let linkedTrack = project.tracks.first(where: { $0.items.contains { $0.id == linkedID } }),
            let linked = linkedTrack.items.first(where: { $0.id == linkedID })
        {
            let linkedTarget = try freeTrack(
                near: linkedTrack.id, at: frame, duration: linked.duration, ignoring: ignoring)
            if linkedTarget != linkedTrack.id {
                // Moving the partner also re-places `itemID` on its new layer at the same frame.
                operations.append(.move(item: linkedID, toTrack: linkedTarget, atFrame: frame))
            }
        }
        try add(operations)
    }
}
