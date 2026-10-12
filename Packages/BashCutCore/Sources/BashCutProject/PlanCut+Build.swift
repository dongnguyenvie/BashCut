import Foundation

/// The operations that build the list, worked out on a scratch copy (`LayerPlanner`) so the check and the apply see
/// the same edit.
extension PlanCut {
    /// Where each entry landed, in timeline frames.
    public struct Placement: Sendable {
        public var id: String
        public var at: Int
        public var end: Int
    }

    /// The operations that replace what an earlier apply built with `clips`, `spec.titles` and `spec.music`;
    /// `planner.project` is the edit as it would be, `kept` the items the apply leaves alone.
    /// `textPresets`: the library text presets (templates) titles name by ID, beyond the renderer's own presets;
    /// `transcripts`: the stored transcripts captions are made from, by media ID.
    public static func build(
        _ spec: Spec, clips: [Resolved], on project: Project, textPresets: [String: LibraryTextPreset] = [:],
        transcripts: [String: SourceTranscript] = [:]
    ) throws -> (planner: LayerPlanner, placements: [Placement], kept: [String]) {
        var planner = LayerPlanner(project)
        try removeBuilt(clips: clips, from: project, in: &planner)
        let main = try planner.project.requireTrack(role: TrackRole.main)
        guard main.items.isEmpty else {
            throw ProjectError.invalid(
                "Main holds \(main.items.count) item(s) plan apply did not build "
                    + "(\(main.items.prefix(5).map(\.id).joined(separator: ", "))): delete them first, or edit them with timeline apply")
        }
        var placements = try placeClips(clips, main: main.id, in: &planner)
        let total = placements.last?.end ?? 0
        if let captions = spec.captions {
            try placeCaptions(captions, clips: clips, transcripts: transcripts, textPresets: textPresets, in: &planner)
        }
        var sections: [String: Placement] = [:]
        for resolved in clips {
            guard let section = resolved.clip.section, let placed = placements.first(where: { $0.id == resolved.clip.id })
            else { continue }
            let span = sections[section]
            sections[section] = Placement(
                id: section, at: min(span?.at ?? placed.at, placed.at), end: max(span?.end ?? placed.end, placed.end))
        }
        placements += try placeTitles(
            spec.titles, anchors: placements, sections: sections, textPresets: textPresets, in: &planner)
        placements += try placeSounds(spec.sfx, anchors: placements, sections: sections, length: total, in: &planner)
        if let music = spec.music, total > 0, let placed = try placeMusic(music, length: total, in: &planner) {
            placements.append(placed)
            if let duck = music.duckDb {
                let track = try planner.project.requireTrack(role: TrackRole.music)
                try planner.add([.setTrackProperties(
                    track: track.id, patch: ["duckingEnabled": .bool(true), "duckUnderSpeechDb": .number(duck)])])
            }
        }
        let others = planner.project.tracks.flatMap(\.items).filter { $0.fields[tag] == nil }.map(\.id)
        return (planner, placements, others)
    }

    /// Deletes the section markers an earlier apply set (markers must stay inside the edit, so they go first), then
    /// the items it built (a linked partner goes with its item).
    static func removeBuilt(clips: [Resolved], from project: Project, in planner: inout LayerPlanner) throws {
        let built = project.tracks.flatMap(\.items).filter { $0.fields[tag] != nil }
        let sectionIDs = Set(clips.compactMap(\.clip.section))
            .union(plannedSections(project).map(\.id))
            .union(built.compactMap { $0.fields[sectionTag]?.string })
        for marker in planner.project.sectionMarkers where sectionIDs.contains(marker.id) {
            try planner.add([.deleteSection(id: marker.id)])
        }
        for id in built.map(\.id) where planner.project.tracks.contains(where: { $0.items.contains { $0.id == id } }) {
            try planner.add([.delete(item: id, ripple: false)])
        }
    }

