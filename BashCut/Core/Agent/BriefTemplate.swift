import BashCutProject
import Foundation

/// What the open project looks like, for choosing which brief templates fit (the dock's quick starts, the fit badge in
/// the New brief sheet and the order of the composer's template menu).
public enum BriefFit: String, CaseIterable, Sendable {
    /// No project, or a project with nothing in it yet.
    case none
    /// Media imported, nothing on the timeline.
    case footage
    /// One long speech clip (a podcast, talk or livestream) and at most that clip on the timeline.
    case talk
    /// Items on the timeline.
    case timeline
    /// Timeline items selected.
    case selection

    /// A video or audio file in the project, as the fit rule sees it.
    public struct Media: Sendable, Equatable {
        public let seconds: Double
        public let hasSpeech: Bool
        public init(seconds: Double, hasSpeech: Bool) {
            self.seconds = seconds
            self.hasSpeech = hasSpeech
        }
    }

    /// A clip this long with speech makes the project a long talk.
    public static let talkSeconds: Double = 600

    /// The project state from what the document knows: whether a project is open, its video and audio media,
    /// how many items the timeline has and how many are selected.
    public static func state(hasProject: Bool, media: [Media], timelineItems: Int, selected: Int) -> BriefFit {
        guard hasProject else { return .none }
        if selected > 0, timelineItems > 0 { return .selection }
        let talks = media.filter { $0.hasSpeech && $0.seconds >= talkSeconds }
        if talks.count == 1, timelineItems <= 1 { return .talk }
        if timelineItems > 0 { return .timeline }
        return media.isEmpty ? .none : .footage
    }
}

/// The three sections of the template list.
public enum BriefGroup: String, CaseIterable, Sendable {
    case make, fix, finish

    public var titleKey: String {
        switch self {
        case .make: "Make a video"
        case .fix: "Fix the edit"
        case .finish: "Finish"
        }
    }

    public var title: String { BriefText.localized(titleKey) }
}

/// One blank in a template: free text with a default, or chips with a default choice. Chips also take a value the
/// user types ("other…").
public struct BriefField: Sendable, Identifiable {
    public enum Kind: Sendable {
        case text(defaultKey: String)
        case chips(optionKeys: [String], defaultIndex: Int)
    }

    /// The name used in the template's pattern: `{length}`.
    public let id: String
    public let labelKey: String
    public let kind: Kind

    public static func text(_ id: String, _ label: String, _ defaultValue: String = "") -> BriefField {
        BriefField(id: id, labelKey: label, kind: .text(defaultKey: defaultValue))
    }

    public static func chips(_ id: String, _ label: String, _ options: [String], _ defaultIndex: Int = 0) -> BriefField {
        BriefField(id: id, labelKey: label, kind: .chips(optionKeys: options, defaultIndex: defaultIndex))
    }

    public var label: String { BriefText.localized(labelKey) }

    /// The chip choices in the interface language; empty for a text field.
    public var options: [String] {
        if case .chips(let keys, _) = kind { return keys.map(BriefText.localized) }
        return []
    }

    public var isText: Bool {
        if case .text = kind { return true }
        return false
    }

    /// The value a fresh brief starts with; empty for a text field without a default.
    public var defaultValue: String {
        switch kind {
        case .text(let key): key.isEmpty ? "" : BriefText.localized(key)
        case .chips(let keys, let index): BriefText.localized(keys[min(max(index, 0), keys.count - 1)])
        }
    }

    /// What an empty field shows in the request: `‹topic›`, selected after it is inserted so typing replaces it.
    public var hole: String { "‹" + label.lowercased() + "›" }

    /// Every source string of the field, for the localization check.
    var sourceKeys: [String] {
        switch kind {
        case .text(let key): [labelKey, key].filter { !$0.isEmpty }
        case .chips(let keys, _): [labelKey] + keys
        }
    }
}

/// A starting point for a brief: what to make or fix, the recipe skill it maps to, the project states it fits, and a
/// request pattern with `{field}` blanks.
public struct BriefTemplate: Sendable, Identifiable {
    public let id: String
    public let group: BriefGroup
    public let systemImage: String
    public let titleKey: String
    public let detailKey: String
    /// The agent kit recipe (skill) this request belongs to.
    public let recipe: String
    public let fits: Set<BriefFit>
    public let fields: [BriefField]
    public let patternKey: String

    public init(
        id: String, group: BriefGroup, systemImage: String, titleKey: String, detailKey: String, recipe: String,
        fits: Set<BriefFit>, fields: [BriefField], patternKey: String
    ) {
        self.id = id
        self.group = group
        self.systemImage = systemImage
        self.titleKey = titleKey
        self.detailKey = detailKey
        self.recipe = recipe
        self.fits = fits
        self.fields = fields
        self.patternKey = patternKey
    }

    public var title: String { BriefText.localized(titleKey) }
    public var detail: String { BriefText.localized(detailKey) }
    public var pattern: String { BriefText.localized(patternKey) }

    /// Fits the project; a template for the whole timeline also fits a selection.
    public func fits(_ state: BriefFit) -> Bool {
        fits.contains(state) || (state == .selection && fits.contains(.timeline))
    }

    /// Each field's starting value, by field ID.
    public var defaultValues: [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.defaultValue) })
    }

    /// The request with `values` (field ID → text) put in; a field without a value shows its hole (`‹topic›`).
    public func prompt(_ values: [String: String] = [:]) -> String {
        BriefText.fill(pattern, fields: fields, values: values.merging(defaultValues) { own, _ in own })
    }

    /// Every source string: title, description, field labels, defaults, chips and the pattern.
    public var sourceKeys: [String] { [titleKey, detailKey, patternKey] + fields.flatMap(\.sourceKeys) }
}

public enum BriefText {
    /// The interface-language text for an English source string in Localizable.xcstrings.
    public static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    /// Puts each field's value in its `{id}` blank, or its hole when the value is empty.
    public static func fill(_ pattern: String, fields: [BriefField], values: [String: String]) -> String {
        fields.reduce(pattern) { text, field in
            let value = (values[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.replacingOccurrences(of: "{\(field.id)}", with: value.isEmpty ? field.hole : value)
        }
    }

    /// The `{name}` blanks in a pattern.
    public static func placeholders(in pattern: String) -> [String] {
        var names: [String] = []
        var rest = pattern[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            names.append(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return names
    }

    /// The range of the first hole (`‹…›`) in `text`, so the composer can select it.
    public static func firstHole(in text: String) -> Range<String.Index>? {
        guard let open = text.firstIndex(of: "‹"), let close = text[open...].firstIndex(of: "›") else { return nil }
        return open..<text.index(after: close)
    }

    /// Lowercased, without accents, đ as d: "Dịch phụ đề" → "dich phu de", so search works without Vietnamese
    /// diacritics.
    public static func normalize(_ text: String) -> String {
        text.searchFolded
    }

    /// Whether every word of `query` is in the title or description (in the interface language or English), the ID or
    /// the recipe, ignoring case and accents.
    public static func matches(_ query: String, _ template: BriefTemplate) -> Bool {
        let words = normalize(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = normalize([template.title, template.detail, template.titleKey, template.detailKey, template.id,
                                  template.recipe].joined(separator: " "))
        return words.allSatisfy { haystack.contains($0) }
    }
}
