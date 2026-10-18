import Foundation

/// Hand edits on what an apply built, kept through a later apply by a three-way merge. Every built item records what
/// the build itself set (`planBuilt`), so a later apply tells a hand edit (the item differs from its record) from a
/// list change (the new build differs from the record): a field changed by hand and not by the list since stays as it
/// was set by hand; one the list changed too takes the list's value. Merged are an item's sound (`volumeDb`, `muted`,
/// fades), picture (`transform` and `textStyle` key by key, `crop`, `keyframes`, `backdrop`, `fill`, `color`), a
/// title's `text`, and an entry's timing: the pieces a ripple cut, split or trim left of a clip (kept while its row
/// gives the same range), and where a line, title, graphic or sound starts. What an apply keeps and what it gives back
/// to the list is reported (`HandReport`), in plan check and `plan apply --dry-run` too.
extension PlanCut {
    /// What the build set on an item, as `{field: value}` with its `id` (a split part carries its origin's record).
    static let builtTag = "planBuilt"
    /// Whether an apply made captions from a built clip's media (a transcript was there).
    static let captionedTag = "planCaptioned"
    /// The level plan apply measured for the music bed (the record holds the list's: a fixed level or the fallback).
    public static let measuredTag = "planMeasured"
    /// Fields merged as one value.
    static let keptKeys = ["volumeDb", "muted", "fadeIn", "fadeOut", "crop", "keyframes", "backdrop", "fill", "color", "text"]
    /// Fields merged key by key.
    static let keptObjectKeys = ["transform", "textStyle"]

    /// What an apply keeps of the hand edits on what the last one built (`kept`), and what it gives back to the list
    /// because the list changed the same field (`overwritten`).
    public struct HandReport: Sendable {
        public var kept: [JSONValue] = []
        public var overwritten: [JSONValue] = []
        public var isEmpty: Bool { kept.isEmpty && overwritten.isEmpty }
        /// Whether the music bed keeps a level set by hand, so apply does not measure a new one.
        public var keepsMusicLevel: Bool {
            kept.contains { $0.object["item"] == .string("plan-music") && $0.object["field"] == .string("volumeDb") }
        }
        public var json: JSONValue { .object(["kept": .array(kept), "overwritten": .array(overwritten)]) }

        /// Words captions leave out because their cues were deleted by hand, by media.
        mutating func keepDeleted(_ words: [String: Int]) {
            for (media, count) in words.sorted(by: { $0.key < $1.key }) where count > 0 {
                keep("captions", "captions", "deleted", .object(["media": .string(media), "words": .integer(count)]))
            }
        }

        mutating func keep(_ item: String, _ entry: String, _ field: String, _ value: JSONValue) {
            kept.append(.object(["item": .string(item), "entry": .string(entry), "field": .string(field), "value": value]))
        }

        mutating func overwrite(_ item: String, _ entry: String, _ field: String, hand: JSONValue, list: JSONValue) {
            overwritten.append(.object([
                "item": .string(item), "entry": .string(entry), "field": .string(field), "hand": hand, "list": list,
            ]))
        }
    }

    /// The built items as the apply found them, the new build's records and what is merged so far.
    struct Keep {
        /// Items an earlier apply built (captions apart), by ID, with their layer.
        var old: [String: (item: Item, track: String)] = [:]
        /// Entries whose row is the one stored in plan.cut: for items built before records, what the new build sets
        /// stands for what the last one set.
        var unchanged: Set<String> = []
        /// Picture fields a row clears with null, by item ID: the list wins over a hand edit.
        var cleared: [String: Set<String>] = [:]
        /// The new build's record by item ID.
        var fresh: [String: [String: JSONValue]] = [:]
        /// The item of the new build whose record an item kept from before takes (its own ID, or a split's origin).
        var origin: [String: String] = [:]
        var merged = Set<String>()
        var report = HandReport()

        init(_ project: Project = Project(fields: [:]), spec: Spec? = nil) {
            for track in project.tracks {
                for item in track.items where item.fields[tag] != nil && item.fields[tag] != .string("captions") {
                    old[item.id] = (item, track.id)
                }
            }
            guard let spec else { return }
            let stored = project["plan"]?.object["cut"].map(entryRows) ?? [:]
            unchanged = Set(spec.rows.compactMap { id, row in stored[id].map { alike($0, row) } == true ? id : nil })
            cleared = clearedPictures(spec)
        }

        /// The value a field takes: the hand's when it differs from what the last build set and the list did not
        /// change it since, else the list's; either case is reported.
        mutating func merge(_ hand: JSONValue, was: JSONValue, list: JSONValue, at place: (item: String, entry: String, field: String)) -> JSONValue {
            guard !alike(hand, was) else { return list }
            if alike(list, was) {
                report.keep(place.item, place.entry, place.field, hand)
                return hand
            }
            if !alike(hand, list) { report.overwrite(place.item, place.entry, place.field, hand: hand, list: list) }
            return list
        }

