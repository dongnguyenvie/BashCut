import Foundation

extension Track {
    /// Empty ranges between the start of the timeline and the last item, in timeline order.
    public var gaps: [Range<Int>] {
        var result: [Range<Int>] = []
        var cursor = 0
        for item in items.sorted(by: { $0.at < $1.at }) {
            if item.at > cursor { result.append(cursor..<item.at) }
            cursor = max(cursor, item.end)
        }
        return result
    }
}

extension Project {
    /// The gap on `trackID` that contains `frame`.
    public func gap(on trackID: String, containing frame: Int) throws -> Range<Int> {
        guard let track = tracks.first(where: { $0.id == trackID }) else {
            throw ProjectError.invalid("Unknown layer \(trackID)")
        }
        guard let gap = track.gaps.first(where: { $0.contains(frame) }) else {
            throw ProjectError.invalid("No gap at frame \(frame) on \(track.name)")
        }
        return gap
    }

    /// Closes the gap on `trackID` that contains `frame` by moving every later item on that layer left by the
    /// gap's length (linked sound follows its picture), as one undoable edit.
    public func closingGap(on trackID: String, containing frame: Int) throws -> EditOperation {
        let gap = try gap(on: trackID, containing: frame)
        let later = (tracks.first { $0.id == trackID }?.items ?? [])
            .filter { $0.at >= gap.upperBound }.sorted { $0.at < $1.at }
        var ops: [EditOperation] = later.map { .move(item: $0.id, toTrack: trackID, atFrame: $0.at - gap.count) }
        if tracks.first(where: { $0.id == trackID })?.role == TrackRole.main {
            // Sections on the main layer follow its clips (#507-11): removed ones first, then the moved ones in order.
            let shifted = shiftedMarkers(from: gap.upperBound, by: -gap.count)
            let kept = Dictionary(shifted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let sections = sectionMarkers
            ops += sections.filter { kept[$0.id] == nil }.map { .deleteSection(id: $0.id) }
            ops += sections.compactMap { section in
                guard let moved = kept[section.id], moved.at != section.at else { return nil }
                return .upsertSection(id: section.id, label: section.label, atFrame: moved.at)
            }
        }
        return .group(label: "Delete gap", author: .user, ops: ops)
    }

    /// Moves every item on `track` that starts at or after `frame` by `delta`. A ripple on the main layer moves the
    /// timeline's markers with it (#507-11), from `markersFrom` (the edited edge) when markers inside the edited clip
    /// move too.
    ///
    /// The linked partner of each moved item moves with it when it sits on another layer, so a clip's sound stays in
    /// sync though its own layer was not rippled. `moved` holds what this operation's ripples already moved: a
    /// partner moved with its clip is not moved again by its own layer's ripple.
    mutating func shift(track: Int, from frame: Int, by delta: Int, markersFrom: Int? = nil, moved: inout Set<String>) throws {
        var partners: [String] = []
        for index in tracks[track].items.indices where tracks[track].items[index].at >= frame {
            let item = tracks[track].items[index]
            guard moved.insert(item.id).inserted else { continue }
            tracks[track].items[index].at = try sum(item.at, delta)
            if let partner = item.fields["linkedAudio"]?.string ?? item.fields["linkedVideo"]?.string { partners.append(partner) }
        }
        for partner in partners where !moved.contains(partner) {
            guard let (other, index) = try? location(partner), other != track else { continue }
            tracks[other].items[index].at = try sum(tracks[other].items[index].at, delta)
            moved.insert(partner)
        }
        if tracks[track].role == TrackRole.main, tracks[track].kind == "video", delta != 0, !markers.isEmpty {
            markers = shiftedMarkers(from: markersFrom ?? frame, by: delta)
        }
    }

    /// The markers after the main layer moves by `delta` from `frame`: later ones move with it; when time is removed
    /// (`delta` < 0), markers inside the removed part go to the cut, and of the sections that then share a frame
    /// only the one that started latest is kept, since it starts what is left.
    public func shiftedMarkers(from frame: Int, by delta: Int) -> [TimelineMarker] {
        let cut = frame + min(delta, 0)
        var moved: [(marker: TimelineMarker, original: Int)] = markers.map { marker in
            var marker = marker
            let at = marker.at
            if at >= frame {
                marker.fields["at"] = .integer(at + delta)
            } else if at >= cut {
                marker.fields["at"] = .integer(cut)
            }
            return (marker, at)
        }
        if delta < 0 {
            moved = moved.filter { entry in
                entry.marker.kind != "section" || !moved.contains { other in
                    other.marker.kind == "section" && other.marker.at == entry.marker.at && other.original > entry.original
                }
            }
        }
        return moved.map(\.marker)
    }
}
