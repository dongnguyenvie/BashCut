import BashCutAutomation
import BashCutEngine
import BashCutPlugins
import BashCutProject
import Foundation

/// Beat grid v2 and music energy (P0-B10): `beats.detect` keeps the provider's whole grid for the file (beats in its
/// own seconds with strengths, downbeats, confidence, fit and half/double alternates) next to the timeline grid;
/// `beats.grid` reads it with the downbeats on the timeline; `audio.energy` gives the energy curve and
/// lift/drop/breath candidates, also at the timeline frames where the media plays.
extension ProjectDocument {
    static func beatKey(_ url: URL) throws -> String {
        try ProjectCache.contentKey(for: url, namespace: "media-beats-v1")
    }

    func storeBeatGrid(_ generated: GeneratedBeatGrid, url: URL, root: URL) throws {
        let key = try Self.beatKey(url)
        let record: JSONValue = .object([
            "version": .integer(1), "key": .string(key), "bpm": .number(generated.bpm),
            "beatsSeconds": .array(generated.beatSeconds.map(JSONValue.number)), "grid": .object(generated.grid),
            "provider": .object(generated.provenance.json),
            "measuredAt": .string(ISO8601DateFormatter().string(from: Date())),
        ])
        try ProjectCache.store(record, .beats, key: key, projectRoot: root)
    }

    /// The stored grid of `mediaID`'s file as it is now, or nil.
    func storedBeatGrid(_ mediaID: String) throws -> JSONValue? {
        let source = try analysisSource(mediaID)
        let key = try Self.beatKey(source.url)
        guard let record = ProjectCache.record(JSONValue.self, .beats, key: key, projectRoot: source.root),
            record.object["key"]?.string == key
        else { return nil }
        return record
    }

    /// Timeline frames where `seconds` of `media` play, through every clip of it.
    func timelineFrames(of seconds: [Double], media: Media) -> [JSONValue] {
        var frames: [JSONValue] = []
        for item in project.tracks.flatMap(\.items) where item.mediaID == media.id {
            let start = Double(item.sourceIn) / media.fps.value
            let end = start + item.sourceSeconds(afterFrames: item.duration, fps: project.fps)
            for second in seconds where second >= start && second <= end {
                let frame = item.at + Int(item.timelineFrames(atSourceSeconds: second - start, fps: project.fps).rounded())
                frames.append(.object(["seconds": .number(second), "item": .string(item.id), "frame": .integer(frame)]))
            }
        }
        return frames
    }

    func registerBeatGridCommands() {
        handle("beats.grid") { document, arguments, _ in
            let mediaID = try arguments.string("media")
            guard var record = try document.storedBeatGrid(mediaID)?.object,
                let media = document.project.media.first(where: { $0.id == mediaID })
            else { throw RPCFailure(-32602, "Media \(mediaID) has no stored beat grid: run beats detect first") }
            let downbeats = record["grid"]?.object["downbeats"]?.array.compactMap(\.double) ?? []
            record["downbeatFrames"] = .array(document.timelineFrames(of: downbeats, media: media))
            record["media"] = .string(mediaID)
            return .object(record)
        }
        handleAuthored("audio.energy") { document, arguments, author in
            let mediaID = try arguments.string("media")
            let provider = arguments.optionalString("provider")
            return try await document.startCapabilityJob("audio.energy", author: author, arguments: arguments) { document in
                let (root, media, url) = try document.capabilityMedia(mediaID)
                let generated = try await document.plugins.running("audio.energy") {
                    try await document.plugins.service.analyzeEnergy(
                        mediaURL: url,
                        preferredProvider: provider ?? document.project.preferredProvider(for: "audio.energy"),
                        projectRoot: root)
                }
                var result = generated.result.object
                // Where the file plays on the timeline, to place a second of the curve.
                result["timeline"] = .array(document.project.tracks.flatMap(\.items).filter { $0.mediaID == media.id }.map { item in
                    let start = Double(item.sourceIn) / media.fps.value
                    return .object([
                        "item": .string(item.id), "at": .integer(item.at), "fromSeconds": .number(start),
                        "toSeconds": .number(start + item.sourceSeconds(afterFrames: item.duration, fps: document.project.fps)),
                    ])
                })
                result["media"] = .string(mediaID)
                result["provider"] = .object(generated.provenance.json)
                return .object(result)
            }
        }
    }
}
