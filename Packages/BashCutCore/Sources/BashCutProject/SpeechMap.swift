import Foundation

/// Where a source media has sound that may be speech, and the gaps between (P0-A3), with the calibration used.
///
/// The level windows of `media.analyze` (broadband RMS per 0.1 s) are split into a quiet and a loud class by Otsu's
/// method on their dB values, unless the caller gives the threshold. The report says how far apart the classes are
/// (`separationDb`, the loud median minus the quiet median, and `eta`, the share of the level variance the split
/// explains). When they are closer than `minSeparationDb` (a noisy street, music under the voice) it reports
/// `separation: none` and no spans instead of made-up silences. A stored transcript adds the spans where words were
/// recognised, and how much the two agree. Spans are sound, not proof of speech; the agent decides.
public enum SpeechMap {
    public struct Parameters: Sendable, Equatable {
        /// dBFS a window must reach to count as sound; nil calibrates from the media.
        public var thresholdDb: Double?
        /// Gaps up to this many seconds inside a span are bridged.
        public var bridgeSeconds: Double
        /// Spans shorter than this are dropped (clicks, bumps).
        public var minSpeechSeconds: Double
        /// Classes closer than this (dB) do not separate.
        public var minSeparationDb: Double

        public init(
            thresholdDb: Double? = nil, bridgeSeconds: Double = 0.3, minSpeechSeconds: Double = 0.2,
            minSeparationDb: Double = 6
        ) {
            self.thresholdDb = thresholdDb
            self.bridgeSeconds = bridgeSeconds
            self.minSpeechSeconds = minSpeechSeconds
            self.minSeparationDb = minSeparationDb
        }
    }

    /// The two-class split of the levels.
    public struct Calibration: Sendable, Equatable {
        public let thresholdDb: Double
        public let floorDb: Double
        public let speechDb: Double
        public let eta: Double

        public var separationDb: Double { speechDb - floorDb }
    }

    /// Otsu's split of `levels` (dB) in 0.5 dB bins. Digital silence is left out (it is always quiet, and would
    /// otherwise make any recording with a silent head look clearly separated). Nil with fewer than ten windows of
    /// sound or a level that hardly changes.
    public static func calibrate(_ levels: [Double]) -> Calibration? {
        let clamped = levels.filter { $0 > MediaAnalysis.silenceDb }
        guard clamped.count >= 10, let low = clamped.min(), let high = clamped.max(), high - low >= 0.5 else { return nil }
        let bin = 0.5
        let count = Int(((high - low) / bin).rounded(.down)) + 1
        var histogram = [Double](repeating: 0, count: count)
        for level in clamped { histogram[min(count - 1, Int((level - low) / bin))] += 1 }
        let total = Double(clamped.count)
        let centre = { (index: Int) in low + (Double(index) + 0.5) * bin }
        let mean = histogram.indices.map { histogram[$0] * centre($0) }.reduce(0, +) / total
        let variance = clamped.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / total
        var best = (score: -1.0, split: 0)
        var weight = 0.0, sum = 0.0
        for index in 0..<(count - 1) {
            weight += histogram[index]
            sum += histogram[index] * centre(index)
            guard weight > 0, weight < total else { continue }
            let lowMean = sum / weight, highMean = (mean * total - sum) / (total - weight)
            let between = weight * (total - weight) * (lowMean - highMean) * (lowMean - highMean) / (total * total)
            if between > best.score { best = (between, index) }
        }
        guard best.score >= 0 else { return nil }
        let threshold = low + Double(best.split + 1) * bin
        return Calibration(
            thresholdDb: threshold, floorDb: median(clamped.filter { $0 < threshold }),
            speechDb: median(clamped.filter { $0 >= threshold }), eta: variance > 0 ? best.score / variance : 0)
    }

