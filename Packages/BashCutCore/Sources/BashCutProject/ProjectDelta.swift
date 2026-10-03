import Foundation

/// A project written as its differences from another one, for the history journal: consecutive
/// snapshots share almost everything, so each step stores only the fields, layers and items it changed.
///
/// `{"set": {key: value}, "unset": [key], "tracks": [layer]}`, where a layer is the ID of an unchanged
/// base layer, or `{"track": {fields without items}, "items": [entry]}`. An item entry is `[start, count]`
/// (a run of unchanged items from the base layer with the same ID), the ID of an unchanged base item on
/// another layer, or the item itself. `"tracks"` is left out when no layer changed.
enum ProjectDelta {
    static func encode(_ target: Project, from base: Project) -> JSONValue {
        var delta: [String: JSONValue] = [:]
        var set: [String: JSONValue] = [:]
        for (key, value) in target.storage where base.storage[key] != value { set[key] = value }
        let unset = base.storage.keys.filter { target.storage[$0] == nil }.sorted()
        if !set.isEmpty { delta["set"] = .object(set) }
        if !unset.isEmpty { delta["unset"] = .array(unset.map(JSONValue.string)) }
        if target.hasTracks != base.hasTracks || target.tracks != base.tracks {
            delta["tracks"] = target.hasTracks ? .array(encode(target.tracks, from: base)) : .null
        }
        return .object(delta)
    }

    static func apply(_ value: JSONValue, to base: Project) throws -> Project {
        guard case .object(let delta) = value else { throw ProjectError.invalid("History delta: expected object") }
        var storage = base.storage
        for (key, value) in delta["set"]?.object ?? [:] { storage[key] = value }
        for key in delta["unset"]?.array ?? [] {
            guard let key = key.string else { throw ProjectError.invalid("History delta: invalid unset key") }
            storage[key] = nil
        }
        var hasTracks = base.hasTracks
        var tracks = base.tracks
        switch delta["tracks"] {
        case nil: break
        case .null?:
            hasTracks = false
            tracks = []
        case .array(let values)?:
            hasTracks = true
            tracks = try decode(values, from: base)
        case _?: throw ProjectError.invalid("History delta: invalid tracks")
        }
        return Project(storage: storage, hasTracks: hasTracks, tracks: tracks)
    }

    private static func encode(_ tracks: [Track], from base: Project) -> [JSONValue] {
        let baseTracks = Dictionary(base.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var baseItems: [String: Item]?
        return tracks.map { track in
            if let old = baseTracks[track.id], old == track, !track.id.isEmpty { return .string(track.id) }
            var value: [String: JSONValue] = ["track": .object(track.storage)]
            if track.hasItems {
                // Indexed lazily: most steps change only fields or one layer.
                let items = baseItems ?? Dictionary(
                    base.tracks.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                baseItems = items
                value["items"] = .array(encode(track.items, base: baseTracks[track.id]?.items ?? [], others: items))
            }
            return .object(value)
        }
    }

    private static func encode(_ items: [Item], base: [Item], others: [String: Item]) -> [JSONValue] {
        var entries: [JSONValue] = []
        var run: (start: Int, count: Int)?
        func flush() {
            if let run { entries.append(.array([.integer(run.start), .integer(run.count)])) }
            run = nil
        }
        var cursor = 0  // where the next base item is expected, so edits that keep order stay one run
        var positions: [String: Int]?
        for item in items {
            var position: Int?
            if cursor < base.count, base[cursor] == item {
                position = cursor
            } else {
                let index = positions ?? Dictionary(
                    base.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
                positions = index
                if let found = index[item.id], base[found] == item { position = found }
            }
            if let position {
                if let current = run, current.start + current.count == position {
                    run = (current.start, current.count + 1)
                } else {
                    flush()
                    run = (position, 1)
                }
                cursor = position + 1
                continue
            }
            flush()
            entries.append(others[item.id] == item && !item.id.isEmpty ? .string(item.id) : .object(item.fields))
        }
        flush()
        return entries
    }

    private static func decode(_ values: [JSONValue], from base: Project) throws -> [Track] {
        let baseTracks = Dictionary(base.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let baseItems = Dictionary(
            base.tracks.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try values.map { value in
            switch value {
            case .string(let id):
                guard let track = baseTracks[id] else { throw ProjectError.invalid("History delta: unknown layer \(id)") }
                return track
            case .object(let fields):
                guard case .object(let storage)? = fields["track"] else {
                    throw ProjectError.invalid("History delta: invalid layer")
                }
                guard let entries = fields["items"] else { return Track(storage: storage, hasItems: false, items: []) }
                let layer = storage["id"]?.string.flatMap { baseTracks[$0]?.items } ?? []
                let items = try decode(entries.array, layer: layer, others: baseItems)
                return Track(storage: storage, hasItems: true, items: items)
            default: throw ProjectError.invalid("History delta: invalid layer")
            }
        }
    }

    private static func decode(_ entries: [JSONValue], layer: [Item], others: [String: Item]) throws -> [Item] {
        var items: [Item] = []
        for entry in entries {
            switch entry {
            case .array(let run):
                guard run.count == 2, let start = run[0].int, let count = run[1].int, start >= 0, count > 0,
                    start <= layer.count - count
                else { throw ProjectError.invalid("History delta: invalid item run") }
                items += layer[start..<(start + count)]
            case .string(let id):
                guard let item = others[id] else { throw ProjectError.invalid("History delta: unknown item \(id)") }
                items.append(item)
            case .object(let fields): items.append(Item(fields: fields))
            default: throw ProjectError.invalid("History delta: invalid item")
            }
        }
        return items
    }
}