    /// Lays the clips on Main one after another, then their section markers.
    static func placeClips(_ clips: [Resolved], main: String, in planner: inout LayerPlanner) throws -> [Placement] {
        let fps = planner.project.fps.value
        let labels = Dictionary(plannedSections(planner.project).map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        var placements: [Placement] = []
        var markers: [EditOperation] = []
        var cursor = 0
        var section: String?
        for resolved in clips {
            let clip = resolved.clip
            guard let media = planner.project.media.first(where: { $0.id == clip.media }) else { continue }
            if let wanted = clip.section, wanted != section {
                markers.append(.upsertSection(id: wanted, label: labels[wanted] ?? wanted, atFrame: cursor))
                section = wanted
            }
            var patch: [String: JSONValue] = [tag: .string(clip.id)]
            if let section = clip.section { patch[sectionTag] = .string(section) }
            if let role = clip.role { patch["tag"] = .object(["role": .string(role)]) }
            // The in edge rounds down and the out edge up to whole frames, so a clip given at word edges keeps the
            // whole of its first and last word (rounding the length could end it a frame inside the last one).
            let sourceIn = media.isImage ? 0 : Int((resolved.from * media.fps.value).rounded(.down))
            let start = media.isImage ? resolved.from : Double(sourceIn) / media.fps.value
            let slot = Slot(
                at: cursor, span: max(1, Int(((resolved.to - start) * fps - 1e-6).rounded(.up))),
                sourceIn: sourceIn, patch: patch)
            let end = clip.cover.isEmpty
                ? try placeOwn(clip, media: media, slot: slot, main: main, in: &planner)
                : try placeCovered(clip, media: media, slot: slot, main: main, in: &planner)
            placements.append(Placement(id: clip.id, at: cursor, end: end))
            cursor = end
        }
        try planner.add(markers)
        return placements
    }

    /// Where a clip goes: its first frame, length, source in-point and the tag fields its items carry.
    struct Slot {
        var at: Int
        var span: Int
        var sourceIn: Int
        var patch: [String: JSONValue]
    }

    /// A clip with its own picture and linked sound; returns where it ends (speed changes its length).
    static func placeOwn(_ clip: Clip, media: Media, slot: Slot, main: String, in planner: inout LayerPlanner) throws -> Int {
        let id = "plan-" + clip.id
        try planner.placeMedia(media, on: main, at: slot.at, duration: slot.span, itemID: id, sourceIn: slot.sourceIn)
        if clip.speed != 1 { try planner.add([.setSpeed(item: id, speed: clip.speed, keepDuration: false)]) }
        var patch = slot.patch
        if let volume = clip.volumeDb { patch["volumeDb"] = .number(volume) }
        var picture = patch
        if !clip.transform.isEmpty { picture["transform"] = .object(clip.transform) }
        try planner.add([.setProperties(item: id, patch: picture)])
        let placed = planner.project.tracks.flatMap(\.items).first { $0.id == id }
        if let partner = placed?.linkedItemID { try planner.add([.setProperties(item: partner, patch: patch)]) }
        return placed?.end ?? slot.at + slot.span
    }

    /// A covered clip: its sound on the dialogue layer, its covers on Main one after another (muted), the last one
    /// filling what is left. Returns where it ends.
    static func placeCovered(_ clip: Clip, media: Media, slot: Slot, main: String, in planner: inout LayerPlanner) throws -> Int {
        let fps = planner.project.fps.value
        let end = slot.at + slot.span
        var sound = Item(id: "plan-\(clip.id)-sound", media: media.id, at: slot.at, duration: slot.span, sourceIn: slot.sourceIn)
        for (key, value) in slot.patch { sound[key] = value }
        if let volume = clip.volumeDb { sound["volumeDb"] = .number(volume) }
        try planner.place(sound, on: planner.project.requireTrack(role: TrackRole.dialogue, kind: "audio").id)
        var cursor = slot.at
        for (index, shot) in clip.cover.enumerated() where cursor < end {
            guard let picture = planner.project.media.first(where: { $0.id == shot.media }) else { continue }
            let wanted = index == clip.cover.count - 1 ? end - cursor : Int(((shot.seconds ?? 3) * fps).rounded())
            let length = max(1, min(wanted, end - cursor))
            var item = Item(
                id: "plan-\(clip.id)-cover\(index + 1)", media: picture.id, at: cursor, duration: length,
                sourceIn: picture.isImage ? 0 : Int((shot.from * picture.fps.value).rounded(.down)))
            for (key, value) in slot.patch { item[key] = value }
            item["tag"] = .object(["role": .string("broll")])
            if !shot.transform.isEmpty { item["transform"] = .object(shot.transform) }
            if picture.hasAudio == true { item["muted"] = .bool(true) }
            try planner.place(item, on: main)
            cursor += length
        }
        return end
    }

    /// Titles on the captions layer (spilling onto another text layer where one is already shown): the renderer
    /// preset or the library preset's look, then the title's own style over it.
    static func placeTitles(
        _ titles: [Title], anchors: [Placement], sections: [String: Placement] = [:],
        textPresets: [String: LibraryTextPreset], in planner: inout LayerPlanner
    ) throws -> [Placement] {
        guard !titles.isEmpty else { return [] }
        let fps = planner.project.fps.value
        let titlesTrack = try planner.titleTrack()
        var placements: [Placement] = []
        for title in titles {
            let anchor = title.clip.flatMap { id in anchors.first { $0.id == id } } ?? title.section.flatMap { sections[$0] }
            let start = anchor.map { $0.at + Int((title.offset * fps).rounded()) } ?? Int(((title.at ?? 0) * fps).rounded())
            // Without seconds a title lasts to the end of its clip or section.
            let length = title.seconds.map { Int(($0 * fps).rounded()) } ?? ((anchor?.end ?? start) - start)
            var item = Item(id: "plan-" + title.id, at: max(0, start), duration: max(1, length))
            item["text"] = .string(title.text)
            for (key, value) in try look(
                for: item, (title.preset, title.style, title.textStyle), textPresets: textPresets, project: planner.project)
            {
                item[key] = value
            }
            item[tag] = .string(title.id)
            try planner.place(item, on: titlesTrack)
            placements.append(Placement(id: title.id, at: item.at, end: item.end))
        }
        return placements
    }

    /// The properties that give text `item` a renderer preset or a library preset's look, then `style` (item
    /// properties) and `textStyle` over it.
    static func look(
        for item: Item, _ look: (preset: String?, style: [String: JSONValue], textStyle: [String: JSONValue]),
        textPresets: [String: LibraryTextPreset], project: Project
    ) throws -> [String: JSONValue] {
        let (preset, style, textStyle) = look
        var patch: [String: JSONValue] = [:]
        if let preset, let library = textPresets[preset], !TextPreset.all.contains(preset) {
            patch = try library.patch(for: item, project: project)
        } else if let preset {
            patch["textPreset"] = .string(preset)
        }
        for (key, value) in style where !["id", "at", "dur", "in", "media", "text", "textStyle", tag].contains(key) {
            patch[key] = value
        }
        if !textStyle.isEmpty {
            let base = patch["textStyle"]?.object ?? item["textStyle"]?.object ?? [:]
            patch["textStyle"] = .object(base.merging(textStyle) { $1 })
        }
        // Text tied to brand roles (a library preset's or the style's brandRoles) takes the project's kit (#453).
        if let roles = patch["brandRoles"]?.object, let brand = project.brand {
            let base = patch["textStyle"]?.object ?? item["textStyle"]?.object ?? [:]
            patch["textStyle"] = .object(brand.restyled(base, roles: roles))
        }
        return patch
    }

    /// Captions from the stored transcript of each media whose sound the clips play, through the built clips (as
    /// `captions generate` would make them), in the captions' preset and style, tagged `captions`.
    static func placeCaptions(
        _ captions: Captions, clips: [Resolved], transcripts: [String: SourceTranscript],
        textPresets: [String: LibraryTextPreset], in planner: inout LayerPlanner
    ) throws {
        var heard: [String] = []
        for resolved in clips where !heard.contains(resolved.clip.media) { heard.append(resolved.clip.media) }
        for media in heard {
            guard let transcript = transcripts[media] else { continue }
            let before = Set(planner.project.tracks.flatMap(\.items).map(\.id))
            // Only cues inside what the plan built: other clips of the same media keep their captions.
            let operation = try planner.project.importingCues(
                transcript.phrases, replace: false, provenance: transcript.provider, media: media,
                words: transcript.words, wordStyle: captions.wordStyle)
            try planner.add([operation])
            let added = planner.project.tracks.flatMap(\.items).filter { !before.contains($0.id) }
            for item in added {
                var patch = try look(
                    for: item, (captions.preset, captions.style, captions.textStyle), textPresets: textPresets,
                    project: planner.project)
                patch[tag] = .string("captions")
                let text = captions.replace.reduce(item.text) { text, pair in
                    text.replacingOccurrences(of: pair.from, with: pair.to, options: .caseInsensitive)
                }
                if text != item.text { patch["text"] = .string(text) }
                try planner.add([.setProperties(item: item.id, patch: patch)])
            }
        }
    }

    /// Sound effects on the SFX layer (spilling onto another where one already plays), each at its anchor plus
    /// offset, for its seconds or the whole file, never past the edit's end.
    static func placeSounds(
        _ sounds: [Sound], anchors: [Placement], sections: [String: Placement], length total: Int,
        in planner: inout LayerPlanner
    ) throws -> [Placement] {
        guard !sounds.isEmpty, total > 0 else { return [] }
        let fps = planner.project.fps.value
        let track = try planner.project.requireTrack(role: TrackRole.sfx)
        var placements: [Placement] = []
        for sound in sounds {
            guard let media = planner.project.media.first(where: { $0.id == sound.media }) else { continue }
            let anchor = sound.on.flatMap { id in anchors.first { $0.id == id }?.at }
                ?? sound.section.flatMap { sections[$0]?.at } ?? Int(((sound.at ?? 0) * fps).rounded())
            let start = max(0, anchor + Int((sound.offset * fps).rounded()))
            guard start < total else { continue }
            let wanted = Int(((sound.seconds ?? media.durationSeconds) * fps).rounded())
            let duration = max(1, min(wanted, Int((media.durationSeconds * fps).rounded(.down)), total - start))
            let id = "plan-" + sound.id
            try planner.placeMedia(media, on: track.id, at: start, duration: duration, itemID: id, sourceIn: 0)
            var patch: [String: JSONValue] = [tag: .string(sound.id)]
            if let volume = sound.volumeDb { patch["volumeDb"] = .number(volume) }
            try planner.add([.setProperties(item: id, patch: patch)])
            placements.append(Placement(id: sound.id, at: start, end: start + duration))
        }
        return placements
    }

    /// The music bed from frame 0, as long as the clips (or what the file has left).
    static func placeMusic(_ music: Music, length total: Int, in planner: inout LayerPlanner) throws -> Placement? {
        guard let media = planner.project.media.first(where: { $0.id == music.media }) else { return nil }
        let track = try planner.project.requireTrack(role: TrackRole.music)
        let available = Int(((media.durationSeconds - music.from) * planner.project.fps.value).rounded(.down))
        let duration = min(total, max(1, available))
        let id = "plan-music"
        try planner.placeMedia(
            media, on: track.id, at: 0, duration: duration, itemID: id, sourceIn: Int((music.from * media.fps.value).rounded(.down)))
        var patch: [String: JSONValue] = [tag: .string("music")]
        if let volume = music.volumeDb { patch["volumeDb"] = .number(volume) }
        try planner.add([.setProperties(item: id, patch: patch)])
        return Placement(id: "music", at: 0, end: duration)
    }
}
