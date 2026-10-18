import CryptoKit
import Foundation

/// Captions `plan.apply` builds: from the transcript through the built clips and from each voice line's take. The
/// built cues carry `planCut: "captions"` and `planCaptions`, a digest of what was generated; `captions group` keeps
/// both on the cues it makes. A later apply that would generate the same cues keeps the ones on the timeline (hand
/// grouped or not); one that would generate different cues replaces them all, and never stacks a second set (#628).
/// Cues `captions group` made carry how they were grouped (`captionGroup`); their replacements are grouped the same
/// way (B3). Words a built clip played with no caption shown over them (cues deleted by hand) get none again.
extension PlanCut {
    /// The field holding the digest of the captions an apply generated.
    public static let captionsTag = "planCaptions"

    /// What captions are made from: stored transcripts by media ID, voice line takes by line ID, library text presets.
    struct CaptionSources {
        var transcripts: [String: SourceTranscript]
        var takes: [String: LineTake]
        var textPresets: [String: LibraryTextPreset]
    }

    /// Replaces the captions an earlier apply built (and any cues grouped from them) with the list's, or keeps them
    /// when the list would generate the same cues again. Refuses to lay captions over speech captions it did not
    /// build, rather than stacking two sets. `was` is the project before the apply, where the old cues were heard.
    @discardableResult
    static func rebuildCaptions(
        _ spec: Spec, clips: [Resolved], sources: CaptionSources, was: Project, in planner: inout LayerPlanner
    ) throws -> [String: Int] {
        let old = planner.project.tracks.flatMap(\.items).filter { $0.fields[tag] == .string("captions") }
        var scratch = planner
        for item in old { try scratch.add([.delete(item: item.id, ripple: false)]) }
        guard let captions = spec.captions else {
            planner = scratch
            return [:]
        }
        let before = Set(scratch.project.tracks.flatMap(\.items).map(\.id))
        try placeCaptions(
            captions, clips: clips, transcripts: sources.transcripts, textPresets: sources.textPresets, in: &scratch)
        try placeLineCaptions(
            captions, lines: spec.voiceover, takes: sources.takes, textPresets: sources.textPresets, in: &scratch)
        let added = scratch.project.tracks.flatMap(\.items).filter { !before.contains($0.id) }
        let digest = captionsDigest(added)
        if !old.isEmpty, old.allSatisfy({ $0.fields[captionsTag] == .string(digest) }) { return [:] }
        let foreign = scratch.project.tracks.flatMap(\.items).filter { item in
            item.fields[tag] == nil && item["captionMedia"] != nil && added.contains { $0.at < item.end && $0.end > item.at }
        }
        guard foreign.isEmpty else {
            throw ProjectError.invalid(
                "The captions layer holds \(foreign.count) speech caption(s) plan apply did not build where its captions go "
                    + "(\(foreign.prefix(5).map(\.id).joined(separator: ", "))): delete them first, or drop captions from the list")
        }
        for item in added {
            try scratch.add([.setProperties(item: item.id, patch: [captionsTag: .string(digest)])])
        }
        // The old cues as they were heard before the apply (a speed set while rebuilding retimes the scratch copies).
        let wasOld = was.tracks.flatMap(\.items).filter { $0.fields[tag] == .string("captions") }
        let shown = try dropUnshown(Set(added.map(\.id)), heardIn: was, in: &scratch)
        try regroup(shown.left, like: wasOld, heardIn: was, in: &scratch)
        planner = scratch
        return shown.dropped
    }

    /// The media whose built clips `was` played without captions count as deleted by hand (see `dropUnshown`).
    static func captionedMedia(_ was: Project, shown: [Item]) -> Set<String> {
        let built = was.tracks.flatMap(\.items).filter { $0.fields[tag] != nil && $0.fields[tag] != .string("captions") }
        let marked = built.contains { $0[captionedTag] != nil }
        let captioned = marked ? built.filter { $0[captionedTag] == .bool(true) }
            : shown.contains { $0.fields[tag] == .string("captions") } ? built : []
        return Set(shown.compactMap { $0["captionMedia"]?.string }).union(captioned.compactMap(\.mediaID))
    }

    /// Marks the built clips whose media has a transcript the captions are made from (`planCaptioned`), so a later
    /// apply tells captions deleted by hand from a media transcribed since.
    static func markCaptioned(_ spec: Spec, transcripts: [String: SourceTranscript], in planner: inout LayerPlanner) throws {
        guard spec.captions != nil else { return }
        for item in planner.project.tracks.flatMap(\.items) {
            guard let entry = item.fields[tag]?.string, entry != "captions", let media = item.mediaID else { continue }
            let captioned = transcripts[media] != nil
            if item[captionedTag] != .bool(captioned) {
                try planner.add([.setProperties(item: item.id, patch: [captionedTag: .bool(captioned)])])
            }
        }
    }

