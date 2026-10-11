import Foundation

/// Each clip's source range: quotes and word indices through the media's stored transcript, rough seconds kept as
/// given (their edges reported against the transcript), stills for their seconds.
extension PlanCut {
    public static func resolve(
        _ spec: Spec, project: Project, transcripts: [String: SourceTranscript]
    ) -> (clips: [Resolved], problems: [Problem]) {
        var resolved: [Resolved] = []
        var problems: [Problem] = []
        for clip in spec.clips {
            guard let media = project.media.first(where: { $0.id == clip.media }) else {
                problems.append(Problem(id: "unknown-media", severity: "error", entry: clip.id, detail: "No media \(clip.media) in the project"))
                continue
            }
            do {
                let (range, found) = try resolveClip(clip, media: media, transcript: transcripts[media.id])
                problems += found
                if let range { resolved.append(range) }
            } catch {
                problems.append(Problem(id: "range-invalid", severity: "error", entry: clip.id, detail: "\(error)"))
            }
        }
        problems += coverProblems(spec, project: project) + overlaps(resolved)
        return (resolved, problems)
    }

    static func resolveClip(
        _ clip: Clip, media: Media, transcript: SourceTranscript?
    ) throws -> (Resolved?, [Problem]) {
        if media.isImage {
            let seconds = clip.seconds ?? clip.to.map { $0 - (clip.from ?? 0) } ?? 3
            return (Resolved(clip: clip, from: 0, to: seconds, facts: ["still": .bool(true)]), [])
        }
        if clip.quote == nil, clip.words == nil { return try resolveSeconds(clip, media: media, transcript: transcript) }
        guard let transcript else {
            return (nil, [Problem(
                id: "no-transcript", severity: "error", entry: clip.id,
                detail: "\(media.id) has no transcript: media transcribe --media \(media.id), or give from/to")])
        }
        if let span = clip.words {
            let facts = try QuoteRange.json(transcript, media: media, first: span.first, last: span.last).object
            return (ranged(clip, facts), [])
        }
        return try resolveQuote(clip, quote: clip.quote ?? "", media: media, transcript: transcript)
    }

    static func resolveSeconds(
        _ clip: Clip, media: Media, transcript: SourceTranscript?
    ) throws -> (Resolved?, [Problem]) {
        let fps = media.fps.value > 0 ? media.fps.value : 30
        let from = clip.from ?? 0, to = clip.to ?? media.durationSeconds
        guard to > from, to <= media.durationSeconds + 1 / fps else {
            return (nil, [Problem(
                id: "range-outside-media", severity: "error", entry: clip.id,
                detail: String(format: "%@ runs %.2f s; the clip asks %.2f–%.2f s", media.id, media.durationSeconds, from, to))])
        }
        var facts: [String: JSONValue] = [:]
        if let transcript {
            // Rough times are kept as given; the snapped edges are only reported.
            facts = try QuoteRange.json(transcript, media: media, from: from, to: to).object
            facts["from"] = .number(from)
            facts["to"] = .number(to)
        }
        return (Resolved(clip: clip, from: from, to: to, facts: facts), [])
    }

    static func resolveQuote(
        _ clip: Clip, quote: String, media: Media, transcript: SourceTranscript
    ) throws -> (Resolved?, [Problem]) {
        let words = transcript.words.filter { $0.event == nil }
        let found = QuoteRange.find(quote, in: words)
        guard let best = found.first else {
            return (nil, [Problem(
                id: "quote-not-found", severity: "error", entry: clip.id,
                detail: "The quote was not found in \(media.id)'s transcript", facts: ["quote": .string(quote)])])
        }
        var facts = try QuoteRange.json(transcript, media: media, first: best.first, last: best.last, matches: found.count).object
        let matched = Double(best.matched) / Double(max(1, best.last - best.first + 1))
        facts["matched"] = .number((matched * 1_000).rounded() / 1_000)
        var problems: [Problem] = []
        if matched < 1 {
            problems.append(Problem(
                id: "quote-partial", severity: "warning", entry: clip.id,
                detail: "Only part of the quote was heard in place; read text before trusting the range",
                facts: ["matched": .number(matched), "heard": facts["text"] ?? .null]))
        }
        if found.count > 1 {
            facts["alternatives"] = .array(found.dropFirst().map { .number(words[$0.first].start) })
            problems.append(Problem(
                id: "quote-ambiguous", severity: "info", entry: clip.id,
                detail: "The quote is said \(found.count) times; the first is used (give words FIRST-LAST to pick)",
                facts: ["starts": .array(found.map { .number(words[$0.first].start) })]))
        }
        return (ranged(clip, facts), problems)
    }

    /// The resolved range from QuoteRange facts, or nil when they hold no range.
    static func ranged(_ clip: Clip, _ facts: [String: JSONValue]) -> Resolved? {
        guard let from = facts["from"]?.double, let to = facts["to"]?.double, to > from else { return nil }
        return Resolved(clip: clip, from: from, to: to, facts: facts)
    }

    /// Covers naming media the project does not have, or starting past its end.
    static func coverProblems(_ spec: Spec, project: Project) -> [Problem] {
        var problems: [Problem] = []
        for clip in spec.clips {
            for media in Set(clip.cover.map(\.media)) where !project.media.contains(where: { $0.id == media }) {
                problems.append(Problem(id: "unknown-media", severity: "error", entry: clip.id, detail: "No cover media \(media) in the project"))
            }
            for shot in clip.cover {
                guard let media = project.media.first(where: { $0.id == shot.media }), !media.isImage,
                    shot.from >= media.durationSeconds
                else { continue }
                problems.append(Problem(
                    id: "range-outside-media", severity: "error", entry: clip.id,
                    detail: String(format: "Cover %@ starts at %.2f s; the media runs %.2f s", media.id, shot.from, media.durationSeconds)))
            }
        }
        return problems
    }

    /// Two clips showing overlapping source of one media: the viewer sees the same moment twice.
    static func overlaps(_ clips: [Resolved]) -> [Problem] {
        // What the viewer sees: a clip's own picture, or its covers (a cover without seconds: 3 s for this check).
        var spans: [(entry: String, media: String, from: Double, to: Double)] = []
        for clip in clips where clip.facts["still"] == nil {
            if clip.clip.cover.isEmpty {
                spans.append((clip.clip.id, clip.clip.media, clip.from, clip.to))
            } else {
                spans += clip.clip.cover.map { (clip.clip.id, $0.media, $0.from, $0.from + ($0.seconds ?? 3)) }
            }
        }
        var problems: [Problem] = []
        for (index, first) in spans.enumerated() {
            for second in spans[(index + 1)...] where second.media == first.media {
                let overlap = min(first.to, second.to) - max(first.from, second.from)
                guard overlap > 0.05 else { continue }
                problems.append(Problem(
                    id: "source-reused", severity: "warning", entry: second.entry,
                    detail: String(format: "%@ and %@ both show %.2f s of %@", first.entry, second.entry, overlap, first.media),
                    facts: ["clips": .array([.string(first.entry), .string(second.entry)]), "seconds": .number(overlap)]))
            }
        }
        return problems
    }
}
