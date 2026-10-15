import CryptoKit
import Foundation

/// Captions `plan.apply` builds: from the transcript through the built clips and from each voice line's take. The
/// built cues carry `planCut: "captions"` and `planCaptions`, a digest of what was generated; `captions group` keeps
/// both on the cues it makes. A later apply that would generate the same cues keeps the ones on the timeline (hand
/// grouped or not); one that would generate different cues replaces them all, and never stacks a second set (#628).
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
    /// build, rather than stacking two sets.
    static func rebuildCaptions(_ spec: Spec, clips: [Resolved], sources: CaptionSources, in planner: inout LayerPlanner) throws {
        let old = planner.project.tracks.flatMap(\.items).filter { $0.fields[tag] == .string("captions") }
        var scratch = planner
        for item in old { try scratch.add([.delete(item: item.id, ripple: false)]) }
        guard let captions = spec.captions else {
            planner = scratch
            return
        }
        let before = Set(scratch.project.tracks.flatMap(\.items).map(\.id))
        try placeCaptions(
            captions, clips: clips, transcripts: sources.transcripts, textPresets: sources.textPresets, in: &scratch)
        try placeLineCaptions(
            captions, lines: spec.voiceover, takes: sources.takes, textPresets: sources.textPresets, in: &scratch)
        let added = scratch.project.tracks.flatMap(\.items).filter { !before.contains($0.id) }
        let digest = captionsDigest(added)
        if !old.isEmpty, old.allSatisfy({ $0.fields[captionsTag] == .string(digest) }) { return }
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
        planner = scratch
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