    public static func json(
        sound: MediaAnalysis.Sound, words: [CaptionWords.Timed]?, parameters: Parameters = Parameters()
    ) -> JSONValue {
        let total = Double(sound.levels.count) * sound.window
        let calibration = calibrate(sound.levels)
        var calibrationJSON: [String: JSONValue] = [
            "method": .string(parameters.thresholdDb == nil ? "otsu" : "given"),
            "minSeparationDb": number(parameters.minSeparationDb),
        ]
        if let calibration {
            calibrationJSON["floorDb"] = number(calibration.floorDb)
            calibrationJSON["speechDb"] = number(calibration.speechDb)
            calibrationJSON["separationDb"] = number(calibration.separationDb)
            calibrationJSON["eta"] = number(calibration.eta)
            calibrationJSON["otsuThresholdDb"] = number(calibration.thresholdDb)
        }
        let separation: String
        if parameters.thresholdDb != nil {
            separation = "given"
        } else if let calibration, calibration.separationDb >= parameters.minSeparationDb {
            separation = calibration.separationDb >= 2 * parameters.minSeparationDb ? "clear" : "weak"
        } else {
            separation = "none"
        }
        calibrationJSON["separation"] = .string(separation)
        let threshold = parameters.thresholdDb ?? (separation == "none" ? nil : calibration?.thresholdDb)
        calibrationJSON["thresholdDb"] = threshold.map(number) ?? .null

        let silent = Double(sound.levels.filter { $0 <= MediaAnalysis.silenceDb }.count) * sound.window
        var result: [String: JSONValue] = [
            "measuredOn": .string(
                "broadband RMS per \(sound.window) s window from media.analyze (dBFS); digital silence is quiet and "
                    + "left out of the calibration"),
            "seconds": number(total), "digitalSilenceSeconds": number(silent),
            "calibration": .object(calibrationJSON),
            "parameters": .object([
                "bridgeSeconds": number(parameters.bridgeSeconds), "minSpeechSeconds": number(parameters.minSpeechSeconds),
            ]),
        ]
        let levelSpans = threshold.map { threshold in
            MediaAnalysis.activeSpans(sound, over: threshold, bridge: parameters.bridgeSeconds)
                .filter { $0.1 - $0.0 >= parameters.minSpeechSeconds }
        }
        if let spans = levelSpans {
            result["spans"] = spansJSON(spans)
            result["speechSeconds"] = number(seconds(spans))
            result["speechShare"] = number(total > 0 ? seconds(spans) / total : 0)
            let gaps = gaps(between: spans, total: total)
            result["gaps"] = spansJSON(gaps)
            result["gapStats"] = stats(gaps.map { $0.1 - $0.0 })
        } else {
            result["spans"] = .null
            result["gaps"] = .null
            result["reason"] = .string(
                (calibration == nil
                    ? "Too little sound, or a level that hardly changes: no quiet and loud classes to split."
                    : "Quiet and loud windows are closer than minSeparationDb: the floor and the sound over it do not "
                        + "separate, so no spans are given.")
                    + " Pass thresholdDb to force one (just over \(MediaAnalysis.silenceDb) splits sound from digital "
                    + "silence), or read the transcript spans.")
        }
        if let words {
            let heard = joined(words.map { ($0.start, $0.end) }, bridge: parameters.bridgeSeconds)
            var transcript: [String: JSONValue] = [
                "words": .integer(words.count), "spans": spansJSON(heard), "speechSeconds": number(seconds(heard)),
                "gaps": spansJSON(gaps(between: heard, total: total)),
            ]
            if let level = levelSpans {
                let shared = overlap(level, heard)
                transcript["levelCoveredByWords"] = number(seconds(level) > 0 ? shared / seconds(level) : 0)
                transcript["wordsCoveredByLevel"] = number(seconds(heard) > 0 ? shared / seconds(heard) : 0)
            }
            result["transcript"] = .object(transcript)
        } else {
            result["transcript"] = .null
        }
        return .object(result)
    }

    /// Spans joined across gaps up to `bridge` seconds, sorted.
    static func joined(_ spans: [(Double, Double)], bridge: Double) -> [(Double, Double)] {
        var result: [(Double, Double)] = []
        for span in spans.sorted(by: { $0.0 < $1.0 }) {
            if let last = result.last, span.0 - last.1 <= bridge + 1e-9 {
                result[result.count - 1].1 = max(last.1, span.1)
            } else {
                result.append(span)
            }
        }
        return result
    }

    /// The quiet stretches around and between sorted spans, from 0 to `total`.
    static func gaps(between spans: [(Double, Double)], total: Double) -> [(Double, Double)] {
        var gaps: [(Double, Double)] = []
        var reached = 0.0
        for span in spans {
            if span.0 > reached { gaps.append((reached, span.0)) }
            reached = max(reached, span.1)
        }
        if total > reached { gaps.append((reached, total)) }
        return gaps
    }

    static func overlap(_ first: [(Double, Double)], _ second: [(Double, Double)]) -> Double {
        first.map { span in
            second.map { max(0, min(span.1, $0.1) - max(span.0, $0.0)) }.reduce(0, +)
        }.reduce(0, +)
    }

    static func seconds(_ spans: [(Double, Double)]) -> Double { spans.map { $0.1 - $0.0 }.reduce(0, +) }

    static func spansJSON(_ spans: [(Double, Double)]) -> JSONValue {
        .array(spans.map { start, end in
            .object(["start": number(start), "end": number(end), "seconds": number(end - start)])
        })
    }

    static func stats(_ values: [Double]) -> JSONValue {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return .object(["count": .integer(0)]) }
        let at = { (share: Double) in sorted[min(sorted.count - 1, Int(Double(sorted.count) * share))] }
        return .object([
            "count": .integer(sorted.count), "medianSeconds": number(at(0.5)), "p90Seconds": number(at(0.9)),
            "maxSeconds": number(sorted[sorted.count - 1]),
        ])
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return .nan }
        return sorted.count % 2 == 1
            ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    static func number(_ value: Double) -> JSONValue { .number((value * 1_000).rounded() / 1_000) }
}
