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
        return .group(
            label: "Delete gap", author: .user,
            ops: later.map { .move(item: $0.id, toTrack: trackID, atFrame: $0.at - gap.count) })
    }
}
