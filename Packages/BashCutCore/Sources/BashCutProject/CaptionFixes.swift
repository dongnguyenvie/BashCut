import Foundation

/// Find and replace in captions (`captions replace`, P2-C3): the text of every caption on the caption layers, with
/// its word timings kept when the replacement leaves the word count as it was. `captions style` is below.
public struct CaptionReplace: Sendable, Equatable {
    public struct Change: Sendable, Equatable {
        public let item: String
        public let before: String
        public let after: String
        public let count: Int
        /// The words no longer match their timings one for one, so `words` was dropped and the timings are
        /// estimated from word length (`Item.wordTimings`).
        public let retimed: Bool
    }

    public var find: String
    public var replacement: String
    public var matchCase: Bool
    /// Only matches with no letter or digit right before or after them.
    public var wholeWord: Bool

    public init(find: String, replacement: String, matchCase: Bool = false, wholeWord: Bool = true) {
        self.find = find
        self.replacement = replacement
        self.matchCase = matchCase
        self.wholeWord = wholeWord
    }

    func expression() throws -> NSRegularExpression {
        guard !find.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectError.invalid("Give the text to find")
        }
        var pattern = NSRegularExpression.escapedPattern(for: find)
        if wholeWord { pattern = "(?<![\\p{L}\\p{N}])" + pattern + "(?![\\p{L}\\p{N}])" }
        return try NSRegularExpression(pattern: pattern, options: matchCase ? [] : [.caseInsensitive])
    }

    /// `text` with every match replaced, and how many there were.
    public func apply(to text: String) throws -> (text: String, count: Int) {
        let expression = try expression()
        let range = NSRange(text.startIndex..., in: text)
        let count = expression.numberOfMatches(in: text, range: range)
        guard count > 0 else { return (text, 0) }
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        return (expression.stringByReplacingMatches(in: text, range: range, withTemplate: template), count)
    }

    /// The patch for `item` and what changed; nil when the text has no match.
    public func patch(for item: Item) throws -> (patch: [String: JSONValue], change: Change)? {
        let before = item.text
        let (after, count) = try apply(to: before)
        guard count > 0, after != before else { return nil }
        var patch: [String: JSONValue] = ["text": .string(after)]
        var retimed = false
        if case .array(let words)? = item.fields["words"] {
            let oldTokens = CaptionWords.tokens(before), newTokens = CaptionWords.tokens(after)
            if words.count == oldTokens.count, newTokens.count == oldTokens.count {
                patch["words"] = .array(zip(words, newTokens).map { word, token in
                    var entry = word.object
                    entry["text"] = .string(token)
                    return .object(entry)
                })
            } else {
                patch["words"] = .null
                retimed = true
            }
        }
        return (patch, Change(item: item.id, before: before, after: after, count: count, retimed: retimed))
    }
}

extension Project {
    /// Text items on caption layers, in timeline order.
    public var captionItems: [Item] {
        tracks.filter { $0.kind == TrackKind.text && $0.role == TrackRole.captions }.flatMap(\.items)
            .sorted { $0.at < $1.at }
    }

    /// One `setProperties` per caption `replace` changes, and the changes.
    public func captionReplaceOperations(_ replace: CaptionReplace) throws -> (ops: [EditOperation], changes: [CaptionReplace.Change]) {
        var operations: [EditOperation] = []
        var changes: [CaptionReplace.Change] = []
        for item in captionItems {
            guard let (patch, change) = try replace.patch(for: item) else { continue }
            operations.append(.setProperties(item: item.id, patch: patch))
            changes.append(change)
        }
        return (operations, changes)
    }
}

extension Project {
    /// The textStyle fields `captions style` takes: the declared ones and `lines`.
    public static let captionStyleFields = Set(ItemProperty.all.filter { $0.group == "textStyle" }.map(\.key))
        .union(["lines"])

    /// One `setProperties` per caption restyling it (`captions style`): `preset` first (as `library apply`), then
    /// `style` merged into its textStyle (null removes a field), then `wordStyle` (null: words all at once).
    public func captionStyleOperations(
        preset: LibraryTextPreset? = nil, style: [String: JSONValue]? = nil, wordStyle: JSONValue? = nil
    ) throws -> [EditOperation] {
        guard preset != nil || style != nil || wordStyle != nil else {
            throw ProjectError.invalid("Give a preset, a style or a wordStyle")
        }
        if let unknown = style?.keys.sorted().first(where: { !Self.captionStyleFields.contains($0) }) {
            throw ProjectError.invalid(
                "\(unknown) is not a textStyle field; use \(Self.captionStyleFields.sorted().joined(separator: ", "))")
        }
        if let wordStyle, wordStyle != .null, !(wordStyle.string.map(CaptionWords.styles.contains) ?? false) {
            throw ProjectError.invalid("Word style must be one of \(CaptionWords.styles.joined(separator: ", ")) or none")
        }
        let targets = captionItems
        guard !targets.isEmpty else { throw ProjectError.invalid("There are no captions to change") }
        return try targets.map { item in
            var patch = try preset?.patch(for: item, project: self) ?? [:]
            if let style {
                patch["textStyle"] = ItemPatch.merge(patch["textStyle"] ?? item["textStyle"] ?? .object([:]), .object(style))
            }
            if let wordStyle { patch["wordStyle"] = wordStyle }
            return .setProperties(item: item.id, patch: patch)
        }
    }
}
