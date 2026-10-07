import Foundation

/// How fast people speak in the footage (P0-C2, `speech.rate`), in the content language's unit: per speaker (or the
/// whole file when the provider names none), each phrase's rate over its own length (p10, p50, p90), the overall rate
/// over all phrase time, and the articulation rate over the time words actually sound. Core holds no normal rate.
public enum SpeechRate {
    public static func json(_ transcript: SourceTranscript, unit: SpeechUnits.Unit) -> JSONValue {
        var groups: [String: [(units: Int, seconds: Double, sounding: Double)]] = [:]
        for phrase in transcript.phrases where phrase.end > phrase.start {
            let inside = transcript.words.filter { $0.start >= phrase.start - 0.05 && $0.end <= phrase.end + 0.05 }
            let speakers = Dictionary(grouping: inside.compactMap(\.speaker), by: { $0 }).mapValues(\.count)
            let speaker = speakers.max { $0.value < $1.value }?.key ?? "all"
            let units = SpeechUnits.count(phrase.text, unit: unit)
            guard units > 0 else { continue }
            let sounding = inside.reduce(0) { $0 + max(0, $1.end - $1.start) }
            groups[speaker, default: []].append((units, phrase.end - phrase.start, sounding))
        }
        let round = { (value: Double) in JSONValue.number((value * 100).rounded() / 100) }
        let speakers: [JSONValue] = groups.keys.sorted().map { speaker in
            let phrases = groups[speaker] ?? []
            let rates = phrases.map { Double($0.units) / $0.seconds }.sorted()
            let percentile = { (share: Double) in rates[min(rates.count - 1, Int((Double(rates.count - 1) * share).rounded()))] }
            let units = phrases.reduce(0) { $0 + $1.units }
            let seconds = phrases.reduce(0) { $0 + $1.seconds }
            let sounding = phrases.reduce(0) { $0 + $1.sounding }
            return .object([
                "speaker": speaker == "all" ? .null : .string(speaker), "phrases": .integer(phrases.count),
                "units": .integer(units), "speakingSeconds": round(seconds),
                "rate": .object(["p10": round(percentile(0.1)), "p50": round(percentile(0.5)), "p90": round(percentile(0.9))]),
                "overall": round(seconds > 0 ? Double(units) / seconds : 0),
                "articulation": sounding > 0 ? round(Double(units) / sounding) : .null,
            ])
        }
        return .object([
            "language": .string(transcript.language), "unit": .string(unit.rawValue), "speakers": .array(speakers),
        ])
    }
}
