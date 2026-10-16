import Foundation

/// Captions follow a speed change (`setSpeed`, `setSpeedCurve`). Captions do not move with their clips in general
/// (a trim, move or ripple delete leaves them where they are), but a speed change rescales what the clip plays and
/// ripples the clips after it, so without this every caption made from that media would end up off its words. A
/// caption made from a media (`captionMedia`) is mapped through the clip of that media it was heard in: the frame
/// where the clip played that source second before is moved to the frame where it plays it now, for the caption's
/// edges and each of its word timings (a word whose middle the clip no longer plays is dropped). Captions of clips
/// the edit did not change, and captions typed or imported as timeline text, stay where they are.
extension Project {
    mutating func retimeCaptions(from before: Project) {
        let now = Dictionary(tracks.flatMap(\.items).map { ($0.id, $0) }) { first, _ in first }
        var heard: [String: [(item: Item, media: Media)]] = [:]
        var placing: [(track: String, item: Item)] = []
        // First take every caption to retime off its layer, so it is placed against the captions that stay.
        var taken = Set<String>()
        for track in tracks where track.role == TrackRole.captions {
            for caption in track.items {
                guard let mediaID = caption["captionMedia"]?.string else { continue }
                if heard[mediaID] == nil { heard[mediaID] = before.audibleClips(mediaID) }
                let middle = (caption.at + caption.end) / 2
                guard let (old, asset) = heard[mediaID]?.first(where: { $0.item.at <= middle && middle < $0.item.end }),
                    let new = now[old.id], new != old
                else { continue }
                taken.insert(caption.id)
                // A caption the clip no longer plays any of (less source at the same length) is removed.
                if let retimed = retimed(caption, from: old, to: new, media: asset, before: before) {
                    placing.append((track.id, retimed))
                }
            }
        }
        guard !taken.isEmpty else { return }
        for index in tracks.indices where tracks[index].role == TrackRole.captions {
            tracks[index].items.removeAll { taken.contains($0.id) }
        }
        for (trackID, caption) in placing.sorted(by: { $0.item.at < $1.item.at }) { place(caption, preferring: trackID) }
    }

    /// Puts a retimed caption back on its layer, or the next free caption layer, or a new one above them (as SubRip
    /// import stacks overlapping cues).
    private mutating func place(_ caption: Item, preferring trackID: String) {
        let layers = tracks.indices.filter { tracks[$0].role == TrackRole.captions && tracks[$0].kind == "text" }
        let own = tracks.firstIndex { $0.id == trackID }
        let lane = own.flatMap { tracks[$0].isFree(at: caption.at, duration: caption.duration) ? $0 : nil }
            ?? layers.first { tracks[$0].isFree(at: caption.at, duration: caption.duration) }
        if let lane {
            tracks[lane].items.append(caption)
            tracks[lane].items.sort { $0.at < $1.at }
        } else if let top = layers.last ?? own {
            var layer = overflowTrack(from: tracks[top])
            layer.items = [caption]
            tracks.insert(layer, at: top + 1)
        }
    }

    /// `caption` mapped from where `old` played its source to where `new` plays it, kept inside `new`.
    private func retimed(_ caption: Item, from old: Item, to new: Item, media: Media, before: Project) -> Item? {
        let start = Double(old.sourceIn) / media.fps.value
        let source = { (frame: Int) in start + old.sourceSeconds(afterFrames: frame - old.at, fps: before.fps) }
        let map = { (frame: Int) in min(new.end, max(new.at, self.frame(atSource: source(frame), in: new, media: media))) }
        let plays = sourceSpan(of: new, media: media)
        var item = caption
        item.at = map(caption.at)
        item.duration = map(caption.end) - item.at
        guard item.duration >= 1 else { return nil }
        if case .array(let words) = caption.fields["words"] {
            item.fields["words"] = .array(words.compactMap { word in
                var entry = word.object
                guard let at = entry["at"]?.int, let length = entry["dur"]?.int else { return word }
                // A word the clip no longer plays the middle of is not heard there any more (as placedCues keeps them).
                guard plays.contains((source(caption.at + at) + source(caption.at + at + length)) / 2) else { return nil }
                let from = min(item.duration - 1, max(0, map(caption.at + at) - item.at))
                entry["at"] = .integer(from)
                entry["dur"] = .integer(max(1, min(item.duration, map(caption.at + at + length) - item.at) - from))
                return .object(entry)
            })
        }
        return item
    }
}
