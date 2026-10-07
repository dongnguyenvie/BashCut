import Foundation

/// The timeline's sound as numbers without exporting (#471, P0-B9): loudness over time with its silent stretches,
/// and from stems rendered per role, how loud the voice is, how far music sits under it in each spoken window and
/// how loud it is in the gaps, and for every sound effect its level against the voice around it and where it lands
/// against cuts, beats and words. Levels are LUFS (momentary, 400 ms) unless named dB; no target is applied.
public enum MixMeasure {
    /// Momentary loudness and sample peak every `step` seconds from the timeline start.
    public struct Curve: Sendable, Equatable {
        public var step: Double
        public var momentary: [Double]
        public var peakDb: [Double]

        public init(step: Double = 0.1, momentary: [Double], peakDb: [Double] = []) {
            self.step = step
            self.momentary = momentary
            self.peakDb = peakDb
        }

        /// Value of block `index`, or silence past the end.
        func level(_ index: Int) -> Double { momentary.indices.contains(index) ? momentary[index] : -100 }
    }

    /// The BS.1770 absolute gate: blocks at or under it count as silence.
    public static let silenceLUFS = -70.0

    /// Stretches where momentary loudness stays at or under the absolute gate, in seconds.
    public static func silences(_ curve: Curve) -> JSONValue {
        var rows: [JSONValue] = []
        var start: Int?
        for index in 0...curve.momentary.count {
            let quiet = index < curve.momentary.count && curve.momentary[index] <= silenceLUFS
            if quiet, start == nil { start = index }
            if !quiet, let from = start {
                rows.append(span(from, index, step: curve.step))
                start = nil
            }
        }
        return .array(rows)
    }

    /// Where a sound becomes audible (the first block over the −70 LUFS gate), peaks (the loudest sample block) and
    /// ends (the last block over the gate), in seconds; nil when it never passes the gate.
    public static func landmarks(_ curve: Curve) -> [String: Double]? {
        guard let first = curve.momentary.firstIndex(where: { $0 > silenceLUFS }),
            let last = curve.momentary.lastIndex(where: { $0 > silenceLUFS })
        else { return nil }
        let peak = curve.peakDb.enumerated().max { $0.element < $1.element }?.offset ?? first
        // A momentary block covers 400 ms: the sound ends within the last block over the gate.
        return ["onset": Double(first) * curve.step, "peak": Double(peak) * curve.step, "tail": Double(last) * curve.step + 0.4]
    }

    static func span(_ from: Int, _ to: Int, step: Double) -> JSONValue {
        let round = { (value: Double) in JSONValue.number((value * 100).rounded() / 100) }
        return .object(["start": round(Double(from) * step), "end": round(Double(to) * step), "seconds": round(Double(to - from) * step)])
    }

