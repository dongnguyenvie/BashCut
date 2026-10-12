import Foundation

/// How an exported video performed (P3-I3): a retention curve and totals imported from a platform's analytics
/// (`outcomes import`), mapped onto the export's sections and words (`outcomes map`). Raw numbers only: a missing
/// value stays null, and nothing is called good or bad.
public enum Outcomes {
    /// One point of a retention curve: seconds into the video and the retention there, in the file's own unit.
    public struct Point: Codable, Sendable, Equatable {
        public var t: Double
        public var retention: Double?

        public init(t: Double, retention: Double?) {
            self.t = t
            self.retention = retention
        }
    }

    /// What was imported for one export.
    public struct Record: Codable, Sendable, Equatable {
        public var export: String
        public var platform: String?
        public var importedAt: Date
        /// `percent` (0–100) or `fraction` (0–1), as the file wrote it.
        public var unit: String
        public var curve: [Point]
        /// Totals as given (views, likes, shares, averageViewSeconds…); a value the file did not give is absent.
        public var totals: [String: JSONValue]

        public init(
            export: String, platform: String?, importedAt: Date = Date(), curve: [Point], totals: [String: JSONValue]
        ) {
            self.export = export
            self.platform = platform
            self.importedAt = importedAt
            let values = curve.compactMap(\.retention)
            unit = !values.isEmpty && values.allSatisfy({ $0 <= 1.5 }) ? "fraction" : "percent"
            self.curve = curve.sorted { $0.t < $1.t }
            self.totals = totals
        }
    }

    public struct Section: Sendable, Equatable {
        public var label: String
        public var start: Double
        public var end: Double

        public init(label: String, start: Double, end: Double) {
            self.label = label
            self.start = start
            self.end = end
        }
    }

    public struct Word: Sendable, Equatable {
        public var text: String
        public var start: Double

        public init(text: String, start: Double) {
            self.text = text
            self.start = start
        }
    }

    // MARK: Import

    public struct Columns: Sendable {
        public var time: String?
        public var retention: String?

        public init(time: String? = nil, retention: String? = nil) {
            self.time = time
            self.retention = retention
        }
    }