    /// Leaves out of the rebuilt cues `ids` the words a built clip played in `was` with no caption of that media over
    /// them: cues deleted by hand (chatter, a false start, every cue of a screen recording under the voice) stay
    /// deleted. Count the media `was` showed captions of and the media of clips an apply captioned (`planCaptioned`),
    /// so a media captioned for the first time (transcribed since) gets all its captions; for an edit built before
    /// that mark, every built clip's media once the plan had built captions. Returns the cues left, and the words left
    /// out by media.
    static func dropUnshown(
        _ ids: Set<String>, heardIn was: Project, in planner: inout LayerPlanner
    ) throws -> (left: Set<String>, dropped: [String: Int]) {
        let shown = was.tracks.filter { $0.role == TrackRole.captions }.flatMap(\.items).filter { $0["captionMedia"] != nil }
        var unshown: [(media: String, start: Double, end: Double)] = []
        for media in captionedMedia(was, shown: shown).sorted() {
            let covered = shown.filter { $0["captionMedia"]?.string == media }.map { ($0.at, $0.end) }
            for (clip, asset) in was.audibleClips(media) where clip.fields[tag] != nil {
                let sourceFPS = asset.fps.value > 0 ? asset.fps.value : was.fps.value
                let seconds = { (frame: Int) in
                    Double(clip.sourceIn) / sourceFPS + clip.sourceSeconds(afterFrames: frame - clip.at, fps: was.fps)
                }
                var cursor = clip.at
                for (at, end) in covered.sorted(by: { $0.0 < $1.0 }) where end > cursor && at < clip.end {
                    if at > cursor { unshown.append((media, seconds(cursor), seconds(at))) }
                    cursor = max(cursor, end)
                }
                if cursor < clip.end { unshown.append((media, seconds(cursor), seconds(clip.end))) }
            }
        }
        guard !unshown.isEmpty, let track = planner.project.tracks.first(where: { $0.role == TrackRole.captions }) else {
            return (ids, [:])
        }
        let sources = TimelineTranscript.SourceMap(planner.project)
        var left = ids
        var dropped: [String: Int] = [:]
        for cue in track.items.filter({ ids.contains($0.id) }).sorted(by: { $0.at < $1.at }) {
            let words = TimelineTranscript.words(of: cue, sources: sources)
            let kept = words.filter { word in
                guard let media = word.mediaID, let source = word.source else { return true }
                let middle = (source.start + source.end) / 2
                return !unshown.contains { $0.media == media && $0.start <= middle && middle < $0.end }
            }
            guard kept.count < words.count else { continue }
            let gone = words.filter { word in !kept.contains { $0.at == word.at && $0.text == word.text } }
            dropped.merge(Dictionary(grouping: gone) { $0.mediaID ?? "" }.mapValues(\.count)) { $0 + $1 }
            left.remove(cue.id)
            guard !kept.isEmpty else {
                try planner.add([.delete(item: cue.id, ripple: false)])
                continue
            }
            let spans = kept.map { ReviewSync.WordSpan(at: $0.at, end: $0.end, text: $0.text) }
            let rest = try CaptionGrouping.operation(
                planner.project, words: spans, groups: [Array(spans.indices)], author: .agent,
                mark: cue[CaptionGrouping.field], replacing: [cue.id])
            try planner.add([rest.operation])
            left.formUnion(rest.cues.map(\.id))
        }
        return (left, dropped)
    }

