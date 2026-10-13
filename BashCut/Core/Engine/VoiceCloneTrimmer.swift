import Foundation

/// One measured fact about a clone reference (#532): what was measured, its value and whether it passes.
public struct VoiceCloneCheck: Sendable, Equatable {
    /// `length`, `loudness`, `speech`, `gaps`, `noise` or `clipping`.
    public let id: String
    public let passed: Bool
    public let value: Double
    public let detail: String
}

/// Why a source cannot give a clone reference, with the checks measured on the way.
public struct VoiceCloneRefusal: Error, LocalizedError, Sendable {
    /// `tooShort`, `tooQuiet`, `mostlySilence`, `notEnoughSpeech` or `clipped`.
    public let reason: String
    public let message: String
    public let checks: [VoiceCloneCheck]
    public var errorDescription: String? { message }
}

/// The window of a source chosen as a clone reference, in seconds from the start of the samples.
public struct VoiceCloneWindow: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let checks: [VoiceCloneCheck]
    public var seconds: Double { end - start }
}

/// Picks the best clean stretch of speech for a clone reference (#532): the window within the provider's
/// [min, max] seconds with the most speech, the fewest long gaps and no clipping, starting and ending between words.
/// Speech comes from Apple's sound classifier when it ran (with music under the voice), else from levels: frames
/// 10 dB over the noise floor and within 30 dB of the loud frames. A second speaker is not detected.
public enum VoiceCloneTrimmer {
    /// Seconds per level frame.
    static let frame = 0.05
    /// A silent run at least this long counts as a gap.
    static let gapSeconds = 0.4

    struct Levels {
        let decibels: [Double]
        let clipped: [Int]
        let voiced: [Bool]
        let floor: Double
        let loud: Double
        let rate: Double
        /// Speech level over the noise between words, in dB.
        let noise: Double
        /// Music confidence per frame (empty without the classifier).
        let music: [Double]
    }

