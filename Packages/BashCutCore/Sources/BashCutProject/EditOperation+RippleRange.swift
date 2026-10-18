import Foundation

/// `rippleDeleteRange`: cuts the timeline span `[from, to)` out of every layer (or the given ones) in one edit.
///
/// On each layer, items inside the span go, items over one edge are trimmed to it, and items over the whole span lose
/// its middle: a clip is split and its two parts joined at `from`, while an item without media (text, captions) stays
/// one item that is shorter, its words and keyframes inside the span dropped. On a continuous layer (music by default)
/// an item keeps its source running and loses its tail instead, so a bed does not jump. Everything after the span
/// moves left by its length, with the markers, sections and beat grid. A linked clip's sound gets the same cut as
/// its picture, so the layers of linked partners are cut too. Transitions on removed cuts go; a transition after a
/// split part moves to its right part.
extension Project {
    public static let rippleRangeSuffix = "-cut"

    mutating func rippleDeleteRange(from: Int, to: Int, tracks scope: [String]?, continuous: [String]?) throws {
        guard from >= 0, to > from, to <= EditOperation.maximumFrame else {
            throw ProjectError.invalid("rippleDeleteRange: from must be before to")
        }
        let layers = try cutLayers(scope, from: from)
        let beds = Set(continuous ?? tracks.filter { $0.role == TrackRole.music }.map(\.id))
        let length = to - from
        var used = Set(tracks.flatMap { $0.items.map(\.id) })
        var rightParts: [String: String] = [:]
        for index in tracks.indices where layers.contains(tracks[index].id) {
            var kept: [Item] = []
            for item in tracks[index].items {
                let bed = beds.contains(tracks[index].id) && item.linkedItemID == nil
                kept += try cut(item, from: from, to: to, bed: bed) { base in
                    var id = base + Self.rippleRangeSuffix, counter = 2
                    while used.contains(id) {
                        id = base + Self.rippleRangeSuffix + "\(counter)"
                        counter += 1
                    }
                    used.insert(id)
                    rightParts[base] = id
                    return id
                }
            }
            tracks[index].items = kept
        }
        followRightParts(rightParts)
        let main = tracks.first { $0.role == TrackRole.main && $0.kind == "video" }
        if main.map({ layers.contains($0.id) }) ?? (scope == nil), !markers.isEmpty {
            markers = shiftedMarkers(from: to, by: -length)
        }
        rippleBeatGrid(from: from, to: to, beds: beds, layers: layers)
    }

    /// The layers a cut of `[from, to)` limited to `scope` (nil: all) edits, with the layers of the linked partners
    /// of the items it cuts or moves.
    private func cutLayers(_ scope: [String]?, from: Int) throws -> Set<String> {
        let all = Set(tracks.map(\.id))
        guard let scope else { return all }
        if let unknown = scope.first(where: { !all.contains($0) }) { throw ProjectError.invalid("Unknown layer \(unknown)") }
        var layers = Set(scope)
        for track in tracks where layers.contains(track.id) {
            for item in track.items where item.end > from {
                if let partner = item.linkedItemID, let (index, _) = try? location(partner) { layers.insert(tracks[index].id) }
            }
        }
        return layers
    }

    /// What is left of `item` after cutting `[from, to)` and closing the span; `newID` names a split's right part.
    private func cut(_ item: Item, from: Int, to: Int, bed: Bool, newID: (String) -> String) throws -> [Item] {
        let length = to - from
        if item.end <= from { return [item] }
        if item.at >= to {
            var moved = item
            moved.at = item.at - length
            return [moved]
        }
        if item.at >= from && item.end <= to { return [] }
        if item.at >= from || item.end <= to { return try cutOverEdge(item, from: from, to: to, bed: bed) }
        return try cutOverSpan(item, from: from, to: to, bed: bed, newID: newID)
    }

    private func cutOverEdge(_ item: Item, from: Int, to: Int, bed: Bool) throws -> [Item] {
        // Over the start edge: the end is trimmed to the cut.
        if item.at < from { return [trimmedEnd(item, to: from)].compactMap { $0 } }
        // Over the end edge: the start is trimmed to the span's end and the rest moves to the cut; a bed loses its
        // tail instead, so its sound runs on from where it started.
        var right = bed ? trimmedTail(item, by: to - item.at) : try trimmedStart(item, to: to)
        right?.at = from
        return [right].compactMap { $0 }
    }

    private func cutOverSpan(_ item: Item, from: Int, to: Int, bed: Bool, newID: (String) -> String) throws -> [Item] {
        if bed { return [trimmedTail(item, by: to - from)] }
        if item.mediaID == nil { return [joinedText(item, from: from, to: to)].compactMap { $0 } }
        // A clip is split and its parts joined; each keeps its part of a speed ramp.
        guard var left = trimmedEnd(item, to: from), var right = try trimmedStart(item, to: to) else {
            return [trimmedEnd(item, to: from), try trimmedStart(item, to: to)].compactMap { $0 }
        }
        for key in ["exit", "fadeOut"] { left.fields.removeValue(forKey: key) }
        for key in ["enter", "fadeIn"] { right.fields.removeValue(forKey: key) }
        right.fields["id"] = .string(newID(item.id))
        right.at = from
        return [left, right]
    }

    /// The item ending at `frame`, its words past it dropped; nil when no word is left of a worded caption.
    private func trimmedEnd(_ item: Item, to frame: Int) -> Item? {
        var trimmed = item
        trimmed.duration = frame - item.at
        if let curve = item.speedCurve {
            trimmed.setSpeedCurve(curve.trimmed(edge: .end, by: frame - item.end, duration: item.duration))
        }
        return trimmed.keepingWords { $0 < trimmed.duration }
    }

