@preconcurrency import AVFoundation
import BashCutAutomation
import BashCutEngine
import BashCutProject
import Foundation

/// The shots and cuts on Main (P0-B1, P0-B2): `review.shots` reads them as a sequence (or a source file's measured
/// shots, each cut with its kind and framing), `review.sync` times cuts, text and sound effects
/// against the beat grid and the words, and with `rendered` the last export's sound against the timeline's mix.
extension ProjectDocument {
    func registerReviewTimingCommands() {
        handle("review.compare") { document, arguments, _ in try document.compareReview(arguments) }
        handle("review.packet") { document, arguments, _ in try await document.reviewPacket(arguments) }
        handle("review.verify") { document, arguments, _ in try await document.verifyReviewIssue(arguments) }
        handleAuthored("review.accept") { document, arguments, author in try document.acceptReviewIssue(arguments, author: author) }
        handle("review.shots") { document, arguments, _ in
            guard let mediaID = arguments.optionalString("media") else {
                return ReviewShots.json(
                    document.project, picture: document.reviewPicture, summary: arguments.bool("summary"),
                    range: try arguments.frameRange())
            }
            let (_, record) = try document.storedAnalysis(mediaID)
            guard let record, record.picture != nil, let media = document.project.media.first(where: { $0.id == mediaID })
            else { throw RPCFailure(-32602, "Media \(mediaID) has no picture measurement: run media analyze first") }
            return ReviewShots.json(media: media, record: record, minScore: arguments.optionalDouble("minScore") ?? 0.1)
        }
        handle("platforms.get") { document, arguments, _ in
            guard let id = arguments.optionalString("id") else { return document.platformsJSON(facts: arguments.bool("facts")) }
            guard let platform = OutputPlatform.named(id) else {
                throw RPCFailure(-32602, "Unknown platform \(id); use " + OutputPlatform.all.map(\.id).joined(separator: ", "))
            }
            let applied = ReviewProfile(document.project).applying(to: platform)
            var row = applied.json.object
            row["facts"] = .object(platform.facts.mapValues(\.json))
            row["overridden"] = .bool(applied != platform)
            row["data"] = .object([
                "version": .string(PlatformData.current.version), "origin": .string(PlatformData.current.origin),
            ])
            return .object(row)
        }
        handle("review.sync") { document, arguments, _ in
            var kinds: Set<ReviewSync.Event> = [.cuts]
            if let list = arguments.optionalString("events") {
                kinds = try Set(list.split(separator: ",").map { name in
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard let event = ReviewSync.Event(rawValue: trimmed) else {
                        throw RPCFailure(-32602, "Unknown event \(trimmed): use cuts, text, sfx or captions")
                    }
                    return event
                })
            }
            let (words, source) = await document.syncWords()
            var result = ReviewSync.json(document.project, words: words, kinds: kinds, bins: arguments.bool("bins")).object
            result["wordSource"] = .string(source)
            if arguments.bool("rendered") { result["rendered"] = try await document.renderDrift() }
            return .object(result)
        }
    }

    /// Every platform's facts with the project's overrides (`platforms.get` without an id).
    func platformsJSON(facts: Bool) -> JSONValue {
        let profile = ReviewProfile(project)
        let outputs = Set(outputPresets.compactMap(\.platform?.id))
        return .object([
            "platforms": .array(OutputPlatform.all.map { platform in
                var row = profile.applying(to: platform).json.object
                row["output"] = .bool(outputs.contains(platform.id))
                row["overridden"] = .bool(profile.applying(to: platform) != platform)
                if facts { row["facts"] = .object(platform.facts.mapValues(\.json)) }
                return .object(row)
            }),
            "data": .object([
                "version": .string(PlatformData.current.version), "origin": .string(PlatformData.current.origin),
            ]),
            "layout": layoutPlatform?.json ?? .null,
            "targets": .object(Dictionary(uniqueKeysWithValues: outputPresets.map { preset in
                let target = project.loudnessTarget(preset: preset.argument, platform: preset.platform)
                return (preset.argument, JSONValue.object([
                    "integratedLUFS": .number(target.lufs), "truePeakDbTP": .number(target.truePeak),
                ]))
            })),
        ])
    }

    /// The words heard through the clips from stored transcripts, else the caption words.
    func syncWords() async -> (words: [ReviewSync.WordSpan], source: String) {
        let spans = { (value: JSONValue) in
            value.object["words"]?.array.compactMap { word -> ReviewSync.WordSpan? in
                guard let at = word.object["at"]?.int, let end = word.object["end"]?.int else { return nil }
                return ReviewSync.WordSpan(at: at, end: end, text: word.object["text"]?.string ?? "")
            } ?? []
        }
        let heard = spans(await heardWords(from: 0, to: nil, media: nil))
        if !heard.isEmpty { return (heard, "transcript") }
        let captions = spans(TimelineTranscript.wordsJSON(project))
        return (captions, captions.isEmpty ? "none" : "captions")
    }

    func renderDrift() async throws -> JSONValue {
        guard let render = lastRender, FileManager.default.fileExists(atPath: render.url.path) else {
            throw RPCFailure(-32602, "No export of this session to measure: export first")
        }
        guard render.revision == project.revision else {
            throw RPCFailure(-32602, "The last export shows revision \(render.revision), not \(project.revision): export again")
        }
        for _ in 0..<500 where preview.currentBuild == nil { try await Task.sleep(for: .milliseconds(10)) }
        guard let snapshot = preview.currentBuild else { throw RPCFailure(-32603, "The timeline is not built yet") }
        let rendered = AVURLAsset(url: render.url)
        guard let timeline = try await RenderDrift.envelope(snapshot.composition, mix: snapshot.audioMix),
            let file = try await RenderDrift.envelope(rendered, mix: nil)
        else { return .object(["sound": .bool(false)]) }
        var result = RenderDrift.json(
            RenderDrift.windows(reference: timeline, rendered: file), renderedSeconds: Double(file.count) / 100,
            timelineSeconds: Double(timeline.count) / 100
        ).object
        result["path"] = .string(render.url.path)
        return .object(result)
    }

    /// `review.compare` (P1-E8): two measured media, the project's tolerances.
    func compareReview(_ arguments: CommandArguments) throws -> JSONValue {
        let load = { (id: String) throws -> MediaAnalysis in
            guard let record = try self.storedAnalysis(id).record else {
                throw RPCFailure(-32602, "\(id) is not measured yet: media analyze --media \(id)")
            }
            return record
        }
        let reference = try arguments.string("reference"), ours = try arguments.string("ours")
        let tolerances = (project["review"]?.object["compare"]?.object ?? [:]).compactMapValues(\.double)
        var result = ReviewCompare.json(reference: try load(reference), ours: try load(ours), tolerances: tolerances).object
        result["reference"] = .string(reference)
        result["ours"] = .string(ours)
        return .object(result)
    }
}
