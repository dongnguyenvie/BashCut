import Foundation

/// The raw picture measurement as data for the agent (`review.picture`, #463): every sample and every hard cut, with
/// the units and the noise floors the picture checks use, so an agent can judge from the numbers instead of verdicts.
extension ReviewPicture {
    /// The noise floors the picture measurement uses, as documented measurement facts (fractions of full
    /// scale on a 24×24 grey thumbnail).
    public static var floorsJSON: JSONValue {
        .object([
            "blackLuma": .number(blackLuma), "flatSpread": .number(flatSpread), "stillChange": .number(stillChange),
            "stillPeak": .number(stillPeak),
        ])
    }

    /// The measurement for `project`: samples and cuts inside `from..<to` (the whole timeline by default). Cuts are
    /// placed with the project's current items; `current` is false when the timeline changed since the measurement.
    public func json(
        for project: Project, from: Int = 0, to: Int? = nil, samples includeSamples: Bool = true,
        cuts includeCuts: Bool = true
    ) -> JSONValue {
        let end = to ?? Int.max
        let fps = project.fps.value
        let inRange = { (frame: Int) in frame >= from && frame < end }
        var result: [String: JSONValue] = [
            "revision": .integer(revision), "current": .bool(revision == project.revision),
            "fps": .number(fps), "interval": .integer(interval),
            "units": .string(
                "Fractions of full scale (0-1) on a 24x24 grey thumbnail. luma: mean brightness; spread: its "
                    + "standard deviation (near 0 on a flat frame); change: mean absolute difference from the previous "
                    + "sample (1 on the first); peak: largest one-cell difference from the previous sample; cut "
                    + "difference: mean absolute difference between the last frame before a hard cut and the first after."),
            "floors": Self.floorsJSON,
        ]
        if includeSamples {
            result["samples"] = .array(self.samples.filter { inRange($0.frame) }.map { sample in
                .object([
                    "frame": .integer(sample.frame), "seconds": .number(Self.rounded(Double(sample.frame) / fps)),
                    "luma": .number(Self.rounded(sample.luma)), "spread": .number(Self.rounded(sample.spread)),
                    "change": .number(Self.rounded(sample.change)), "peak": .number(Self.rounded(sample.peak)),
                ])
            })
        }
        if includeCuts {
            let placed = Dictionary(Self.hardCuts(project).map { ($0.item, $0) }, uniquingKeysWith: { first, _ in first })
            let main = project.tracks.first { $0.role == "main" }?.items.sorted { $0.at < $1.at } ?? []
            let previous = Dictionary(zip(main.dropFirst(), main).map { ($0.id, $1.id) }, uniquingKeysWith: { first, _ in first })
            let rows: [(frame: Int?, value: JSONValue)] = self.cuts.map { item, difference in
                var row: [String: JSONValue] = ["item": .string(item), "difference": .number(Self.rounded(difference))]
                let cut = placed[item]
                if let cut {
                    row["frame"] = .integer(cut.at)
                    row["before"] = .integer(cut.before)
                    row["seconds"] = .number(Self.rounded(Double(cut.at) / fps))
                }
                if let left = previous[item] { row["fromItem"] = .string(left) }
                return (cut?.at, .object(row))
            }
            // An item that is no longer a hard cut (edited since) has no frame; it stays, last, unless a range is asked.
            result["cuts"] = .array(rows
                .filter { row in row.frame.map(inRange) ?? (from == 0 && to == nil) }
                .sorted { ($0.frame ?? Int.max, "\($0.value)") < ($1.frame ?? Int.max, "\($1.value)") }
                .map(\.value))
        }
        return .object(result)
    }

    static func rounded(_ value: Double) -> Double { (value * 100_000).rounded() / 100_000 }
}
