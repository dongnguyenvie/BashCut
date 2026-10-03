import BashCutProject
import Foundation

struct AudioGainPoint: Equatable, Sendable {
    let frame: Int
    let volume: Float
}

enum AudioGainPlanner {
    static func speechRanges(in project: Project) -> [Range<Int>] {
        let items = Dictionary(
            uniqueKeysWithValues: project.tracks.flatMap { track in
                track.items.map { ($0.id, $0) }
            })
        let ranges = project.tracks.flatMap { track -> [Range<Int>] in
            guard track.role == "voiceover" || track.role == "dialogue", !track.isMuted else { return [] }
            return track.items.compactMap { item in
                let isSpeech: Bool
                if track.role == "voiceover" {
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
        return merge(ranges)
    }

    static func points(
        for item: Item, on track: Track, speech: [Range<Int>], mixGainDb: Double = 0
    ) -> [AudioGainPoint] {
        let silent = item["muted"] == .bool(true) || track.isMuted
        let staticDb = item["volumeDb"]?.double ?? 0
        let volumeKeys = item.motion.flatMap { motion in motion.keys["volume"].map { (motion, $0) } }
        func base(_ frame: Int) -> Double {
            guard !silent else { return 0 }
            let db = volumeKeys.flatMap { $0.0.value("volume", at: Double(frame - item.at)) } ?? staticDb
            return pow(10, (db + mixGainDb) / 20)
        }
        let fadeIn = min(item.duration / 2, max(0, item["fadeIn"]?.int ?? 0))
        let fadeOut = min(item.duration / 2, max(0, item["fadeOut"]?.int ?? 0))
        let duckDb = track.role == "music" && track["duckingEnabled"] != .bool(false)
            ? track["duckUnderSpeechDb"]?.double : nil
        let attack = max(0, track["duckAttackFrames"]?.int ?? 3)
        let release = max(0, track["duckReleaseFrames"]?.int ?? 8)
        let relevant = duckDb == nil ? [] : speech.filter {
            $0.upperBound + release > item.at && $0.lowerBound - attack < item.end
        }
        var frames = Set([item.at, item.end])
        if let keys = volumeKeys?.1 { frames.formUnion(volumeFrames(keys, item: item)) }
        if fadeIn > 0 { frames.insert(item.at + fadeIn) }
        if fadeOut > 0 { frames.insert(item.end - fadeOut) }
        for range in relevant {
            frames.insert(max(item.at, range.lowerBound - attack))
            frames.insert(max(item.at, range.lowerBound))
            frames.insert(min(item.end, range.upperBound))
            frames.insert(min(item.end, range.upperBound + release))
        }
        return frames.sorted().map { frame in
            let fadeGain = min(
                fadeIn > 0 ? Double(frame - item.at) / Double(fadeIn) : 1,
                fadeOut > 0 ? Double(item.end - frame) / Double(fadeOut) : 1)
            let duckGain = relevant.map {
                attenuation(at: frame, speech: $0, db: duckDb ?? 0, attack: attack, release: release)
            }.min() ?? 1
            return AudioGainPoint(
                frame: frame, volume: Float(base(frame) * max(0, min(1, fadeGain)) * duckGain))
        }
    }

    /// Timeline frames inside the item where the volume keys need a point: each key, and between keys whose value
    /// changes, enough steps that the linear ramps between points follow the ease and the dB curve; a hold key
    /// jumps one frame before the next key.
    private static func volumeFrames(_ keys: [ItemMotion.Key], item: Item) -> Set<Int> {
        var frames = Set(keys.map { item.at + $0.frame })
        for (from, to) in zip(keys, keys.dropFirst()) where from.value != to.value {
            if from.ease == .hold {
                frames.insert(item.at + to.frame - 1)
                continue
            }
            let step = max(2, (to.frame - from.frame) / 100)
            frames.formUnion(stride(from: from.frame + step, to: to.frame, by: step).map { item.at + $0 })
        }
        return frames.filter { (item.at...item.end).contains($0) }
    }

    private static func attenuation(
        at frame: Int, speech: Range<Int>, db: Double, attack: Int, release: Int
    ) -> Double {
        let duck = pow(10, db / 20)
        if speech.contains(frame) { return duck }
        if frame < speech.lowerBound, attack > 0, frame >= speech.lowerBound - attack {
            let progress = Double(frame - (speech.lowerBound - attack)) / Double(attack)
            return 1 + (duck - 1) * progress
        }
        if frame >= speech.upperBound, release > 0, frame <= speech.upperBound + release {
            let progress = Double(frame - speech.upperBound) / Double(release)
            return duck + (1 - duck) * progress
        }
        return 1
    }

    private static func merge(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.sorted(by: { ($0.lowerBound, $0.upperBound) < ($1.lowerBound, $1.upperBound) }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
