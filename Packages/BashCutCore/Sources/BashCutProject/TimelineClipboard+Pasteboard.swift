import Foundation

/// The clipboard on the OS pasteboard (#357 follow-up): copied clips as JSON under a private type, with the media
/// they play (and each file's absolute path), so they paste into another project or another BashCut instance.
extension TimelineClipboard {
    /// The private pasteboard type.
    public static let pasteboardType = "com.bashcut.timeline-items"
    public static let pasteboardVersion = 1

    /// The clipboard as pasteboard JSON: `{version, fps, entries [{item, track, trackKind, offset}], media [{…fields,
    /// absolutePath}]}`. `projectRoot` (nil for an unsaved project) resolves the media files.
    public func pasteboardJSON(from project: Project, projectRoot: URL?, workspaceRoot: URL? = nil) -> JSONValue {
        let used = Set(entries.compactMap(\.item.mediaID))
        let media = project.media.filter { used.contains($0.id) }.map { asset -> JSONValue in
            var fields = asset.fields
            if let projectRoot, !asset.path.hasPrefix("@"),
                let url = try? MediaPathResolver.resolve(asset.path, projectRoot: projectRoot, workspaceRoot: workspaceRoot)
            {
                fields["absolutePath"] = .string(url.path)
            }
            return .object(fields)
        }
        return .object([
            "version": .integer(Self.pasteboardVersion), "fps": project.fps.json,
            "entries": .array(entries.map { entry in
                .object([
                    "item": .object(entry.item.fields), "track": .string(entry.trackID),
                    "trackKind": .string(entry.trackKind), "offset": .integer(entry.offset),
                ])
            }),
            "media": .array(media),
        ])
    }

    /// Clips read from pasteboard JSON, ready to paste into `project` (at `projectRoot`): media already in the project
    /// (same ID and file, or the same file under another ID) are reused, the others are added with a project-relative
    /// path (and a new ID when theirs is taken). Timing written at another frame rate is converted to the project's.
    /// Returns the clipboard and the operations that add the media; paste the clipboard after them.
    public static func fromPasteboard(
        _ json: JSONValue, into project: Project, projectRoot: URL?, workspaceRoot: URL? = nil
    ) throws -> (clipboard: TimelineClipboard, addMedia: [EditOperation]) {
        let fields = json.object
        guard fields["version"]?.int == pasteboardVersion, case .array(let rows)? = fields["entries"], !rows.isEmpty else {
            throw ProjectError.invalid("The pasteboard has no BashCut clips this version can read")
        }
        let sourceFPS = FrameRate(json: fields["fps"])
        let ratio = sourceFPS.value > 0 && sourceFPS != project.fps ? project.fps.value / sourceFPS.value : 1
        func resolved(_ media: Media) -> String? {
            guard let projectRoot, !media.path.hasPrefix("@") else { return nil }
            return (try? MediaPathResolver.resolve(media.path, projectRoot: projectRoot, workspaceRoot: workspaceRoot))?.path
        }
        var mapping: [String: String] = [:]
        var operations: [EditOperation] = []
        var taken = Set(project.media.map(\.id))
        for row in fields["media"]?.array ?? [] {
            var copied = Media(fields: row.object)
            let absolute = row.object["absolutePath"]?.string
            copied.fields["absolutePath"] = nil
            let existing = project.media.first { media in
                if media.path.hasPrefix("@") || copied.path.hasPrefix("@") { return media.path == copied.path }
                guard let absolute, let path = resolved(media) else {
                    return media.id == copied.id && media.path == copied.path
                }
                return path == URL(fileURLWithPath: absolute).standardizedFileURL.path
            }
            if let existing {
                mapping[copied.id] = existing.id
                continue
            }
            if let absolute, !copied.path.hasPrefix("@") {
                guard let projectRoot else { throw ProjectError.invalid("Save the project before pasting clips from another") }
                copied.fields["path"] = .string(
                    MediaPathResolver.projectPath(for: URL(fileURLWithPath: absolute), projectRoot: projectRoot))
            }
            let id = taken.contains(copied.id) ? UUID().uuidString : copied.id
            taken.insert(id)
            mapping[copied.id] = id
            copied.fields["id"] = .string(id)
            operations.append(.addMedia(copied))
        }
        let entries = rows.map { row -> Entry in
            let fields = row.object
            var item = Item(fields: fields["item"]?.object ?? [:])
            if let media = item.mediaID { item.fields["media"] = .string(mapping[media] ?? media) }
            if ratio != 1 { item = Self.converting(item, by: ratio) }
            let offset = Int((Double(fields["offset"]?.int ?? 0) * ratio).rounded())
            return Entry(
                item: item, trackID: fields["track"]?.string ?? "", trackKind: fields["trackKind"]?.string ?? "",
                offset: offset)
        }
        return (TimelineClipboard(entries: entries), operations)
    }

    /// `item` with its timeline timing (length, fades, keyframes, word timings) scaled by `ratio` (project frames per
    /// source-project frame). Source in-points are in media frames and stay.
    static func converting(_ item: Item, by ratio: Double) -> Item {
        var item = item
        let scale = { (frames: Int) in Int((Double(frames) * ratio).rounded()) }
        item.duration = max(1, scale(item.duration))
        for key in ["fadeIn", "fadeOut"] {
            if let frames = item.fields[key]?.int { item.fields[key] = .integer(scale(frames)) }
        }
        if let motion = item.motion {
            item.fields["keyframes"] = ItemMotion(keys: motion.keys.mapValues { keys in
                var last = Int.min
                return keys.compactMap { key -> ItemMotion.Key? in
                    let frame = scale(key.frame)
                    guard frame > last else { return nil }
                    last = frame
                    return ItemMotion.Key(frame: frame, value: key.value, ease: key.ease)
                }
            }).json
        }
        if case .array(let words) = item.fields["words"] {
            item.fields["words"] = .array(words.map { word in
                var entry = word.object
                for key in ["at", "end"] { if let frames = entry[key]?.int { entry[key] = .integer(scale(frames)) } }
                return .object(entry)
            })
        }
        return item
    }
}
