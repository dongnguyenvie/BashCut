import Foundation

/// The operations that build the list, worked out on a scratch copy (`LayerPlanner`) so the check and the apply see
/// the same edit.
extension PlanCut {
    /// Where each entry landed, in timeline frames.
    public struct Placement: Sendable {
        public var id: String
        public var at: Int
        public var end: Int
        /// Frames a graphic's span asked for, when its movie is shorter.
        public var asked: Int?
    }

    /// The operations that replace what an earlier apply built with `clips`, `spec.titles` and `spec.music`;
    /// `planner.project` is the edit as it would be, `kept` the items the apply leaves alone. Cut transitions and
    /// In/Out set by hand on built items come back on the rebuilt ones unless the list sets them (#623), and so do
    /// their sound, speed and the music bed's span (`HandEdits`).
    /// `textPresets`: the library text presets (templates) titles name by ID, beyond the renderer's own presets;
    /// `transcripts`: the stored transcripts captions are made from, by media ID.
    public static func build(
        _ spec: Spec, clips: [Resolved], on project: Project, textPresets: [String: LibraryTextPreset] = [:],
        transcripts: [String: SourceTranscript] = [:], takes: [String: LineTake] = [:]
    ) throws -> (planner: LayerPlanner, placements: [Placement], kept: [String], hand: HandReport) {
        var planner = LayerPlanner(project)
        let handSet = HandSet(project)
        var keep = Keep(project, spec: spec)
        try removeBuilt(clips: clips, lines: spec.voiceover, from: project, in: &planner)
        let main = try planner.project.requireTrack(role: TrackRole.main)
        guard main.items.isEmpty else {
            throw ProjectError.invalid(
                "Main holds \(main.items.count) item(s) plan apply did not build "
                    + "(\(main.items.prefix(5).map(\.id).joined(separator: ", "))): delete them first, or edit them with timeline apply")
        }
        var placements = try placeClips(clips, main: main.id, kept: handSet.hand, keep: &keep, in: &planner)
        var lines = try placeLines(spec.voiceover, takes: takes, in: &planner)
        // Lines moved by hand (a ripple cut before them) stay where they are; anchors and sections follow them.
        let moved = try keepTiming(spec.voiceover.map(\.id), followsClips: false, keep: &keep, in: &planner)
        lines = lines.map { line in moved[line.id].map { Placement(id: line.id, at: $0.at, end: $0.end) } ?? line }
        placements += lines
        // What was set by hand comes back before the captions, which leave out what is muted.
        try keepFields(Set(clips.map(\.clip.id) + spec.voiceover.map(\.id)), keep: &keep, in: &planner)
        let total = max(placements.map(\.end).max() ?? 0, lineEnd(spec.voiceover, placements: lines, fps: planner.project.fps.value))
        let sources = CaptionSources(transcripts: transcripts, takes: takes, textPresets: textPresets)
        keep.report.keepDeleted(try rebuildCaptions(spec, clips: clips, sources: sources, was: project, in: &planner))
        try markCaptioned(spec, transcripts: transcripts, in: &planner)
        var sections: [String: Placement] = [:]
        let sectioned = clips.map { ($0.clip.id, $0.clip.section) } + spec.voiceover.map { ($0.id, $0.section) }
        for (id, section) in sectioned {
            guard let section, let placed = placements.first(where: { $0.id == id }) else { continue }
            let span = sections[section]
            sections[section] = Placement(
                id: section, at: min(span?.at ?? placed.at, placed.at), end: max(span?.end ?? placed.end, placed.end))
        }
        try markLineSections(spec.voiceover, clips: clips, sections: sections, in: &planner)
        placements += try placeTitles(
            spec.titles, anchors: placements, sections: sections, textPresets: textPresets, in: &planner)
        placements += try placeGraphics(spec.graphics, anchors: placements, sections: sections, main: main.id, in: &planner)
        placements += try placeSounds(spec.sfx, anchors: placements, sections: sections, length: total, in: &planner)
        if let music = spec.music, total > 0,
            let placed = try placeMusic(music, length: total, kept: handSet.hand, in: &planner)
        {
            placements.append(placed)
            let track = try planner.project.requireTrack(role: TrackRole.music)
            try planner.add([.setTrackProperties(track: track.id, patch: musicTrackPatch(music, track: track, fps: planner.project.fps.value))])
        }
        let anchored = spec.titles.map(\.id) + spec.graphics.map(\.id) + spec.sfx.map(\.id)
        try keepTiming(anchored, followsClips: false, keep: &keep, in: &planner)
        try keepFields(keep: &keep, in: &planner)
        try applyEdges(spec, kept: handSet, in: &planner)
        let others = planner.project.tracks.flatMap(\.items).filter { $0.fields[tag] == nil }.map(\.id)
        return (planner, placements, others, keep.report)
    }

