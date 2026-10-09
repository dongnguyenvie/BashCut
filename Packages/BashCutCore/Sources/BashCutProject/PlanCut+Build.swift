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
    public static func build(
        _ spec: Spec, clips: [Resolved], on project: Project
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
        placements += try placeTitles(spec.titles, anchors: placements, in: &planner)
        if let music = spec.music, total > 0, let placed = try placeMusic(music, length: total, in: &planner) {
            placements.append(placed)
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
            let slot = Slot(
                at: cursor, span: max(1, Int(((resolved.to - resolved.from) * fps).rounded())),
                sourceIn: media.isImage ? 0 : Int((resolved.from * media.fps.value).rounded(.down)), patch: patch)
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
        try planner.add([.setProperties(item: id, patch: patch)])
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
            if picture.hasAudio == true { item["muted"] = .bool(true) }
            try planner.place(item, on: main)
            cursor += length
        }
        return end
    }

    /// Titles on the captions layer (spilling onto another text layer where one is already shown).
    static func placeTitles(_ titles: [Title], anchors: [Placement], in planner: inout LayerPlanner) throws -> [Placement] {
        guard !titles.isEmpty else { return [] }
        let fps = planner.project.fps.value
        let captions = try planner.project.requireTrack(role: TrackRole.captions)
        var placements: [Placement] = []
        for title in titles {
            let anchor = title.clip.flatMap { id in anchors.first { $0.id == id } }
            let start = anchor.map { $0.at + Int((title.offset * fps).rounded()) } ?? Int(((title.at ?? 0) * fps).rounded())
            var item = Item(id: "plan-" + title.id, at: max(0, start), duration: max(1, Int((title.seconds * fps).rounded())))
            item["text"] = .string(title.text)
            if let preset = title.preset { item["textPreset"] = .string(preset) }
            for (key, value) in title.style where !["id", "at", "dur", "in", "media"].contains(key) { item[key] = value }
            item[tag] = .string(title.id)
            try planner.place(item, on: captions.id)
            placements.append(Placement(id: title.id, at: item.at, end: item.end))
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
