import Foundation
import BashCutProject

public struct LegacyEDLImportReport: Sendable, Equatable {
    public let project: Project
    public let sourceCutCount: Int
    public let sourceVoiceoverCount: Int
    public let sourceTotalFrames: Int?
    public let warnings: [String]

    public var importedCutCount: Int {
        project.tracks.first(where: { $0.role == "main" })?.items.count ?? 0
    }

    public var importedDuration: Int { project.duration }

    public var importedVoiceoverCount: Int {
        project.tracks.first(where: { $0.role == "voiceover" })?.items.count ?? 0
    }
}

public enum LegacyEDLImporter {
    public static func decode(
        _ data: Data, name: String, destinationDirectory: URL
    ) throws -> LegacyEDLImportReport {
        let root = try JSONDecoder().decode(JSONValue.self, from: data).object
        let clips = (root["v1"] ?? root["clips"])?.array ?? []
        guard !clips.isEmpty else { throw ProjectError.invalid("edl.json: clips or v1 is required") }
        let fps = frameRate(root["fps"])
        var project = Project(name: name, fps: fps)
        var mediaByPath: [String: Media] = [:]
        var mainItems: [Item] = []
        var dialogueItems: [Item] = []
        var captionItems: [Item] = []
        var markers: [TimelineMarker] = []
        var cursor = 0
        let videoContext = MediaImportContext(
            fps: fps, destination: destinationDirectory, kind: "video", hasAudio: false)

        for (index, value) in clips.enumerated() {
            let clip = value.object
            guard let soundPath = string(clip, keys: ["path", "file", "src"]),
                let duration = integer(clip, keys: ["so_frame", "dur", "duration"]), duration > 0
            else { throw ProjectError.invalid("edl.json: clip \(index + 1) is missing path or duration") }
            let picturePath = string(clip, keys: ["vpath"]) ?? soundPath
            let sourceIn = max(0, integer(clip, keys: ["src_in_frame", "in"]) ?? 0)
            let at = max(0, integer(clip, keys: ["rec_frame", "at"]) ?? cursor)
            let picture = media(
                path: picturePath, minimumFrames: sourceIn + duration,
                context: videoContext.withAudio(picturePath == soundPath), existing: &mediaByPath)
            let videoID = "legacy-v1-\(index + 1)"
            let audioID = "legacy-a1-\(index + 1)"
            var item = Item(id: videoID, media: picture.id, at: at, duration: duration,
                            sourceIn: sourceIn)
            copyTransform(from: clip, to: &item)
            copyTags(from: clip, to: &item)

            if picturePath != soundPath {
                let sound = media(
                    path: soundPath, minimumFrames: sourceIn + duration,
                    context: videoContext.withAudio(true), existing: &mediaByPath)
                dialogueItems.append(
                    Item(id: audioID, media: sound.id, at: at,
                         duration: duration, sourceIn: sourceIn))
            } else {
                item.fields["linkedAudio"] = .string(audioID)
                var audio = Item(id: audioID, media: picture.id, at: at, duration: duration,
                                 sourceIn: sourceIn)
                audio.fields["linkedVideo"] = .string(videoID)
                dialogueItems.append(audio)
            }
            mainItems.append(item)
            if let subtitle = string(clip, keys: ["sub", "subtitle"]) {
                captionItems += captions(
                    subtitle, at: at, duration: duration, fps: fps,
                    idPrefix: "legacy-clip-\(index + 1)-caption")
            }
            if let section = string(clip, keys: ["sec", "section"]),
                markers.last?.label != section
            {
                markers.append(TimelineMarker(id: "legacy-section-\(markers.count + 1)", at: at,
                                              kind: "section", label: section))
            }
            cursor = max(cursor, at + duration)
        }

        let voice = voiceovers(
            from: root["vo"]?.array ?? [],
            context: MediaImportContext(
                fps: fps, destination: destinationDirectory, kind: "audio", hasAudio: true),
            media: &mediaByPath)
        captionItems += voice.captions
        var tracks = project.tracks
        setItems(mainItems, role: "main", tracks: &tracks)
        setItems(dialogueItems, role: "dialogue", tracks: &tracks)
        setItems(voice.items, role: "voiceover", tracks: &tracks)
        setItems(captionItems, role: "captions", tracks: &tracks)
        project.tracks = tracks
        project.media = mediaByPath.values.sorted { $0.id < $1.id }
        project.markers = markers
        var warnings = voice.warnings
        for key in ["fx", "transitions", "over", "sfx"] where root[key] != nil {
            warnings.append("\(key) requires manual review")
        }
        project = project.normalizingLayers()
        try project.validate()
        return LegacyEDLImportReport(
            project: project, sourceCutCount: clips.count, sourceVoiceoverCount: root["vo"]?.array.count ?? 0,
            sourceTotalFrames: integer(root, keys: ["total_frames"]), warnings: warnings)
    }
}

private extension LegacyEDLImporter {
    static func frameRate(_ value: JSONValue?) -> FrameRate {
        if case .array = value { return FrameRate(json: value) }
        let number = value?.double ?? 29.97
        if abs(number - 29.97) < 0.02 { return FrameRate() }
        if abs(number - 23.976) < 0.02 { return FrameRate(24_000, 1_001) }
        if abs(number - 59.94) < 0.02 { return FrameRate(60_000, 1_001) }
        return FrameRate(max(1, Int(number.rounded())), 1)
    }

    static func string(_ object: [String: JSONValue], keys: [String]) -> String? {
        keys.lazy.compactMap { object[$0]?.string }.first
    }