    /// The item starting at `frame` (its source and keyframes follow, like a trim), or nil when no word is left.
    private func trimmedStart(_ item: Item, to frame: Int) throws -> Item? {
        var trimmed = item
        trimmed.sourceIn = try sum(item.sourceIn, sourceOffset(frame - item.at, item: item))
        trimmed.duration = item.end - frame
        trimmed.at = frame
        trimmed.shiftTimedContent(by: item.at - frame)
        if let curve = item.speedCurve {
            trimmed.setSpeedCurve(curve.trimmed(edge: .start, by: frame - item.at, duration: item.duration))
        }
        return trimmed.keepingWords { $0 >= 0 }
    }

    /// A bed `frames` shorter at its end, its source and start unchanged.
    private func trimmedTail(_ item: Item, by frames: Int) -> Item {
        var shortened = item
        shortened.duration = item.duration - frames
        if let curve = item.speedCurve {
            shortened.setSpeedCurve(curve.trimmed(edge: .end, by: -frames, duration: item.duration))
        }
        return shortened
    }

    /// A text item over the whole span made one item without it: its words and keyframes inside go, later ones move
    /// to the cut. Nil when no word is left of a worded caption.
    private func joinedText(_ item: Item, from: Int, to: Int) -> Item? {
        let start = from - item.at, end = to - item.at, length = to - from
        var joined = item
        joined.duration = item.duration - length
        if let motion = item.motion {
            var keys: [String: [ItemMotion.Key]] = [:]
            for (property, list) in motion.keys {
                let left = list.filter { $0.frame < start || $0.frame >= end }.map { key in
                    key.frame >= end ? ItemMotion.Key(frame: key.frame - length, value: key.value, ease: key.ease) : key
                }
                if !left.isEmpty { keys[property] = left }
            }
            joined.fields["keyframes"] = keys.isEmpty ? nil : ItemMotion(keys: keys).json
        }
        return joined.keepingWords(shiftingFrom: end, by: -length) { $0 < start || $0 >= end }
    }

    /// Right parts of split clips link to each other's right parts, and take the transitions after their clip.
    private mutating func followRightParts(_ rightParts: [String: String]) {
        guard !rightParts.isEmpty else { return }
        for right in rightParts.values {
            guard let (track, index) = try? location(right) else { continue }
            for key in ["linkedAudio", "linkedVideo"] {
                guard let partner = tracks[track].items[index].fields[key]?.string else { continue }
                tracks[track].items[index].fields[key] = rightParts[partner].map(JSONValue.string)
            }
        }
        transitions = transitions.map { transition in
            guard let right = rightParts[transition.fromItemID] else { return transition }
            var moved = transition
            moved.fields["from"] = .string(right)
            return moved
        }
    }

    /// The beat grid follows the cut: beats inside the span go and later ones move, unless its music is a bed that
    /// kept running, whose beats stay where they are (those past the new end go).
    private mutating func rippleBeatGrid(from: Int, to: Int, beds: Set<String>, layers: Set<String>) {
        guard var grid = self["beatGrid"]?.object, let media = grid["media"]?.string,
            let frames = grid["frames"]?.array.compactMap(\.int)
        else { return }
        let playing = tracks.filter { layers.contains($0.id) && $0.items.contains { $0.mediaID == media } }
        let kept = !playing.isEmpty && playing.allSatisfy { beds.contains($0.id) }
        let end = duration
        let moved = frames.compactMap { frame -> Int? in
            if kept { return frame <= end ? frame : nil }
            if frame < from { return frame }
            return frame >= to ? frame - (to - from) : nil
        }
        guard moved != frames else { return }
        if moved.isEmpty {
            self["beatGrid"] = nil
        } else {
            grid["frames"] = .array(moved.map(JSONValue.integer))
            self["beatGrid"] = .object(grid)
        }
    }
}

extension Item {
    /// The item with only the words whose middle passes `keep` (frames from its start), later ones moved by `delta`
    /// from `shiftFrom`, and its text made of the kept words. Items without matching word timings come back as they
    /// are; nil when every word went.
    fileprivate func keepingWords(
        shiftingFrom shiftFrom: Int = .max, by delta: Int = 0, _ keep: (Int) -> Bool
    ) -> Item? {
        guard case .array(let list) = fields["words"], list.count == CaptionWords.tokens(text).count else { return self }
        let tokens = CaptionWords.tokens(text)
        var words: [JSONValue] = []
        var kept: [String] = []
        for (word, token) in zip(list, tokens) {
            var entry = word.object
            guard let at = entry["at"]?.int else { return self }
            let middle = at + max(1, entry["dur"]?.int ?? 1) / 2
            guard keep(middle) else { continue }
            if at >= shiftFrom { entry["at"] = .integer(at + delta) }
            if let wordAt = entry["at"]?.int, let length = entry["dur"]?.int {
                // A word cut by the item's new edge ends there.
                let start = max(0, wordAt)
                entry["at"] = .integer(start)
                entry["dur"] = .integer(max(1, min(length - (start - wordAt), duration - start)))
            }
            words.append(.object(entry))
            kept.append(token)
        }
        guard !words.isEmpty else { return nil }
        guard words.count != list.count else {
            var item = self
            item.fields["words"] = .array(words)
            return item
        }
        var item = self
        item.fields["words"] = .array(words)
        item.fields["text"] = .string(kept.joined(separator: " "))
        return item
    }
}
