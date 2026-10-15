import Foundation

/// How a Music layer ducks under speech (#630). Speech is the voiceover layers and dialogue tagged as speech; a gap
/// between lines shorter than the layer's hold (`duckMinGapFrames`, 2.5 s when unset) keeps the music down, so it
/// rises only in a long silence instead of pumping between closely spaced lines.
public enum MusicDucking {
    /// The hold when a layer sets none: gaps shorter than this between lines keep the music down.
    public static let defaultMinGapSeconds = 2.5
    /// A level change of at least this many dB counts as one move of the bed.
    public static let pumpStepDb = 3.0
    /// More level moves per minute of speech than this, in gaps shorter than the default hold, is a pumping bed.
    public static let pumpMovesPerMinute = 4.0

    /// The frames speech covers, merged, from layers that are not muted.
    public static func speechRanges(in project: Project) -> [Range<Int>] {
        let items = Dictionary(
            uniqueKeysWithValues: project.tracks.flatMap { track in
                track.items.map { ($0.id, $0) }
            })
        let ranges = project.tracks.flatMap { track -> [Range<Int>] in
            guard track.role == TrackRole.voiceover || track.role == TrackRole.dialogue, !track.isMuted else { return [] }
            return track.items.compactMap { item in
                let isSpeech: Bool
                if track.role == TrackRole.voiceover {
                    isSpeech = true
                } else if item["tag"]?.object["role"]?.string == "speech" {
                    isSpeech = true
                } else if let videoID = item["linkedVideo"]?.string {
                    isSpeech = items[videoID]?["tag"]?.object["role"]?.string == "speech"
                } else {
                    isSpeech = false
                }
                return isSpeech ? item.at..<item.end : nil
            }
        }
        return held(ranges, minGap: 0)
    }

    /// `ranges` sorted and merged, with gaps shorter than `minGap` frames filled in.
    public static func held(_ ranges: [Range<Int>], minGap: Int) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.sorted(by: { ($0.lowerBound, $0.upperBound) < ($1.lowerBound, $1.upperBound) }) {
            if let last = result.last, range.lowerBound - last.upperBound < max(1, minGap) {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// The layer's level under speech in dB, or nil when it does not duck.
    public static func duckDb(_ track: Track) -> Double? {
        guard track.role == TrackRole.music, track["duckingEnabled"] != .bool(false) else { return nil }
        return track["duckUnderSpeechDb"]?.double
    }

    /// The layer's hold in frames: `duckMinGapFrames`, else 2.5 s.
    public static func minGapFrames(_ track: Track, fps: Double) -> Int {
        track["duckMinGapFrames"]?.int ?? Int((defaultMinGapSeconds * fps).rounded())
    }

    /// How a ducking Music layer moves under speech: the gaps where it comes back up (`rises`), those shorter than
    /// the default hold (`shortRises`, the pumping kind), and their moves (down and up) per minute of speech.
    public struct Bed: Sendable, Equatable {
        public var track: String
        public var duckDb: Double
        public var minGapFrames: Int
        public var rises: [Range<Int>]
        public var shortRises: [Range<Int>]
        public var movesPerMinute: Double
        public var pumping: Bool { movesPerMinute > MusicDucking.pumpMovesPerMinute }
    }

    /// Each ducking Music layer that plays under speech, with the gaps where it rises.
    public static func beds(_ project: Project) -> [Bed] {
        let fps = project.fps.value
        let speech = speechRanges(in: project)
        guard let first = speech.first?.lowerBound, let last = speech.last?.upperBound, fps > 0 else { return [] }
        let short = Int((defaultMinGapSeconds * fps).rounded())
        return project.tracks.compactMap { track in
            guard let duck = duckDb(track), duck <= -pumpStepDb, !track.isMuted,
                track.items.contains(where: { $0.at < last && $0.end > first })
            else { return nil }
            let hold = minGapFrames(track, fps: fps)
            let held = held(speech, minGap: hold)
            let rises = zip(held, held.dropFirst()).map { $0.upperBound..<$1.lowerBound }.filter { gap in
                track.items.contains { $0.at <= gap.lowerBound && $0.end >= gap.upperBound }
            }
            let shortRises = rises.filter { $0.count < short }
            let minutes = Double(last - first) / fps / 60
            return Bed(
                track: track.id, duckDb: duck, minGapFrames: hold, rises: rises, shortRises: shortRises,
                movesPerMinute: minutes > 0 ? Double(shortRises.count * 2) / minutes : 0)
        }
    }

    /// The music level in dB that puts music measured at `musicLUFS` (at 0 dB) `underVoiceDb` under a voice measured
    /// at `voiceLUFS`, within the clip gain range.
    public static func bedVolumeDb(voiceLUFS: Double, musicLUFS: Double, underVoiceDb: Double) -> Double {
        let raw = voiceLUFS - underVoiceDb - musicLUFS
        return (min(Project.volumeDbRange.upperBound, max(-60, raw)) * 10).rounded() / 10
    }
}