    /// Groups the rebuilt cues `ids` the way `captions group` grouped the old ones: by the same rule (breaking at the
    /// new cuts), or, for chosen groups, keeping together the words heard in the stretch of source one old cue held
    /// (other words keep their generated cue). Does nothing when no old cue was grouped.
    static func regroup(_ ids: Set<String>, like old: [Item], heardIn was: Project, in planner: inout LayerPlanner) throws {
        let marks = old.compactMap { $0.fields[CaptionGrouping.field] }
        guard !marks.isEmpty, let track = planner.project.tracks.first(where: { $0.role == TrackRole.captions }) else { return }
        let project = planner.project
        let sources = TimelineTranscript.SourceMap(project)
        let heard = track.items.filter { ids.contains($0.id) }.sorted { $0.at < $1.at }
            .flatMap { cue in TimelineTranscript.words(of: cue, sources: sources).map { (cue: cue.id, word: $0) } }
        guard !heard.isEmpty else { return }
        let spans = heard.map { ReviewSync.WordSpan(at: $0.word.at, end: $0.word.end, text: $0.word.text) }
        let groups: [[Int]]
        let mark: JSONValue
        if let rule = marks.lazy.compactMap({ CaptionGrouping.Rule(json: $0) }).first {
            groups = CaptionGrouping.groups(spans, rule: rule, fps: project.fps.value, cuts: CaptionGrouping.cuts(project))
            mark = rule.json
        } else {
            // Where each old grouped cue was heard: its media and the source seconds its words cover.
            let wasSources = TimelineTranscript.SourceMap(was)
            let held: [(media: String, start: Double, end: Double)] = old.filter { $0.fields[CaptionGrouping.field] != nil }
                .compactMap { cue in
                    let words = TimelineTranscript.words(of: cue, sources: wasSources)
                    guard let media = words.first?.mediaID else { return nil }
                    let times = words.compactMap(\.source)
                    guard let start = times.map(\.start).min(), let end = times.map(\.end).max() else { return nil }
                    return (media, start, end)
                }
            let keys = heard.map { entry -> String in
                if let media = entry.word.mediaID, let source = entry.word.source {
                    let middle = (source.start + source.end) / 2
                    if let index = held.firstIndex(where: { $0.media == media && $0.start <= middle && middle <= $0.end }) {
                        return "held:\(index)"
                    }
                }
                return "cue:" + entry.cue
            }
            var runs: [[Int]] = []
            for index in keys.indices {
                if index > 0, keys[index] == keys[index - 1] { runs[runs.count - 1].append(index) } else { runs.append([index]) }
            }
            groups = runs
            mark = CaptionGrouping.manualMark
        }
        // Only the rebuilt cues are replaced: hand-made text on the captions layer stays.
        let grouped = try CaptionGrouping.operation(
            project, words: spans, groups: groups, author: .agent, mark: mark, replacing: Set(heard.map(\.cue)))
        try planner.add([grouped.operation])
    }

    /// A digest of generated cues that ignores their IDs, stable across runs.
    static func captionsDigest(_ items: [Item]) -> String {
        let rows = items.sorted { ($0.at, $0.text) < ($1.at, $1.text) }.map { item in
            JSONValue.object(item.fields.filter { $0.key != "id" && $0.key != captionsTag })
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(JSONValue.array(rows))) ?? Data()
        return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
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
            var added = planner.project.tracks.flatMap(\.items).filter { !before.contains($0.id) }
            // The importer captions every clip of the media; a clip placed by hand (a camera picture-in-picture
            // under the voice) is not the plan's, so its cues go.
            let built = planner.project.audibleClips(media).map(\.item).filter { $0.fields[tag] != nil }
            for item in added where !built.contains(where: { $0.at < item.end && $0.end > item.at }) {
                try planner.add([.delete(item: item.id, ripple: false)])
            }
            added = added.filter { item in built.contains { $0.at < item.end && $0.end > item.at } }
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

    /// Captions with each line's own text (its `caption` when given), timed by the words heard in its take.
    static func placeLineCaptions(
        _ captions: Captions, lines: [Line], takes: [String: LineTake], textPresets: [String: LibraryTextPreset],
        in planner: inout LayerPlanner
    ) throws {
        for line in lines {
            guard let take = takes[line.id], !take.words.isEmpty,
                planner.project.tracks.contains(where: { $0.items.contains { $0.fields[tag] == .string(line.id) } })
            else { continue }
            let text = line.caption ?? line.text
            let script = captions.maxChars.map { captionLines(text, maxChars: $0) } ?? text
            let aligned = TextAlignment.cues(script: script, heard: take.words)
            guard !aligned.cues.isEmpty else { continue }
            let before = Set(planner.project.tracks.flatMap(\.items).map(\.id))
            try planner.add([planner.project.importingCues(
                aligned.cues, provenance: ["aligned": .string("voice")], media: take.media.id, words: aligned.words,
                wordStyle: captions.wordStyle)])
            for item in planner.project.tracks.flatMap(\.items) where !before.contains(item.id) {
                var patch = try look(
                    for: item, (captions.preset, captions.style, captions.textStyle), textPresets: textPresets,
                    project: planner.project)
                patch[tag] = .string("captions")
                try planner.add([.setProperties(item: item.id, patch: patch)])
            }
        }
    }

    /// `text` broken into lines of at most `maxChars` characters at word gaps, one cue each; a line breaks early
    /// after a comma or a full stop once it holds half the limit. A word longer than the limit stays whole.
    static func captionLines(_ text: String, maxChars: Int) -> String {
        var lines: [String] = []
        var current = ""
        for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            if !current.isEmpty, current.count + 1 + word.count > maxChars {
                lines.append(current)
                current = word
            } else {
                current = current.isEmpty ? word : current + " " + word
            }
            if let last = word.last, ",.;:!?".contains(last), current.count * 2 >= maxChars {
                lines.append(current)
                current = ""
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.joined(separator: "\n")
    }
}
