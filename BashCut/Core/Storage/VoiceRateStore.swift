import BashCutProject
import Foundation

/// Speaking rates measured on synthesized takes, kept per voice (P0-C2, P0-C4): `voice speak` adds each take's rate,
/// and `speech rate` and `capabilities get --voices` read them, so a voice's pace is a measurement on this Mac, not an assumption.
/// One JSON file in the user's BashCut folder; the newest 30 samples per voice are kept.
public final class VoiceRateStore: @unchecked Sendable {
    public static let shared = VoiceRateStore(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BashCut/voice-rates.json"))

    public struct Sample: Codable, Sendable, Equatable {
        public var language: String
        public var unit: String
        public var rate: Double
        public var at: Date
    }

    private let url: URL
    private let lock = NSLock()
    static let kept = 30

    public init(url: URL) { self.url = url }

    private func read() -> [String: [Sample]] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: [Sample]].self, from: data)) ?? [:]
    }

    public func record(voice: String, language: String, unit: String, rate: Double) {
        guard rate.isFinite, rate > 0 else { return }
        lock.withLock {
            var all = read()
            all[voice, default: []].append(Sample(language: language, unit: unit, rate: rate, at: Date()))
            all[voice] = Array(all[voice, default: []].suffix(Self.kept))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? encoder.encode(all).write(to: url, options: .atomic)
        }
    }

    /// Per voice and language: unit, sample count and p10/p50/p90 of the rates.
    public func summary(voice: String? = nil) -> JSONValue {
        let all = lock.withLock { read() }
        var rows: [JSONValue] = []
        for key in all.keys.sorted() where voice == nil || key == voice {
            for (language, samples) in Dictionary(grouping: all[key] ?? [], by: \.language).sorted(by: { $0.key < $1.key }) {
                let rates = samples.map(\.rate).sorted()
                let at = { (share: Double) in
                    JSONValue.number((rates[min(rates.count - 1, Int((Double(rates.count - 1) * share).rounded()))] * 100).rounded() / 100)
                }
                rows.append(.object([
                    "voice": .string(key), "language": .string(language), "unit": .string(samples.last?.unit ?? ""),
                    "samples": .integer(samples.count), "p10": at(0.1), "p50": at(0.5), "p90": at(0.9),
                ]))
            }
        }
        return .array(rows)
    }
}