    /// Deletes the transitions on the cuts an earlier apply built, the section markers it set (markers must stay
    /// inside the edit, so they go first), then the items it built (a linked partner goes with its item). Captions
    /// stay: `rebuildCaptions` keeps or replaces them once the clips are built.
    static func removeBuilt(clips: [Resolved], lines: [Line] = [], from project: Project, in planner: inout LayerPlanner) throws {
        let built = project.tracks.flatMap(\.items).filter { $0.fields[tag] != nil && $0.fields[tag] != .string("captions") }
        let sectionIDs = Set(clips.compactMap(\.clip.section)).union(lines.compactMap(\.section))
            .union(plannedSections(project).map(\.id))
            .union(built.compactMap { $0.fields[sectionTag]?.string })
        // Transitions on built cuts go first and by name: the edit is applied as one group, where a cut rebuilt
        // with the same item IDs would keep one; what stays comes back from the hand-set ones and the list.
        let ids = Set(built.map(\.id))
        for transition in planner.project.transitions where ids.contains(transition.fromItemID) || ids.contains(transition.toItemID) {
            try planner.add([.deleteTransition(id: transition.id)])
        }
        for marker in planner.project.sectionMarkers where sectionIDs.contains(marker.id) {
            try planner.add([.deleteSection(id: marker.id)])
        }
        for id in built.map(\.id) where planner.project.tracks.contains(where: { $0.items.contains { $0.id == id } }) {
            try planner.add([.delete(item: id, ripple: false)])
        }
    }

