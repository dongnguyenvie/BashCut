import Foundation

/// Claims without a source (P3-I5): numbers, prices, superlatives and names in on-screen text (titles, not captions:
/// those are what was said on camera) and in the voiceover script (`plan.cut.voiceover`) that no entry of the claims
/// ledger (`knowledge set-claim`) covers. Info only: the words are listed, nothing is judged true or false.
public enum ClaimScan {
    public struct Found: Sendable, Equatable {
        public var numbers: [String] = []
        public var prices: [String] = []
        public var superlatives: [String] = []
        public var names: [String] = []

        public var isEmpty: Bool { numbers.isEmpty && prices.isEmpty && superlatives.isEmpty && names.isEmpty }
        var all: [String] { prices + numbers + superlatives + names }

        public var json: JSONValue {
            var fields: [String: JSONValue] = [:]
            for (key, list) in [("numbers", numbers), ("prices", prices), ("superlatives", superlatives), ("names", names)]
            where !list.isEmpty { fields[key] = .array(list.map(JSONValue.string)) }
            return .object(fields)
        }
    }

    static let currencyWords: Set<String> = ["đ", "₫", "vnd", "vnđ", "đồng", "usd", "eur", "dollars", "dollar", "euro", "euros", "k"]
    static let currencySigns: Set<Character> = ["$", "€", "£", "¥", "₫"]
    static let superlativeWords: Set<String> = [
        "best", "worst", "most", "least", "greatest", "biggest", "largest", "smallest", "cheapest", "fastest", "highest",
        "lowest", "newest", "oldest", "longest", "shortest", "strongest", "easiest", "only", "#1", "nhất",
    ]

    /// What in `text` reads as a checkable claim.
    public static func scan(_ text: String) -> Found {
        var found = Found()
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let words = tokens.map { $0.trimmingCharacters(in: .punctuationCharacters.subtracting(["#", "%", "$"])) }
        let letters = words.filter { $0.first?.isLetter == true }
        // Title Case or capitals throughout say nothing about names.
        let capitalized = letters.filter { $0.first?.isUppercase == true }.count
        let namesReadable = !letters.isEmpty && Double(capitalized) / Double(letters.count) < 0.5
        var sentenceStart = true
        for (index, token) in tokens.enumerated() {
            let word = words[index]
            let lower = word.lowercased()
            defer { sentenceStart = token.last.map { ".!?:".contains($0) } ?? false }
            guard !word.isEmpty else { continue }
            if word.contains(where: \.isNumber) {
                let next = index + 1 < words.count ? words[index + 1].lowercased() : ""
                let price = token.contains(where: { currencySigns.contains($0) }) || currencyWords.contains(next)
                    || ["k", "đ", "₫", "usd", "vnd"].contains { lower.hasSuffix($0) && lower.dropLast($0.count).contains(where: \.isNumber) }
                if price {
                    found.prices.append(currencyWords.contains(next) ? word + " " + words[index + 1] : word)
                } else {
                    found.numbers.append(word)
                }
            } else if superlativeWords.contains(lower) {
                let previous = index > 0 ? words[index - 1] + " " : ""
                found.superlatives.append(lower == "nhất" ? previous + word : word)
            } else if namesReadable, !sentenceStart, index > 0, word.first?.isUppercase == true, word.count > 1 {
                found.names.append(word)
            }
        }
        return found
    }

    /// `found` without what a claim's text covers (case and punctuation aside).
    public static func unsourced(_ found: Found, claims: [String]) -> Found {
        let covered = claims.map(normalized).joined(separator: " | ")
        let keep = { (fragment: String) in !covered.contains(normalized(fragment)) }
        return Found(
            numbers: found.numbers.filter(keep), prices: found.prices.filter(keep),
            superlatives: found.superlatives.filter(keep), names: found.names.filter(keep))
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters.subtracting(["#", "%", "$"])) }
            .joined(separator: " ")
    }
}

extension TimelineReview {
    static func claimIssues(_ project: Project, claims: [String]) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        let titles = project.tracks.filter { $0.kind == TrackKind.text && $0.role != TrackRole.captions }.flatMap(\.items)
            .sorted { $0.at < $1.at }
        for item in titles {
            let found = ClaimScan.unsourced(ClaimScan.scan(item.text), claims: claims)
            guard !found.isEmpty else { continue }
            issues.append(issue("unsourced-claim-" + item.id, found, frame: item.at, where: "on-screen text"))
        }
        let lines = project["plan"]?.object["cut"]?.object["voiceover"]?.array.map(\.object) ?? []
        for (index, line) in lines.enumerated() {
            guard let text = line["text"]?.string else { continue }
            let found = ClaimScan.unsourced(ClaimScan.scan(text), claims: claims)
            guard !found.isEmpty else { continue }
            let id = line["id"]?.string ?? "\(index + 1)"
            issues.append(issue("unsourced-claim-vo-" + id, found, frame: 0, where: "voiceover line \(id)"))
        }
        return issues
    }

    private static func issue(_ id: String, _ found: ClaimScan.Found, frame: Int, where place: String) -> ReviewIssue {
        ReviewIssue(
            id: id, title: "Claims without a source",
            detail: "\(place.prefix(1).uppercased() + place.dropFirst()) states \(found.all.joined(separator: ", ")) with no "
                + "source in the claims ledger.",
            frame: frame, severity: .info,
            fix: ReviewFix(command: "knowledge.set-claim", hint: "Record each with its source (URL, frame or user)."),
            kind: "unsourced-claim", facts: found.json.object)
    }
}
