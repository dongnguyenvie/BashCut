import Foundation

/// `slip` and `roll`: trims that keep the clip's place (slip changes only the source start) or move a shared cut
/// between two neighbours (roll).
extension Project {
    /// Source frames of `item`'s media played over its first `frames` timeline frames.
    func sourceOffset(_ frames: Int, item: Item) throws -> Int {
        guard let asset = media.first(where: { $0.id == item.mediaID }) else { return 0 }
        // A cut at a fractional source frame rounds down so the right half cannot overrun the source.
        let offset = (item.sourceSeconds(afterFrames: frames, fps: fps) * asset.fps.value).rounded(.down)
        guard offset.isFinite, offset > Double(Int.min), offset < Double(Int.max) else {
            throw ProjectError.invalid("Source frame overflow")
        }
        return Int(offset)
    }

    mutating func slipItem(id: String, sourceIn: Int) throws {
        let (track, index) = try location(id)
        guard tracks[track].items[index].mediaID != nil, sourceIn >= 0, sourceIn <= 2_000_000_000 else {
            throw ProjectError.invalid("Slip requires a media item and a valid source frame")
        }
        tracks[track].items[index].sourceIn = sourceIn
    }

    mutating func rollItem(id: String, edge: Edge, frame: Int) throws {
        let (track, index) = try location(id)
        let selected = tracks[track].items[index]
        let neighbors = tracks[track].items.filter {
            $0.id != id && (edge == .start ? $0.end == selected.at : $0.at == selected.end)
        }
        guard neighbors.count == 1, let neighbor = neighbors.first else {
            throw ProjectError.invalid("Roll requires exactly one adjacent clip on the same track")
        }
        let left = edge == .start ? neighbor : selected
        let right = edge == .start ? selected : neighbor
        guard frame > left.at, frame < right.end else {
            throw ProjectError.invalid("A rolling trim must leave both clips nonempty")
        }
        var moved = Set<String>()
        try trimItem(id: left.id, edge: .end, frame: frame, ripple: false, moved: &moved)
        try trimItem(id: right.id, edge: .start, frame: frame, ripple: false, moved: &moved)
    }
}