    /// Lays the clips on Main one after another, then their section markers.
    static func placeClips(
        _ clips: [Resolved], main: String, kept: HandEdits, keep: inout Keep, in planner: inout LayerPlanner
    ) throws -> [Placement] {
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
                sourceIn: sourceIn, patch: patch, main: main)
            var end = clip.cover.isEmpty
                ? try placeOwn(clip, media: media, slot: slot, kept: kept, in: &planner)
                : try placeCovered(clip, media: media, slot: slot, in: &planner)
            try placeOverlays(clip, media: media, slot: slot, end: end, in: &planner)
            // Its focus is the build's own framing, recorded with the rest before hand-cut pieces replace it.
            try applyFocus([resolved], in: &planner)
            // The pieces a ripple cut, split or trim left of the clip, while its row gives the same range.
            if let kept = try keepTiming([clip.id], followsClips: true, keep: &keep, in: &planner)[clip.id] { end = kept.end }
            placements.append(Placement(id: clip.id, at: cursor, end: end))
            cursor = end
        }
        try planner.add(markers)
        return placements
    }

    /// Where a clip goes: its first frame, length, source in-point, the tag fields its items carry and Main's ID.
    struct Slot {
        var at: Int
        var span: Int
        var sourceIn: Int
        var patch: [String: JSONValue]
        var main: String
    }

    /// A clip with its own picture and linked sound; returns where it ends (speed changes its length).
    static func placeOwn(_ clip: Clip, media: Media, slot: Slot, kept: HandEdits, in planner: inout LayerPlanner) throws -> Int {
        let id = "plan-" + clip.id
        try planner.placeMedia(media, on: slot.main, at: slot.at, duration: slot.span, itemID: id, sourceIn: slot.sourceIn)
        try placeSpeed(clip, id: id, kept: kept, in: &planner)
        var patch = slot.patch
        if let volume = clip.volumeDb { patch = recordingAudio(patch.merging(["volumeDb": .number(volume)]) { $1 }) }
        var picture = patch.merging(pictureFields(clip.picture)) { $1 }
        if !clip.transform.isEmpty { picture["transform"] = .object(clip.transform) }
        try planner.add([.setProperties(item: id, patch: picture)])
        let placed = planner.project.tracks.flatMap(\.items).first { $0.id == id }
        if let partner = placed?.linkedItemID { try planner.add([.setProperties(item: partner, patch: patch)]) }
        return placed?.end ?? slot.at + slot.span
    }

    /// A covered clip: its sound on the dialogue layer, its covers on Main one after another (muted), the last one
    /// filling what is left. Returns where it ends.
    static func placeCovered(_ clip: Clip, media: Media, slot: Slot, in planner: inout LayerPlanner) throws -> Int {
        let fps = planner.project.fps.value
        let end = slot.at + slot.span
        var sound = Item(id: "plan-\(clip.id)-sound", media: media.id, at: slot.at, duration: slot.span, sourceIn: slot.sourceIn)
        for (key, value) in slot.patch { sound[key] = value }
        if let volume = clip.volumeDb {
            sound["volumeDb"] = .number(volume)
            sound[audioTag] = .object(["volumeDb": .number(volume)])
        }
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
            for (key, value) in pictureFields(shot.picture) { item[key] = value }
            if picture.hasAudio == true { mute(&item) }
            try planner.place(item, on: slot.main)
            cursor += length
        }
        return end
    }

    /// Mutes a picture's own sound, recorded as the build's (`planAudio`) so a later apply keeps it unmuted by hand.
    static func mute(_ item: inout Item) {
        item["muted"] = .bool(true)
        item[audioTag] = .object(["muted": .bool(true)])
    }

    /// The picture fields a row sets, and `planPicture` naming them, so a later apply tells them from hand edits.
    static func pictureFields(_ picture: [String: JSONValue]) -> [String: JSONValue] {
        var fields = picture.filter { $0.value != .null }
        if !fields.isEmpty { fields[pictureTag] = .array(fields.keys.sorted().map(JSONValue.string)) }
        return fields
    }

    /// A clip's overlays on an overlay layer (muted), tagged with the clip so they are rebuilt, and move, with it.
    /// The clip's own media plays in sync with the clip unless the overlay gives `from`.
    static func placeOverlays(_ clip: Clip, media clipMedia: Media, slot: Slot, end: Int, in planner: inout LayerPlanner) throws {
        guard !clip.overlays.isEmpty else { return }
        let fps = planner.project.fps.value
        let track = try overlayTrack(in: &planner)
        for (index, overlay) in clip.overlays.enumerated() {
            guard let media = planner.project.media.first(where: { $0.id == overlay.media }) else { continue }
            let at = slot.at + Int((overlay.offset * fps).rounded())
            let from = overlay.from
                ?? (clipMedia.isImage ? 0 : Double(slot.sourceIn) / clipMedia.fps.value) + (media.isImage ? 0 : overlay.offset)
            let available = media.isImage ? end - at : Int(((media.durationSeconds - from) * fps).rounded(.down))
            let length = min(overlay.seconds.map { Int(($0 * fps).rounded()) } ?? end - at, end - at, available)
            guard length > 0 else { continue }
            var item = Item(
                id: "plan-\(clip.id)-overlay\(index + 1)", media: media.id, at: at, duration: length,
                sourceIn: media.isImage ? 0 : Int((from * media.fps.value).rounded(.down)))
            for (key, value) in slot.patch where key != "tag" { item[key] = value }
            if !overlay.transform.isEmpty { item["transform"] = .object(overlay.transform) }
            for (key, value) in pictureFields(overlay.picture) { item[key] = value }
            if media.hasAudio == true { mute(&item) }
            try planner.place(item, on: track)
        }
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
            try planner.add([.setProperties(item: id, patch: recordingAudio(patch))])
            placements.append(Placement(id: sound.id, at: start, end: start + duration))
        }
        return placements
    }

    /// The Music layer's ducking for the bed: off for a fixed bed; asked for, at `duckDb` (else the layer's level,
    /// else −14 dB) with the hold of `duckMinGapSeconds` (2.5 s) between lines (#630).
    static func musicTrackPatch(_ music: Music, track: Track, fps: Double) -> [String: JSONValue] {
        guard music.ducks else { return ["duckingEnabled": .bool(false)] }
        let gap = music.duckMinGapSeconds ?? MusicDucking.defaultMinGapSeconds
        return [
            "duckingEnabled": .bool(true),
            "duckUnderSpeechDb": .number(music.duckDb ?? track["duckUnderSpeechDb"]?.double ?? Music.defaultDuckDb),
            "duckMinGapFrames": .integer(Int((gap * fps).rounded())),
        ]
    }

    /// The music bed from frame 0, as long as the clips (or what the file has left); a bed trimmed or extended by
    /// hand keeps its span while the list plays the same music from the same point.
    static func placeMusic(
        _ music: Music, length total: Int, kept: HandEdits = HandEdits([]), in planner: inout LayerPlanner
    ) throws -> Placement? {
        guard let media = planner.project.media.first(where: { $0.id == music.media }) else { return nil }
        let track = try planner.project.requireTrack(role: TrackRole.music)
        let fps = planner.project.fps.value
        let available = Int(((media.durationSeconds - music.from) * fps).rounded(.down))
        let duration = min(total, max(1, available))
        let sourceIn = Int((music.from * media.fps.value).rounded(.down))
        let span = musicSpan(music, media: media, length: duration, kept: kept, fps: fps)
        let id = "plan-music"
        try planner.placeMedia(media, on: track.id, at: span.at, duration: span.duration, itemID: id, sourceIn: span.sourceIn)
        var patch: [String: JSONValue] = [tag: .string("music")]
        if let volume = music.volumeDb {
            patch["volumeDb"] = .number(volume)
        } else if !music.ducks {
            patch["volumeDb"] = .number(Music.fallbackVolumeDb)
        }
        // The span the build gives the bed, so the next apply knows a hand trim from it.
        patch[musicTag] = .object([
            "at": .integer(0), "dur": .integer(duration), "in": .integer(sourceIn), "media": .string(media.id),
            "underVoiceDb": music.measuresLevel ? .number(music.underVoiceDb ?? Music.defaultUnderVoiceDb) : .null,
        ])
        try planner.add([.setProperties(item: id, patch: recordingAudio(patch))])
        return Placement(id: "music", at: span.at, end: span.at + span.duration)
    }
}