    /// The curve and totals in `text`: JSON (`{curve: [{t|time|seconds, retention}], totals: {…}}` or a list of
    /// points) or CSV with a header row. A position column in percent (`Video position (%)`) is turned into seconds
    /// with `duration`. Cells that are empty or not numbers stay null.
    public static func parse(
        _ text: String, duration: Double, columns: Columns = Columns()
    ) throws -> (curve: [Point], totals: [String: JSONValue]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            guard let value = try? JSONValue(parsing: Data(trimmed.utf8)) else {
                throw ProjectError.invalid("The outcomes file is not valid JSON")
            }
            return try parseJSON(value, duration: duration)
        }
        return try parseCSV(trimmed, duration: duration, columns: columns)
    }

    static func parseJSON(_ value: JSONValue, duration: Double) throws -> (curve: [Point], totals: [String: JSONValue]) {
        let list: [JSONValue]
        var totals: [String: JSONValue] = [:]
        switch value {
        case .array(let points): list = points
        case .object(let fields):
            list = (fields["curve"] ?? fields["retention"] ?? fields["points"])?.array ?? []
            totals = (fields["totals"]?.object ?? [:]).filter { $0.value.double != nil }
        default: list = []
        }
        let curve = list.compactMap { entry -> Point? in
            let fields = entry.object
            let time = (fields["t"] ?? fields["time"] ?? fields["seconds"])?.double
                ?? fields["position"]?.double.map { $0 / 100 * duration }
            guard let time, time.isFinite, time >= 0 else { return nil }
            return Point(t: time, retention: (fields["retention"] ?? fields["value"])?.double.flatMap { $0.isFinite ? $0 : nil })
        }
        guard !curve.isEmpty || !totals.isEmpty else {
            throw ProjectError.invalid("No curve points ({t, retention}) or totals in the outcomes JSON")
        }
        return (curve, totals)
    }

    static func parseCSV(
        _ text: String, duration: Double, columns: Columns
    ) throws -> (curve: [Point], totals: [String: JSONValue]) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let header = lines.first else { throw ProjectError.invalid("The outcomes file is empty") }
        let delimiter: Character = header.contains("\t") ? "\t" : header.filter({ $0 == ";" }).count > header.filter({ $0 == "," }).count ? ";" : ","
        let names = cells(header, delimiter: delimiter)
        let lowered = names.map { $0.lowercased() }
        let find = { (given: String?, test: (String) -> Bool) -> Int? in
            if let given { return lowered.firstIndex(of: given.lowercased()) }
            return lowered.firstIndex(where: test)
        }
        let position = columns.time == nil ? lowered.firstIndex { $0.contains("position") } : nil
        let time = position ?? find(columns.time) { name in
            ["time", "second", "sec", "moment"].contains { name.contains($0) } || name == "t"
        }
        let retention = find(columns.retention) { name in
            ["retention", "audience", "watching", "viewers", "%"].contains { name.contains($0) } && !name.contains("position")
        }
        guard let time, let retention, time != retention else {
            throw ProjectError.invalid(
                "Name the columns: no time and retention columns found among \(names.joined(separator: ", ")) "
                    + "(--time-column, --retention-column)")
        }
        let curve = lines.dropFirst().compactMap { line -> Point? in
            let row = cells(line, delimiter: delimiter)
            guard row.indices.contains(time), var seconds = Self.seconds(row[time]) else { return nil }
            if time == position { seconds = seconds / 100 * duration }
            let value = row.indices.contains(retention) ? number(row[retention]) : nil
            return Point(t: seconds, retention: value)
        }
        guard !curve.isEmpty else { throw ProjectError.invalid("No rows with a time in the outcomes file") }
        return (curve, [:])
    }

    static func cells(_ line: String, delimiter: Character) -> [String] {
        var result: [String] = [], current = "", quoted = false
        for character in line {
            if character == "\"" { quoted.toggle() } else if character == delimiter, !quoted {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else { current.append(character) }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    /// "12.5", "12.5s", "1:05" or "0:01:05" as seconds.
    static func seconds(_ text: String) -> Double? {
        let text = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "s", with: "")
        if text.contains(":") {
            let parts = text.split(separator: ":").map { Double($0) }
            guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
            return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
        }
        return number(text)
    }

    static func number(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    // MARK: Map

    /// Per section: retention at its start and end and the raw change, the largest fall and rise between curve
    /// points inside it, the highest point reached after a rise (a replay peak), and viewers at its start when the
    /// totals give views; then the `top` largest falls of the whole curve with the words heard `window` seconds
    /// around each.
    public static func map(
        _ record: Record, sections: [Section], words: [Word], duration: Double, top: Int = 3, window: Double = 4
    ) -> JSONValue {
        let points = record.curve.compactMap { point in point.retention.map { (t: point.t, value: $0) } }
        let spans = sections.isEmpty ? [Section(label: "whole", start: 0, end: duration)] : sections
        let views = record.totals["views"]?.double
        let scale = record.unit == "fraction" ? 1.0 : 100.0
        let near = { (time: Double) -> JSONValue in
            let heard = words.filter { abs($0.start - time) <= window }.map(\.text)
            return heard.isEmpty ? .null : .string(heard.joined(separator: " "))
        }
        let steps = zip(points, points.dropFirst()).map { (from: $0.0, to: $0.1, change: $0.1.value - $0.0.value) }
        let sectionRows = spans.map { section -> JSONValue in
            let start = value(at: section.start, in: points), end = value(at: section.end, in: points)
            let inside = steps.filter { $0.from.t >= section.start && $0.to.t <= section.end }
            let fall = inside.filter { $0.change < 0 }.min { $0.change < $1.change }
            let rise = inside.filter { $0.change > 0 }.max { $0.change < $1.change }
            var peak: (t: Double, value: Double)?
            for (index, step) in inside.enumerated() where step.change > 0 {
                let next = index + 1 < inside.count ? inside[index + 1].change : -1
                if next <= 0, step.to.value > (peak?.value ?? -.infinity) { peak = step.to }
            }
            var row: [String: JSONValue] = [
                "label": .string(section.label), "start": .number(rounded(section.start)), "end": .number(rounded(section.end)),
                "startRetention": start.map { .number(rounded($0)) } ?? .null,
                "endRetention": end.map { .number(rounded($0)) } ?? .null,
                "change": start.flatMap { first in end.map { .number(rounded($0 - first)) } } ?? .null,
                "drop": fall.map { step in
                    .object([
                        "at": .number(rounded(step.to.t)), "change": .number(rounded(step.change)), "words": near(step.to.t),
                    ])
                } ?? .null,
                "lift": rise.map { step in .object(["at": .number(rounded(step.to.t)), "change": .number(rounded(step.change))]) }
                    ?? .null,
                "replayPeak": peak.map { .object(["at": .number(rounded($0.t)), "retention": .number(rounded($0.value))]) }
                    ?? .null,
            ]
            row["viewsAtStart"] = views.flatMap { views in start.map { .number((views * $0 / scale).rounded()) } } ?? .null
            return .object(row)
        }
        let drops = steps.filter { $0.change < 0 }.sorted { $0.change < $1.change }.prefix(max(0, top)).map { step in
            JSONValue.object([
                "at": .number(rounded(step.to.t)), "from": .number(rounded(step.from.value)), "to": .number(rounded(step.to.value)),
                "change": .number(rounded(step.change)),
                "section": spans.first { $0.start <= step.from.t && step.from.t < $0.end }.map { .string($0.label) } ?? .null,
                "words": near(step.to.t),
            ])
        }
        return .object([
            "export": .string(record.export), "platform": record.platform.map(JSONValue.string) ?? .null,
            "unit": .string(record.unit), "points": .integer(record.curve.count), "totals": .object(record.totals),
            "views": views.map(JSONValue.number) ?? .null, "sections": .array(sectionRows), "drops": .array(Array(drops)),
            "window": .number(window),
        ])
    }

    /// The curve at `time`, linear between points; nil outside the curve.
    static func value(at time: Double, in points: [(t: Double, value: Double)]) -> Double? {
        guard let first = points.first, let last = points.last, time >= first.t, time <= last.t else { return nil }
        guard let after = points.firstIndex(where: { $0.t >= time }) else { return last.value }
        let right = points[after]
        guard after > 0, right.t > time else { return right.value }
        let left = points[after - 1]
        return left.value + (right.value - left.value) * (time - left.t) / (right.t - left.t)
    }

    static func rounded(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }
}
