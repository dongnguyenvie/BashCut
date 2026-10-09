import Foundation

/// The editorial limits a project's `review` object sets (#466, P0-K1). Core has none of its own: a check whose limit
/// is unset either does not run or reports what it measured as info, with no verdict. A skill or recipe sets the
/// limits that fit the genre; with them set, the checks warn as before. Severities (`review.severities`) and platform
/// overrides (`review.platform`, #469) live in the same object. Validated on every edit.
public struct ReviewProfile: Sendable, Equatable {
    public static let numberKeys: [String: ClosedRange<Double>] = [
        "minShotSeconds": 0.01...60, "maxShotSeconds": 0.1...3_600, "maxStillSeconds": 0.1...3_600,
        "hookSeconds": 0.1...60, "maxSilenceSeconds": 0.1...600, "maxMusicGapSeconds": 0.1...600,
        "voiceoverMarginSeconds": 0...10, "captionLineChars": 1...500, "captionMaxLines": 1...20,
        "stillMotion": 0...1, "jumpCutChange": 0...1, "blackMinSeconds": 0.01...600, "loudnessToleranceLU": 0...20,
        "minTextSize": 0.001...0.5, "minSpeechCoverage": 0...1,
    ]
    public static let severityValues = ["error", "warning", "info", "off"]

    public let values: [String: Double]
    public let severities: [String: String]
    /// Overrides of platform facts when an app changes its interface: `safeArea` fields and `maxSeconds`.
    public let platform: [String: JSONValue]
    /// Whether review reports credits, AI disclosure and rights (`review.credits`, P2-H9); off unless the user asks.
    public let credits: Bool

    public init(_ project: Project) {
        let review = project["review"]?.object ?? [:]
        values = Self.numberKeys.keys.reduce(into: [:]) { result, key in
            if let value = review[key]?.double { result[key] = value }
        }
        severities = (review["severities"]?.object ?? [:]).compactMapValues(\.string)
        platform = review["platform"]?.object ?? [:]
        credits = review["credits"]?.bool ?? false
    }

    public subscript(key: String) -> Double? { values[key] }

    /// A platform with this project's overrides applied.
    public func applying(to platform: OutputPlatform) -> OutputPlatform {
        let area = self.platform["safeArea"]?.object ?? [:]
        let base = platform.safeArea
        let value = { (key: String, fallback: Double) in area[key]?.double ?? fallback }
        return OutputPlatform(
            id: platform.id, title: platform.title, vertical: platform.vertical,
            maxSeconds: self.platform["maxSeconds"]?.double ?? platform.maxSeconds, targetLUFS: platform.targetLUFS,
            maxTruePeakDbTP: platform.maxTruePeakDbTP,
            safeArea: SafeArea(
                top: value("top", base.top), bottom: value("bottom", base.bottom),
                sideWidth: value("sideWidth", base.sideWidth), sideHeight: value("sideHeight", base.sideHeight),
                margin: value("margin", base.margin)),
            facts: platform.facts)
    }
}

extension Project {
    /// The `review` object: known numbers within their ranges, severities from the known values, platform overrides
    /// as fractions. Unknown keys round-trip.
    func validateReviewSettings() throws {
        guard let value = self["review"], value != .null else { return }
        guard case .object(let review) = value else { throw ProjectError.invalid("review: expected object") }
        if let credits = review["credits"], credits != .null, credits.bool == nil {
            throw ProjectError.invalid("review.credits: expected true or false")
        }
        for (key, range) in ReviewProfile.numberKeys {
            guard let field = review[key], field != .null else { continue }
            guard let number = field.double, number.isFinite, range.contains(number) else {
                throw ProjectError.invalid("review.\(key): expected a number in \(range.lowerBound)…\(range.upperBound)")
            }
        }
        if let severities = review["severities"], severities != .null {
            guard case .object(let map) = severities,
                map.values.allSatisfy({ $0.string.map(ReviewProfile.severityValues.contains) == true })
            else {
                throw ProjectError.invalid("review.severities: values must be \(ReviewProfile.severityValues.joined(separator: ", "))")
            }
        }
        try Self.validateReviewRecords(review)
        if let platform = review["platform"], platform != .null {
            let fields = platform.object
            let area = fields["safeArea"]?.object ?? [:]
            guard case .object = platform, area.values.allSatisfy({ ($0.double ?? -1).isFinite && (0...1).contains($0.double ?? -1) }),
                fields["maxSeconds"].map({ ($0.double ?? 0) > 0 }) ?? true
            else { throw ProjectError.invalid("review.platform: safeArea fractions 0–1 and a positive maxSeconds") }
        }
    }

    /// `accepted` ({issueID: {reason}}) and `blockExport` (issue ID prefixes), P1-E1/E2.
    static func validateReviewRecords(_ review: [String: JSONValue]) throws {
        if let accepted = review["accepted"], accepted != .null {
            guard case .object(let map) = accepted, map.count <= 1_000,
                map.values.allSatisfy({ !($0.object["reason"]?.string ?? "").isEmpty })
            else { throw ProjectError.invalid("review.accepted: each issue ID needs {reason}") }
        }
        if let compare = review["compare"], compare != .null {
            guard case .object(let map) = compare, map.values.allSatisfy({ ($0.double ?? -1) >= 0 }) else {
                throw ProjectError.invalid("review.compare: metric → tolerance (a number ≥ 0)")
            }
        }
        if let block = review["blockExport"], block != .null {
            guard case .array(let list) = block, list.allSatisfy({ !($0.string ?? "").isEmpty }) else {
                throw ProjectError.invalid("review.blockExport: expected issue ID prefixes")
            }
        }
    }
}