// MARK: Voiceover lines and graphics

extension PlanCut {
    /// A line's take as the caller found it: its media (added in the same edit when the project has none for the
    /// file), the voice facts its item keeps, the words heard in it (seconds of the take) and facts for the check.
    public struct LineTake: Sendable {
        public var media: Media
        public var voice: [String: JSONValue]
        public var words: [CaptionWords.Timed]
        public var facts: [String: JSONValue]

        public init(media: Media, voice: [String: JSONValue], words: [CaptionWords.Timed], facts: [String: JSONValue] = [:]) {
            self.media = media
            self.voice = voice
            self.words = words
            self.facts = facts
        }
    }

    /// The lines on the Voiceover layer one after another from frame 0 (or each one's `at`), `pause` apart; a line
    /// without a take is left out (plan check reports it).
    static func placeLines(_ lines: [Line], takes: [String: LineTake], in planner: inout LayerPlanner) throws -> [Placement] {
        guard !lines.isEmpty else { return [] }
        let fps = planner.project.fps.value
        let track = try planner.project.requireTrack(role: TrackRole.voiceover, kind: "audio")
        var placements: [Placement] = []
        var cursor = 0
        for line in lines {
            if let at = line.at { cursor = Int((at * fps).rounded()) }
            guard let take = takes[line.id] else { continue }
            let length = Int((take.media.durationSeconds * fps).rounded(.down))
            guard length > 0 else { continue }
            if !planner.project.media.contains(where: { $0.id == take.media.id }) {
                try planner.add([.addMedia(take.media)])
            }
            var item = Item(id: "plan-" + line.id, media: take.media.id, at: cursor, duration: length)
            item[tag] = .string(line.id)
            if let section = line.section { item[sectionTag] = .string(section) }
            if !take.voice.isEmpty { item["voice"] = .object(take.voice) }
            if let volume = line.volumeDb {
                item["volumeDb"] = .number(volume)
                item[audioTag] = .object(["volumeDb": .number(volume)])
            }
            try planner.place(item, on: track.id)
            placements.append(Placement(id: line.id, at: cursor, end: cursor + length))
            cursor += length + Int((line.pause * fps).rounded())
        }
        return placements
    }