    static func integer(_ object: [String: JSONValue], keys: [String]) -> Int? {
        keys.lazy.compactMap { key in
            object[key]?.int ?? object[key]?.double.map { Int($0.rounded()) }
        }.first
    }

    static func media(
        path: String, minimumFrames: Int, context: MediaImportContext,
        existing: inout [String: Media]
    ) -> Media {
        let normalized = normalizedPath(path, relativeTo: context.destination)
        let key = normalized
        if var found = existing[key] {
            found.fields["frames"] = .integer(max(found.frames, minimumFrames))
            if context.hasAudio { found.fields["hasAudio"] = .bool(true) }
            existing[key] = found
            return found
        }
        let fields: [String: JSONValue] = [
            "id": .string("legacy-media-\(existing.count + 1)"), "path": .string(normalized),
            "kind": .string(context.kind), "fps": context.fps.json,
            "frames": .integer(minimumFrames), "hasAudio": .bool(context.hasAudio),
        ]
        let result = Media(fields: fields)
        existing[key] = result
        return result
    }

    static func normalizedPath(_ path: String, relativeTo directory: URL) -> String {
        guard path.hasPrefix("/") else { return path }
        let source = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let base = directory.standardizedFileURL.pathComponents
        let common = zip(source, base).prefix { $0 == $1 }.count
        return (Array(repeating: "..", count: base.count - common) + source.dropFirst(common))
            .joined(separator: "/")
    }

    static func setItems(_ items: [Item], role: String, tracks: inout [Track]) {
        guard let index = tracks.firstIndex(where: { $0.role == role }) else { return }
        tracks[index].items = items
    }

    static func copyTransform(from clip: [String: JSONValue], to item: inout Item) {
        var transform: [String: JSONValue] = [:]
        for key in ["zoom", "pan", "tilt"] where clip[key] != nil { transform[key] = clip[key] }
        if !transform.isEmpty { item.fields["transform"] = .object(transform) }
    }

    static func copyTags(from clip: [String: JSONValue], to item: inout Item) {
        var tag = clip["tag"]?.object ?? [:]
        if let role = clip["role"] { tag["role"] = role }
        if let section = clip["section"] ?? clip["sec"] { tag["section"] = section }
        if !tag.isEmpty { item.fields["tag"] = .object(tag) }
    }

    static func voiceovers(
        from values: [JSONValue], context: MediaImportContext,
        media existingMedia: inout [String: Media]
    ) -> (items: [Item], captions: [Item], warnings: [String]) {
        var items: [Item] = []
        var textItems: [Item] = []
        var warnings: [String] = []
        for (index, value) in values.enumerated() {
            let voice = value.object
            guard let path = string(voice, keys: ["path", "file", "src"]),
                let duration = frameDuration(voice, fps: context.fps), duration > 0
            else {
                warnings.append("vo[\(index)] is missing path or duration")
                continue
            }
            let at = framePosition(voice, fps: context.fps)
            let sourceIn = max(0, integer(voice, keys: ["src_in_frame", "in"]) ?? 0)
            let asset = media(
                path: path, minimumFrames: sourceIn + duration, context: context,
                existing: &existingMedia)
            items.append(
                Item(id: "legacy-voice-\(index + 1)", media: asset.id, at: at,
                     duration: duration, sourceIn: sourceIn))
            if let text = string(voice, keys: ["text", "sub", "caption"]) {
                textItems += captions(
                    text, at: at, duration: duration, fps: context.fps,
                    idPrefix: "legacy-voice-\(index + 1)-caption")
            }
        }
        return (items, textItems, warnings)
    }

    static func framePosition(_ value: [String: JSONValue], fps: FrameRate) -> Int {
        if let frame = integer(value, keys: ["rec_frame", "at", "at_frame"]) {
            return max(0, frame)
        }
        return max(0, Int(((value["t"]?.double ?? value["time"]?.double ?? 0) * fps.value).rounded()))
    }

    static func frameDuration(_ value: [String: JSONValue], fps: FrameRate) -> Int? {
        if let frames = integer(value, keys: ["duration_frames", "frames", "dur"]) {
            return frames
        }
        return value["duration"]?.double.map { Int(($0 * fps.value).rounded()) }
    }

    static func captions(
        _ text: String, at: Int, duration: Int, fps: FrameRate, idPrefix: String
    ) -> [Item] {
        let expression = try? NSRegularExpression(pattern: #"\|([0-9]+(?:\.[0-9]+)?)\|"#)
        let source = text as NSString
        let matches = expression?.matches(in: text, range: NSRange(location: 0, length: source.length)) ?? []
        var boundaries = [0]
        var labels: [String] = []
        var start = 0
        for match in matches {
            labels.append(source.substring(with: NSRange(location: start, length: match.range.location - start)))
            let seconds = Double(source.substring(with: match.range(at: 1))) ?? 0
            boundaries.append(min(duration, max(0, Int((seconds * fps.value).rounded()))))
            start = match.range.location + match.range.length
        }
        labels.append(source.substring(from: start))
        boundaries.append(duration)
        return labels.enumerated().compactMap { index, label in
            let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let begin = boundaries[index]
            let end = boundaries[index + 1]
            guard !clean.isEmpty, end > begin else { return nil }
            var item = Item(id: "\(idPrefix)-\(index + 1)", at: at + begin, duration: end - begin)
            item.fields["text"] = .string(clean)
            return item
        }
    }
}

private struct MediaImportContext {
    let fps: FrameRate
    let destination: URL
    let kind: String
    let hasAudio: Bool

    func withAudio(_ value: Bool) -> Self {
        Self(fps: fps, destination: destination, kind: kind, hasAudio: value)
    }
}