    /// Frame levels and which frames are speech: with `classes`, frames the classifier calls speech (confidence 0.5 or
    /// more) above −55 dBFS; without, frames 10 dB over the noise floor and within 30 dB of the loud frames.
    static func levels(_ samples: [Float], rate: Double, classes: VoiceCloneClassification? = nil) -> Levels {
        let hop = max(1, Int(rate * frame))
        var decibels: [Double] = [], clipped: [Int] = []
        for start in stride(from: 0, to: samples.count - hop + 1, by: hop) {
            var power = 0.0, clips = 0
            for value in samples[start..<(start + hop)] {
                power += Double(value * value)
                if abs(value) >= 0.999 { clips += 1 }
            }
            decibels.append(20 * log10(sqrt(power / Double(hop)) + 1e-9))
            clipped.append(clips)
        }
        let sorted = decibels.sorted()
        let pick = { (share: Double) in sorted.isEmpty ? -180 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * share))] }
        let (floor, loud) = (pick(0.1), pick(0.95))
        guard let classes else {
            let threshold = max(floor + 10, loud - 30, -55)
            return Levels(
                decibels: decibels, clipped: clipped, voiced: decibels.map { $0 > threshold }, floor: floor, loud: loud,
                rate: rate, noise: loud - floor, music: [])
        }
        let voiced = decibels.indices.map { $0 < classes.speech.count && classes.speech[$0] >= 0.5 && decibels[$0] > -55 }
        let median = { (values: [Double]) in values.isEmpty ? nil : values.sorted()[values.count / 2] }
        let speechLevel = median(decibels.indices.filter { voiced[$0] }.map { decibels[$0] })
        let quietLevel = median(decibels.indices.filter { !voiced[$0] }.map { decibels[$0] })
        let noise = speechLevel.flatMap { speech in quietLevel.map { speech - $0 } } ?? loud - floor
        return Levels(
            decibels: decibels, clipped: clipped, voiced: voiced, floor: floor, loud: loud, rate: rate, noise: noise,
            music: decibels.indices.map { $0 < classes.music.count ? classes.music[$0] : 0 })
    }

    /// Chooses the window or refuses with the reason. `classes` (the sound classifier's speech and music per frame)
    /// replaces the level threshold for speech and adds the music check.
    public static func choose(
        _ samples: [Float], rate: Double, minSeconds: Double, maxSeconds: Double,
        classes: VoiceCloneClassification? = nil
    ) throws -> VoiceCloneWindow {
        let total = Double(samples.count) / rate
        var checks = [VoiceCloneCheck(
            id: "length", passed: total >= minSeconds, value: round(total),
            detail: "source \(round(total)) s, needs \(round(minSeconds))–\(round(maxSeconds)) s")]
        guard total >= minSeconds else {
            throw VoiceCloneRefusal(
                reason: "tooShort",
                message: "The source is \(round(total)) s; a clone needs at least \(round(minSeconds)) s of speech",
                checks: checks)
        }
        let levels = levels(samples, rate: rate, classes: classes)
        checks.append(VoiceCloneCheck(
            id: "loudness", passed: levels.loud >= -45, value: round(levels.loud),
            detail: "loud frames at \(round(levels.loud)) dBFS (needs −45 or more)"))
        guard levels.loud >= -45 else {
            throw VoiceCloneRefusal(reason: "tooQuiet", message: "The source is too quiet to clone from", checks: checks)
        }
        let share = Double(levels.voiced.filter { $0 }.count) / Double(max(1, levels.voiced.count))
        guard share >= 0.25 else {
            checks.append(VoiceCloneCheck(id: "speech", passed: false, value: round(share), detail: "speech in the source"))
            throw VoiceCloneRefusal(
                reason: "mostlySilence", message: "The source has little speech (silence, or music or noise without a voice); "
                    + "pick a part where the voice speaks",
                checks: checks)
        }
        let (start, end) = bestWindow(levels, minFrames: Int((minSeconds / frame).rounded(.up)),
                                      maxFrames: Int((maxSeconds / frame).rounded(.down)))
        return try finish(levels, start: start, end: end, minSeconds: minSeconds, checks: checks)
    }

    /// Frames [start, end) with the best score over lengths from max down to min (0.5 s steps) and starts 0.1 s apart.
    static func bestWindow(_ levels: Levels, minFrames: Int, maxFrames: Int) -> (Int, Int) {
        let count = levels.voiced.count
        let gap = longGapFrames(levels.voiced)
        var voicedSum = [0], gapSum = [0], clipSum = [0]
        for index in 0..<count {
            voicedSum.append(voicedSum[index] + (levels.voiced[index] ? 1 : 0))
            gapSum.append(gapSum[index] + (gap[index] ? 1 : 0))
            // Music under the voice counts like clipping.
            let spoiled = levels.clipped[index] > 0 || (index < levels.music.count && levels.music[index] >= 0.5)
            clipSum.append(clipSum[index] + (spoiled ? 1 : 0))
        }
        let upper = min(maxFrames, count), lower = min(max(1, minFrames), upper)
        var lengths = Array(stride(from: upper, through: lower, by: -10))
        if lengths.last != lower { lengths.append(lower) }
        var best = (score: -Double.infinity, start: 0, end: upper)
        for length in lengths {
            for start in stride(from: 0, through: count - length, by: 2) {
                let end = start + length
                let speech = Double(voicedSum[end] - voicedSum[start]) * frame
                let gaps = Double(gapSum[end] - gapSum[start]) * frame
                // Clean speech beats clipped speech of the same length; clipped speech still beats silence.
                let clipped = Double(clipSum[end] - clipSum[start]) * frame
                var score = speech - gaps - clipped * 0.5
                if start == 0 || !levels.voiced[start] { score += 0.3 }
                if end == count || !levels.voiced[end - 1] { score += 0.3 }
                if score > best.score { best = (score, start, end) }
            }
        }
        return (best.start, best.end)
    }

    /// Frames inside silent runs of at least `gapSeconds`.
    static func longGapFrames(_ voiced: [Bool]) -> [Bool] {
        var result = [Bool](repeating: false, count: voiced.count)
        var runStart: Int?
        for index in 0...voiced.count {
            let silent = index < voiced.count && !voiced[index]
            if silent, runStart == nil { runStart = index }
            if !silent, let first = runStart {
                if Double(index - first) * frame >= gapSeconds { for gapIndex in first..<index { result[gapIndex] = true } }
                runStart = nil
            }
        }
        return result
    }

    /// Tightens the window to the speech inside it (0.1 s before, 0.15 s after) while it stays long enough, then
    /// checks speech, gaps, noise and clipping.
    static func finish(
        _ levels: Levels, start: Int, end: Int, minSeconds: Double, checks: [VoiceCloneCheck]
    ) throws -> VoiceCloneWindow {
        var checks = checks
        let minFrames = Int((minSeconds / frame).rounded(.up))
        var (first, last) = (start, end)
        if let onset = (start..<end).first(where: { levels.voiced[$0] }) { first = max(start, onset - 2) }
        if let tail = (start..<end).last(where: { levels.voiced[$0] }) { last = min(end, tail + 4) }
        if last - first < minFrames { (first, last) = (start, end) }
        let voiced = levels.voiced[first..<last].filter { $0 }.count
        let speech = Double(voiced) * frame
        var longest = 0, run = 0
        for value in levels.voiced[first..<last] {
            run = value ? 0 : run + 1
            longest = max(longest, run)
        }
        let clipped = Double(levels.clipped[first..<last].reduce(0, +)) / (Double(last - first) * frame * levels.rate)
        let noise = levels.noise
        checks += [
            VoiceCloneCheck(id: "speech", passed: speech >= minSeconds * 0.6, value: round(speech),
                            detail: "\(round(speech)) s of speech in the window"),
            VoiceCloneCheck(id: "gaps", passed: Double(longest) * frame < 1, value: round(Double(longest) * frame),
                            detail: "longest pause in the window"),
            VoiceCloneCheck(id: "noise", passed: noise >= 15, value: round(noise),
                            detail: "speech \(round(noise)) dB over the noise floor (15 or more is clean)"),
            VoiceCloneCheck(id: "clipping", passed: clipped <= 0.001, value: (clipped * 10_000).rounded() / 10_000,
                            detail: "share of clipped samples in the window"),
        ]
        guard speech >= minSeconds * 0.6 else {
            throw VoiceCloneRefusal(
                reason: "notEnoughSpeech",
                message: "No \(round(minSeconds)) s stretch has enough continuous speech; pick a part where the voice "
                    + "speaks without long pauses", checks: checks)
        }
        guard clipped <= 0.001 else {
            throw VoiceCloneRefusal(
                reason: "clipped", message: "The voice is clipped (distorted) everywhere; record it quieter", checks: checks)
        }
        try checkMusic(levels, first: first, last: last, checks: &checks)
        return VoiceCloneWindow(start: Double(first) * frame, end: Double(last) * frame, checks: checks)
    }

    /// With the classifier: the share of window frames where music is likely (confidence 0.5 or more). Under 0.2
    /// passes; over half refuses with `musicUnder`.
    static func checkMusic(_ levels: Levels, first: Int, last: Int, checks: inout [VoiceCloneCheck]) throws {
        guard !levels.music.isEmpty, last > first else { return }
        let share = Double(levels.music[first..<last].filter { $0 >= 0.5 }.count) / Double(last - first)
        checks.append(VoiceCloneCheck(
            id: "music", passed: share < 0.2, value: round(share), detail: "share of the window with music under the voice"))
        guard share <= 0.5 else {
            throw VoiceCloneRefusal(
                reason: "musicUnder", message: "Music plays under the voice; pick a part without music", checks: checks)
        }
    }

    static func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