    /// Where the voiceover ends, with the last placed line's pause.
    static func lineEnd(_ lines: [Line], placements: [Placement], fps: Double) -> Int {
        guard let last = placements.last, let line = lines.first(where: { $0.id == last.id }) else { return 0 }
        return last.end + Int((line.pause * fps).rounded())
    }

    /// Section markers at the first line of each section no clip opened.
    static func markLineSections(
        _ lines: [Line], clips: [Resolved], sections: [String: Placement], in planner: inout LayerPlanner
    ) throws {
        let opened = Set(clips.compactMap(\.clip.section))
        let labels = Dictionary(plannedSections(planner.project).map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var markers: [EditOperation] = []
        for line in lines {
            guard let section = line.section, !opened.contains(section), seen.insert(section).inserted,
                let span = sections[section]
            else { continue }
            markers.append(.upsertSection(id: section, label: labels[section] ?? section, atFrame: span.at))
        }
        try planner.add(markers)
    }

    /// The span a graphic asks for, in timeline frames: its anchor's start plus offset, for its seconds, until an
    /// entry's end, else to its anchor's end.
    static func graphicSpan(
        _ graphic: Graphic, anchors: [Placement], sections: [String: Placement], fps: Double
    ) -> Placement? {
        let anchor = graphic.on.flatMap { id in anchors.first { $0.id == id } } ?? graphic.section.flatMap { sections[$0] }
        guard anchor != nil || graphic.at != nil else { return nil }
        let start = max(0, (anchor?.at ?? Int(((graphic.at ?? 0) * fps).rounded())) + Int((graphic.offset * fps).rounded()))
        let end: Int
        if let seconds = graphic.seconds {
            end = start + Int((seconds * fps).rounded())
        } else if let until = graphic.until {
            guard let entry = anchors.first(where: { $0.id == until }) else { return nil }
            end = entry.end
        } else {
            end = anchor?.end ?? start
        }
        return end > start ? Placement(id: graphic.id, at: start, end: end) : nil
    }

    /// Graphics full canvas on the Overlay layer (spilling onto another overlay where one already shows) or on
    /// Main, each for its span or what its movie has left after `from`. A graphic without media gets its span only
    /// (plan check reports it, so a graphics plugin can render it to that length).
    static func placeGraphics(
        _ graphics: [Graphic], anchors: [Placement], sections: [String: Placement], main: String,
        in planner: inout LayerPlanner
    ) throws -> [Placement] {
        guard !graphics.isEmpty else { return [] }
        let fps = planner.project.fps.value
        var placements: [Placement] = []
        for graphic in graphics {
            guard let span = graphicSpan(graphic, anchors: anchors + placements, sections: sections, fps: fps) else { continue }
            guard let id = graphic.media, let media = planner.project.media.first(where: { $0.id == id }) else {
                placements.append(span)
                continue
            }
            let sourceIn = media.isImage ? 0 : Int((graphic.from * media.fps.value).rounded(.down))
            let available = media.isImage ? span.end - span.at
                : Int(((media.durationSeconds - graphic.from) * fps).rounded(.down))
            let length = max(1, min(span.end - span.at, available))
            var item = Item(id: "plan-" + graphic.id, media: media.id, at: span.at, duration: length, sourceIn: sourceIn)
            item[tag] = .string(graphic.id)
            item["tag"] = .object(["role": .string("graphic")])
            if media.hasAudio == true { mute(&item) }
            try planner.place(item, on: graphic.main ? main : try overlayTrack(in: &planner))
            let asked = span.end - span.at
            placements.append(Placement(id: graphic.id, at: span.at, end: span.at + length, asked: asked > length ? asked : nil))
        }
        return placements
    }

    /// The first video layer with the overlay role, added above Main when there is none.
    static func overlayTrack(in planner: inout LayerPlanner) throws -> String {
        if let track = planner.project.track(role: TrackRole.overlay, kind: "video") { return track.id }
        let main = try planner.project.requireTrack(role: TrackRole.main)
        let track = planner.project.overflowTrack(from: main)
        try planner.add([.addTrack(track: track, atIndex: planner.project.overflowIndex(for: main, role: TrackRole.overlay))])
        return track.id
    }
}
