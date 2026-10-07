@preconcurrency import AVFoundation
import BashCutAutomation
import BashCutEngine
import BashCutProject
import Foundation

/// The shots and cuts on Main (P0-B1, P0-B2): `review.shots` reads them as a sequence (or a source file's measured
/// shots), `review.cuts` lists the cuts with kind and framing, `review.sync` times cuts, text and sound effects
/// against the beat grid and the words, and with `rendered` the last export's sound against the timeline's mix.
extension ProjectDocument {
    func registerReviewTimingCommands() {
        handleAuthored("review.accept") { document, arguments, author in try document.acceptReviewIssue(arguments, author: author) }
        handle("review.shots") { document, arguments, _ in
            var lowVariance: ReviewShots.LowVariance?
            switch (arguments.optionalInt("runLength"), arguments.optionalDouble("maxCV")) {
            case (let length?, let cv?): lowVariance = ReviewShots.LowVariance(runLength: length, maxCV: cv)
            case (nil, nil): break
            default: throw RPCFailure(-32602, "Give runLength and maxCV together")
            }
            guard let mediaID = arguments.optionalString("media") else {
                return ReviewShots.json(
                    document.project, picture: document.reviewPicture, summary: arguments.bool("summary"),
                    lowVariance: lowVariance)
            }
            let (_, record) = try document.storedAnalysis(mediaID)
            guard let record, record.picture != nil, let media = document.project.media.first(where: { $0.id == mediaID })
            else { throw RPCFailure(-32602, "Media \(mediaID) has no picture measurement: run media analyze first") }
            return ReviewShots.json(
                media: media, record: record, minScore: arguments.optionalDouble("minScore") ?? 0.1,
                lowVariance: lowVariance)
        }
        handle("review.cuts") { document, _, _ in ReviewCuts.json(document.project) }
        handle("platforms.list") { document, _, _ in
            let profile = ReviewProfile(document.project)
            let outputs = Set(document.outputPresets.compactMap(\.platform?.id))
            return .object([
                "platforms": .array(OutputPlatform.all.map { platform in
                    var row = profile.applying(to: platform).json.object
                    row["output"] = .bool(outputs.contains(platform.id))
                    row["overridden"] = .bool(profile.applying(to: platform) != platform)
                    return .object(row)
                }),
                "layout": document.layoutPlatform?.json ?? .null,
                "targets": .object(Dictionary(uniqueKeysWithValues: document.outputPresets.map { preset in
                    let target = document.project.loudnessTarget(preset: preset.argument, platform: preset.platform)
                    return (preset.argument, JSONValue.object([
                        "integratedLUFS": .number(target.lufs), "truePeakDbTP": .number(target.truePeak),
                    ]))
                })),
            ])
        }
        handle("review.sync") { document, arguments, _ in
            var kinds: Set<ReviewSync.Event> = [.cuts]
            if let list = arguments.optionalString("events") {
                kinds = try Set(list.split(separator: ",").map { name in
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard let event = ReviewSync.Event(rawValue: trimmed) else {
                        throw RPCFailure(-32602, "Unknown event \(trimmed): use cuts, text or sfx")
                    }
                    return event
                })
            }
            let (words, source) = await document.syncWords()
            var result = ReviewSync.json(document.project, words: words, kinds: kinds).object
            result["wordSource"] = .string(source)
            if arguments.bool("rendered") { result["rendered"] = try await document.renderDrift() }
            return .object(result)
        }
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
}