        /// Whether an entry keeps the value set by hand (`now`) over the new build's: it differs from the last
        /// build's, which the new build gives again. Either case is reported, as `facts` gives the value.
        mutating func decide<T>(
            _ place: (item: String, entry: String, field: String), _ value: (now: T, last: T, built: T),
            same: (T, T) -> Bool, facts: (T) -> JSONValue
        ) -> Bool {
            guard !same(value.now, value.last) else { return false }
            if same(value.built, value.last) {
                report.keep(place.item, place.entry, place.field, facts(value.now))
                return true
            }
            if !same(value.now, value.built) {
                report.overwrite(place.item, place.entry, place.field, hand: facts(value.now), list: facts(value.built))
            }
            return false
        }

        func items(of entry: String) -> [(item: Item, track: String)] {
            old.values.filter { $0.item.fields[tag] == .string(entry) }.sorted { ($0.item.at, $0.item.id) < ($1.item.at, $1.item.id) }
        }

        /// What the last apply set on `item`: its record, or for an item built before records, the sound the build
        /// named (`planAudio`), no picture field it did not name (`planPicture`), and the rest as the new build's when
        /// the row is unchanged (so only what differs counts as by hand) or as the item's (nothing counts).
        func base(_ item: Item, fresh new: [String: JSONValue]) -> [String: JSONValue] {
            if let record = item[builtTag]?.object { return record }
            let same = item.fields[tag]?.string.map(unchanged.contains) ?? false
            let audio = item[audioTag]?.object ?? [:]
            let named = Set(item[pictureTag]?.array.compactMap(\.string) ?? [])
            var record: [String: JSONValue] = [:]
            for key in keptKeys + keptObjectKeys {
                if audioKeys.contains(key) {
                    record[key] = audio[key]
                } else if !pictureKeys.contains(key) || named.contains(key) {
                    record[key] = same ? new[key] : item[key]
                }
            }
            for key in ["at", "dur", "in"] { record[key] = same ? new[key] : item.fields[key] }
            return record
        }
    }

    /// The rows of a list by entry ID (`music` for the bed), IDs given or numbered as `decodeAll` numbers them.
    static func entryRows(_ value: JSONValue) -> [String: JSONValue] {
        var rows: [String: JSONValue] = [:]
        for (key, prefix) in [("clips", "c"), ("voiceover", "l"), ("titles", "t"), ("graphics", "g"), ("sfx", "s")] {
            for (index, row) in (value.object[key]?.array ?? []).enumerated() {
                rows[row.object["id"]?.string ?? "\(prefix)\(index + 1)"] = row
            }
        }
        if let music = value.object["music"], music != .null { rows["music"] = music }
        return rows
    }

    /// Picture fields clip, cover and overlay rows clear with null, by the item ID they build.
    static func clearedPictures(_ spec: Spec) -> [String: Set<String>] {
        var cleared: [String: Set<String>] = [:]
        let nulls = { (picture: [String: JSONValue]) in Set(picture.filter { $0.value == .null }.keys) }
        for clip in spec.clips {
            cleared["plan-" + clip.id] = nulls(clip.picture)
            for (index, shot) in clip.cover.enumerated() { cleared["plan-\(clip.id)-cover\(index + 1)"] = nulls(shot.picture) }
            for (index, overlay) in clip.overlays.enumerated() { cleared["plan-\(clip.id)-overlay\(index + 1)"] = nulls(overlay.picture) }
        }
        return cleared.filter { !$0.value.isEmpty }
    }