    /// Median, 10th and 90th percentile of `values`, or null without values.
    static func spread(_ values: [Double]) -> JSONValue {
        guard !values.isEmpty else { return .null }
        let sorted = values.sorted()
        let at = { (share: Double) -> JSONValue in
            let value = sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * share).rounded()))]
            return .number((value * 10).rounded() / 10)
        }
        return .object(["median": at(0.5), "p10": at(0.1), "p90": at(0.9), "blocks": .integer(values.count)])
    }

    /// Which blocks are spoken: those whose middle falls inside a word (frames at `fps`), else those where the
    /// speech stem is over the absolute gate.
    static func spoken(blocks: Int, step: Double, words: [ReviewSync.WordSpan], fps: Double, speech: Curve?) -> [Bool] {
        if !words.isEmpty {
            let spans = words.map { (Double($0.at) / fps, Double($0.end) / fps) }.sorted { $0.0 < $1.0 }
            return (0..<blocks).map { index in
                let middle = (Double(index) + 0.5) * step
                return spans.contains { $0.0 <= middle && middle < $0.1 }
            }
        }
        return (0..<blocks).map { (speech?.level($0) ?? -100) > silenceLUFS }
    }

    public static func json(
        _ project: Project, speech: Curve?, music: Curve?, effects: Curve?, words: [ReviewSync.WordSpan],
        nearSeconds: Double = 1
    ) -> JSONValue {
        let step = speech?.step ?? music?.step ?? effects?.step ?? 0.1
        let blocks = [speech?.momentary.count, music?.momentary.count, effects?.momentary.count].compactMap { $0 }.max() ?? 0
        let fps = project.fps.value
        let inSpeech = spoken(blocks: blocks, step: step, words: words, fps: fps, speech: speech)
        let audible = { (curve: Curve?, index: Int) -> Double? in
            guard let level = curve?.level(index), level > silenceLUFS else { return nil }
            return level
        }
        var voice: [Double] = [], under: [Double] = [], gaps: [Double] = []
        for index in 0..<blocks {
            let music = audible(music, index)
            if inSpeech[index] {
                if let level = audible(speech, index) {
                    voice.append(level)
                    if let music { under.append(level - music) }
                }
            } else if let music {
                gaps.append(music)
            }
        }
        var windows: [JSONValue] = []
        var start: Int?
        for index in 0...blocks {
            let on = index < blocks && inSpeech[index]
            if on, start == nil { start = index }
            if !on, let from = start {
                var row = span(from, index, step: step).object
                let voices = (from..<index).compactMap { audible(speech, $0) }
                let musics = (from..<index).compactMap { audible(music, $0) }
                row["voice"] = spread(voices)
                row["music"] = spread(musics)
                row["musicUnder"] = spread((from..<index).compactMap { i in audible(speech, i).flatMap { v in audible(music, i).map { v - $0 } } })
                windows.append(.object(row))
                start = nil
            }
        }
        return .object([
            "step": .number(step), "speechFrom": .string(words.isEmpty ? "stem" : "words"),
            "voice": spread(voice), "musicUnderSpeech": spread(under), "musicInGaps": spread(gaps),
            "speechWindows": .array(windows),
            "effects": effectsJSON(project, speech: speech, effects: effects, words: words, nearSeconds: nearSeconds),
        ])
    }

    /// Every item on a sound-effects layer: its loudest momentary level and sample peak, the voice's 95th percentile
    /// within `nearSeconds`, the difference, masked (the effect is under that voice level), and its onset and
    /// peak frames against the nearest cut, beat and word.
    static func effectsJSON(
        _ project: Project, speech: Curve?, effects: Curve?, words: [ReviewSync.WordSpan], nearSeconds: Double
    ) -> JSONValue {
        let fps = project.fps.value
        let step = effects?.step ?? 0.1
        let cuts = (project.tracks.first { $0.role == TrackRole.main }?.items.sorted { $0.at < $1.at } ?? []).dropFirst().map(\.at)
        let beats = project.beatFrames
        let edges = words.flatMap { [$0.at, $0.end] }.sorted()
        let items = project.tracks.filter { $0.role == TrackRole.sfx }.flatMap(\.items).sorted { $0.at < $1.at }
        return .array(items.map { item in
            let first = Int(Double(item.at) / fps / step), last = max(first + 1, Int(Double(item.end) / fps / step))
            var row: [String: JSONValue] = ["id": .string(item.id), "at": .integer(item.at), "end": .integer(item.end)]
            let levels = (first..<last).map { effects?.level($0) ?? -100 }
            let peaks = (first..<last).map { index in effects?.peakDb.indices.contains(index) == true ? effects?.peakDb[index] ?? -100 : -100 }
            let loudest = levels.max() ?? -100
            row["loudness"] = .number((loudest * 10).rounded() / 10)
            row["peakDb"] = .number(((peaks.max() ?? -100) * 10).rounded() / 10)
            let peakIndex = first + (peaks.enumerated().max { $0.element < $1.element }?.offset ?? 0)
            let peakFrame = Int((Double(peakIndex) * step * fps).rounded())
            let reach = Int(nearSeconds / step)
            let nearby = ((first - reach)..<(last + reach)).compactMap { index -> Double? in
                guard let level = speech?.level(index), level > silenceLUFS else { return nil }
                return level
            }.sorted()
            if !nearby.isEmpty {
                let p95 = nearby[min(nearby.count - 1, Int((Double(nearby.count - 1) * 0.95).rounded()))]
                row["voiceP95"] = .number((p95 * 10).rounded() / 10)
                row["deltaDb"] = .number(((loudest - p95) * 10).rounded() / 10)
                row["masked"] = .bool(loudest < p95)
            } else {
                row["voiceP95"] = .null
            }
            let offsets = { (frame: Int) -> JSONValue in
                var result: [String: JSONValue] = [:]
                for (name, list) in [("cut", cuts), ("beat", beats), ("word", edges)] {
                    if let near = ReviewSync.nearest(list, to: frame) { result[name] = .integer(frame - near) }
                }
                return .object(result)
            }
            row["onsetOffsets"] = offsets(item.at)
            row["peakFrame"] = .integer(peakFrame)
            row["peakOffsets"] = offsets(peakFrame)
            return .object(row)
        })
    }
}