    /// The fields `keep` merges, as the build set them on `item`.
    static func record(_ item: Item) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "id": .string(item.id), "at": .integer(item.at), "dur": .integer(item.duration), "in": .integer(item.sourceIn),
        ]
        for key in keptKeys + keptObjectKeys {
            if let value = item[key], value != .null { fields[key] = value }
        }
        return fields
    }

    // MARK: Timing

    /// An entry's items relative to its start: (record ID, at, dur, in), in order.
    typealias Shape = [(id: String, at: Int, dur: Int, in: Int)]

    static func same(_ lhs: Shape, _ rhs: Shape) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.id == $1.id && $0.at == $1.at && $0.dur == $1.dur && $0.in == $1.in }
    }

    static func shape(_ items: [(id: String, at: Int, dur: Int, in: Int)]) -> (start: Int, shape: Shape) {
        let start = items.map(\.at).min() ?? 0
        return (start, items.map { ($0.id, $0.at - start, $0.dur, $0.in) }.sorted { ($0.at, $0.id) < ($1.at, $1.id) })
    }

    /// An entry's built items, and the items to put in their place.
    typealias Move = (entry: String, remove: [String], place: [(item: Item, track: String)])

    /// Puts back the timing set by hand on `entries` (built just now in `planner`): a clip's pieces when its row gives
    /// the range it gave before (a ripple cut, a split, a trim), and for an entry that does not follow the clips
    /// (`followsClips` false) its start, unless the list moved it too. Returns where each changed entry now lies.
    @discardableResult
    static func keepTiming(
        _ entries: [String], followsClips: Bool, keep: inout Keep, in planner: inout LayerPlanner
    ) throws -> [String: (at: Int, end: Int)] {
        let moves = entries.compactMap { timingMove($0, followsClips: followsClips, keep: &keep, project: planner.project) }
        var spans: [String: (at: Int, end: Int)] = [:]
        guard !moves.isEmpty else { return spans }
        // Everything moved goes first and comes back after, so pieces never meet the old places of others.
        for id in moves.flatMap(\.remove) where planner.project.tracks.contains(where: { $0.items.contains { $0.id == id } }) {
            try planner.add([.delete(item: id, ripple: false)])
        }
        for move in moves {
            // Linked partners go back in one step, each naming the other.
            do {
                try planner.add(move.place.map { EditOperation.insert(track: $0.track, item: $0.item) })
            } catch {
                for (item, track) in move.place { try planner.place(item, on: track) }
            }
            let placed = move.place.map(\.item)
            spans[move.entry] = (placed.map(\.at).min() ?? 0, placed.map(\.end).max() ?? 0)
        }
        return spans
    }

    /// What `keepTiming` does with one entry: nil when its built items stay as built.
    static func timingMove(_ entry: String, followsClips: Bool, keep: inout Keep, project: Project) -> Move? {
        let new = project.tracks.flatMap { track in track.items.map { ($0, track.id) } }.filter { $0.0.fields[tag] == .string(entry) }
        let old = keep.items(of: entry)
        guard !new.isEmpty, !old.isEmpty else { return nil }
        let fps = project.fps.value
        let built = shape(new.map { ($0.0.id, $0.0.at, $0.0.duration, $0.0.sourceIn) })
        let now = shape(old.map { piece in
            (originID(of: piece.item, track: piece.track, among: new), piece.item.at, piece.item.duration, piece.item.sourceIn)
        })
        let last = lastShape(old, new: new, keep: keep)
        let first = new.min { $0.0.at < $1.0.at }?.0.id ?? entry
        let keepsShape = keep.decide((first, entry, "timing"), (now.shape, last.shape, built.shape), same: same) {
            timingFacts($0, fps: fps)
        }
        let keepsStart = !followsClips && keep.decide((first, entry, "at"), (now.start, last.start, built.start), same: ==) {
            .number(seconds($0, fps: fps))
        }
        guard keepsShape || keepsStart else { return nil }
        let start = keepsStart ? now.start : built.start
        // The build's own items go, so their records are taken now.
        for (item, _) in new where keep.fresh[item.id] == nil { keep.fresh[item.id] = record(item) }
        guard keepsShape else {
            return (entry, new.map(\.0.id), new.map { piece in
                var item = piece.0
                item.at = start + item.at - built.start
                return (item, piece.1)
            })
        }
        return (entry, new.map(\.0.id), old.map { piece in
            var item = piece.item
            item.at = start + item.at - now.start
            keep.origin[item.id] = originID(of: piece.item, track: piece.track, among: new)
            return (item, piece.track)
        })
    }

    /// The shape and start the last apply gave an entry, from its items' records (split parts share their origin's).
    static func lastShape(_ old: [(item: Item, track: String)], new: [(Item, String)], keep: Keep) -> (start: Int, shape: Shape) {
        var records: [String: (Int, Int, Int)] = [:]
        for (item, track) in old {
            let id = originID(of: item, track: track, among: new)
            let built = keep.fresh[id] ?? new.first { $0.0.id == id }.map { PlanCut.record($0.0) } ?? [:]
            let record = keep.base(item, fresh: built)
            if let at = record["at"]?.int, let dur = record["dur"]?.int, let source = record["in"]?.int {
                records[id] = (at, dur, source)
            }
        }
        return shape(records.map { ($0.key, $0.value.0, $0.value.1, $0.value.2) })
    }

    /// The new build's item an item from before takes its record from: its record's ID, else its own ID when the
    /// build made one, else the build's first item of the entry on the same layer (a split part built before records).
    static func originID(of item: Item, track: String, among new: [(Item, String)]) -> String {
        if let id = item[builtTag]?.object["id"]?.string { return id }
        if new.contains(where: { $0.0.id == item.id }) { return item.id }
        return new.first { $0.1 == track }?.0.id ?? item.id
    }

    static func seconds(_ frames: Int, fps: Double) -> Double { (Double(frames) / fps * 100).rounded() / 100 }

    static func timingFacts(_ shape: Shape, fps: Double) -> JSONValue {
        let pictures = shape.filter { piece in !shape.contains { $0.at == piece.at && $0.id < piece.id && $0.dur == piece.dur } }
        return .object([
            "items": .integer(shape.count),
            "seconds": .number(seconds(pictures.map { $0.at + $0.dur }.max() ?? 0, fps: fps)),
        ])
    }

    // MARK: Fields

    /// Merges the hand-set fields back on the built items now in `planner` whose entry is in `entries` (all when nil)
    /// and records what the build set on each, once per item.
    static func keepFields(_ entries: Set<String>? = nil, keep: inout Keep, in planner: inout LayerPlanner) throws {
        let items = planner.project.tracks.flatMap(\.items).filter { item in
            guard let entry = item.fields[tag]?.string, entry != "captions" else { return false }
            return entries.map { $0.contains(entry) } ?? true
        }
        for item in items where keep.merged.insert(item.id).inserted {
            let originID = keep.origin[item.id] ?? item.id
            let fresh = keep.fresh[originID] ?? record(item)
            keep.fresh[originID] = fresh
            var patch: [String: JSONValue] = [builtTag: .object(fresh)]
            if let old = keep.old[item.id]?.item {
                for (key, value) in mergedFields(old, into: item, fresh: fresh, keep: &keep) where !alike(value, item[key] ?? .null) {
                    patch[key] = value
                }
            }
            try planner.add([.setProperties(item: item.id, patch: patch)])
        }
    }

    /// The merged value of each field `keep` merges on `item`, rebuilt from `old`.
    static func mergedFields(
        _ old: Item, into item: Item, fresh: [String: JSONValue], keep: inout Keep
    ) -> [String: JSONValue] {
        let entry = item.fields[tag]?.string ?? ""
        let base = keep.base(old, fresh: fresh)
        let cleared = keep.cleared[item.id] ?? []
        var fields: [String: JSONValue] = [:]
        for key in keptKeys where !cleared.contains(key) {
            let hand = old[key] ?? .null, list = fresh[key] ?? .null
            var was = base[key] ?? .null
            if item.id == "plan-music", key == "volumeDb" {
                // The bed's level was measured under the voice: hand-set while the list asks the same.
                if let measured = old[measuredTag] { was = measured }
                if musicLevelChanged(old, item), !alike(hand, was) {
                    if !alike(hand, list) { keep.report.overwrite(item.id, entry, key, hand: hand, list: list) }
                    was = hand
                }
            }
            fields[key] = keep.merge(hand, was: was, list: list, at: (item.id, entry, key))
        }
        for key in keptObjectKeys {
            let hand = old[key]?.object ?? [:], was = base[key]?.object ?? [:], list = fresh[key]?.object ?? [:]
            var merged: [String: JSONValue] = [:]
            for sub in Set(hand.keys).union(was.keys).union(list.keys).sorted() {
                let value = keep.merge(
                    hand[sub] ?? .null, was: was[sub] ?? .null, list: list[sub] ?? .null, at: (item.id, entry, "\(key).\(sub)"))
                if value != .null { merged[sub] = value }
            }
            fields[key] = merged.isEmpty ? .null : .object(merged)
        }
        return fields
    }

    /// Whether the list asks the bed for another level than the last apply: other music, a fixed level now or
    /// another one, or another level under the voice.
    static func musicLevelChanged(_ old: Item, _ new: Item) -> Bool {
        let was = old[musicTag]?.object ?? [:], now = new[musicTag]?.object ?? [:]
        if was["media"] != now["media"] { return true }
        // Beds built before the record of the level under the voice count as asking the same.
        guard let under = was["underVoiceDb"] else { return false }
        return !alike(under, now["underVoiceDb"] ?? .null)
    }

    /// Equal as JSON values, a whole number the same as its integer (a saved project reads -20.0 back as -20).
    static func alike(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.integer(let left), .number(let right)), (.number(let right), .integer(let left)): return Double(left) == right
        case (.object(let left), .object(let right)):
            return left.count == right.count && left.allSatisfy { key, value in right[key].map { alike(value, $0) } ?? false }
        case (.array(let left), .array(let right)): return left.count == right.count && zip(left, right).allSatisfy(alike)
        default: return lhs == rhs
        }
    }
}
