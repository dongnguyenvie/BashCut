import Foundation

/// A structured licence (P2-H8) for media and library items: `{id, version?, text?, url?, attribution?}`. Older items
/// keep `license` as free text; `init(json:)` reads both, mapping the text to an `id` and keeping it as `text`.
/// What the licence allows (`facts`) follows from `id` and is never stored, so it cannot drift from it.
public struct LicenseTerms: Sendable, Equatable {
    public enum Identifier: String, Sendable, CaseIterable {
        case cc0
        case publicDomain = "public-domain"
        case ccBy = "cc-by"
        case ccBySa = "cc-by-sa"
        case ccByNd = "cc-by-nd"
        case ccByNc = "cc-by-nc"
        case ccByNcSa = "cc-by-nc-sa"
        case ccByNcNd = "cc-by-nc-nd"
        /// Stock-site licences (Pexels, Pixabay, Unsplash, Mixkit…): use freely, but not resell or redistribute as is.
        case royaltyFree = "royalty-free"
        /// Made by the user or their team.
        case own
        case allRightsReserved = "all-rights-reserved"
        /// Text that maps to none of the above; `text` keeps it.
        case custom
        case unknown
    }

    /// What a licence allows; nil when it depends on terms BashCut cannot read (custom, unknown).
    public struct Facts: Sendable, Equatable {
        public let commercial: Bool?
        public let redistribute: Bool?
        public let attributionRequired: Bool?
        public let shareAlike: Bool?

        public var json: JSONValue {
            .object([
                "commercial": commercial.map(JSONValue.bool) ?? .null,
                "redistribute": redistribute.map(JSONValue.bool) ?? .null,
                "attributionRequired": attributionRequired.map(JSONValue.bool) ?? .null,
                "shareAlike": shareAlike.map(JSONValue.bool) ?? .null,
            ])
        }
    }

    public var id: Identifier
    public var version: String?
    /// The licence as it was written, when it came from free text.
    public var text: String?
    public var url: String?
    /// The credit line the licence asks for ("Photo by A on Pexels").
    public var attribution: String?

    public init(id: Identifier, version: String? = nil, text: String? = nil, url: String? = nil, attribution: String? = nil) {
        self.id = id
        self.version = version
        self.text = text
        self.url = url
        self.attribution = attribution
    }

    /// A stored `license`: free text (mapped) or an object; nil for anything else.
    public init?(json: JSONValue) {
        if let text = json.string {
            self = Self.parse(text)
            return
        }
        guard case .object(let fields) = json, let raw = fields["id"]?.string, let id = Identifier(rawValue: raw) else { return nil }
        self.init(
            id: id, version: fields["version"]?.string, text: fields["text"]?.string, url: fields["url"]?.string,
            attribution: fields["attribution"]?.string)
    }

    public var json: JSONValue {
        var fields: [String: JSONValue] = ["id": .string(id.rawValue)]
        if let version { fields["version"] = .string(version) }
        if let text { fields["text"] = .string(text) }
        if let url { fields["url"] = .string(url) }
        if let attribution { fields["attribution"] = .string(attribution) }
        return .object(fields)
    }

    /// How to show it: the text it was written as, or its ID and version ("CC-BY 4.0").
    public var displayName: String {
        if let text { return text }
        let name = [.ccBy, .ccBySa, .ccByNd, .ccByNc, .ccByNcSa, .ccByNcNd, .cc0].contains(id) ? id.rawValue.uppercased() : id.rawValue
        return version.map { "\(name) \($0)" } ?? name
    }

    /// The stored object plus `facts`, as commands report it.
    public var reportJSON: JSONValue {
        var fields = json.object
        fields["facts"] = facts.json
        return .object(fields)
    }

    public var facts: Facts {
        switch id {
        case .cc0, .publicDomain: Facts(commercial: true, redistribute: true, attributionRequired: false, shareAlike: false)
        case .ccBy, .ccByNd: Facts(commercial: true, redistribute: true, attributionRequired: true, shareAlike: false)
        case .ccBySa: Facts(commercial: true, redistribute: true, attributionRequired: true, shareAlike: true)
        case .ccByNc, .ccByNcNd: Facts(commercial: false, redistribute: true, attributionRequired: true, shareAlike: false)
        case .ccByNcSa: Facts(commercial: false, redistribute: true, attributionRequired: true, shareAlike: true)
        case .royaltyFree: Facts(commercial: true, redistribute: false, attributionRequired: false, shareAlike: false)
        case .own: Facts(commercial: true, redistribute: true, attributionRequired: false, shareAlike: false)
        case .allRightsReserved: Facts(commercial: false, redistribute: false, attributionRequired: nil, shareAlike: nil)
        case .custom, .unknown: Facts(commercial: nil, redistribute: nil, attributionRequired: nil, shareAlike: nil)
        }
    }

    /// Maps free licence text: Creative Commons names and short forms (with their version), public domain,
    /// stock-site licences, "own" and "all rights reserved". Anything else is `custom` with the text kept.
    public static func parse(_ text: String) -> LicenseTerms {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return LicenseTerms(id: .unknown) }
        var words = " " + trimmed.lowercased()
            .replacingOccurrences(of: "licence", with: "license")
            .replacingOccurrences(of: "creative commons", with: "cc")
            .replacingOccurrences(of: "attribution", with: "by")
            .replacingOccurrences(of: "non-commercial", with: "nc").replacingOccurrences(of: "noncommercial", with: "nc")
            .replacingOccurrences(of: "share-alike", with: "sa").replacingOccurrences(of: "sharealike", with: "sa")
            .replacingOccurrences(of: "no-derivatives", with: "nd").replacingOccurrences(of: "noderivatives", with: "nd")
            .replacingOccurrences(of: "noderivs", with: "nd")
            .replacingOccurrences(of: "_", with: " ") + " "
        for separator in ["-", "/", ",", "(", ")"] { words = words.replacingOccurrences(of: separator, with: " ") }
        // The version is the number after the name: "CC0 1.0" is 1.0, "CC0" has none.
        let unnamed = trimmed.replacingOccurrences(of: #"cc[\s-]?0"#, with: "", options: [.regularExpression, .caseInsensitive])
        let version = unnamed.range(of: #"\d+(\.\d+)?"#, options: .regularExpression).map { String(unnamed[$0]) }
        guard let id = identify(words) else { return LicenseTerms(id: .custom, text: trimmed) }
        let versioned: Set<Identifier> = [.cc0, .ccBy, .ccBySa, .ccByNd, .ccByNc, .ccByNcSa, .ccByNcNd]
        return LicenseTerms(id: id, version: versioned.contains(id) ? version : nil, text: trimmed)
    }

    /// The licence `words` (lowercased, separators as spaces, padded with spaces) name; nil when none.
    private static func identify(_ words: String) -> Identifier? {
        let has = { (word: String) in words.contains(" \(word) ") }
        if has("cc0") || has("cc 0") || words.contains("cc zero") || words.contains("public domain dedication") {
            return .cc0
        }
        if words.contains("public domain") || has("pd") || has("pdm") { return .publicDomain }
        if has("cc by") || (has("cc") && has("by")) || (has("by") && (has("nc") || has("sa") || has("nd"))) {
            return creativeCommons(nonCommercial: has("nc"), shareAlike: has("sa"), noDerivatives: has("nd"))
        }
        if words.contains("royalty free") || ["pexels", "pixabay", "unsplash", "mixkit"].contains(where: has) {
            return .royaltyFree
        }
        if ["own", "mine", "original", "self made", "self"].contains(where: has) { return .own }
        if words.contains("all rights reserved") || has("copyright") || words.contains("©") { return .allRightsReserved }
        return nil
    }

    private static func creativeCommons(nonCommercial: Bool, shareAlike: Bool, noDerivatives: Bool) -> Identifier {
        switch (nonCommercial, shareAlike, noDerivatives) {
        case (true, true, _): .ccByNcSa
        case (true, _, true): .ccByNcNd
        case (true, _, _): .ccByNc
        case (_, true, _): .ccBySa
        case (_, _, true): .ccByNd
        default: .ccBy
        }
    }

    /// Rejects a `license` that is neither text nor a known object.
    public static func validate(_ value: JSONValue, label: String) throws {
        if let text = value.string {
            guard text.count <= 1_000 else { throw ProjectError.invalid("\(label): license must be at most 1000 characters") }
            return
        }
        guard let terms = LicenseTerms(json: value) else {
            throw ProjectError.invalid(
                "\(label): license must be text or {id, version?, text?, url?, attribution?} with id one of "
                    + Identifier.allCases.map(\.rawValue).joined(separator: ", "))
        }
        for (key, text) in [("text", terms.text), ("url", terms.url), ("attribution", terms.attribution)] {
            if let text, text.count > 1_000 { throw ProjectError.invalid("\(label): license.\(key) is too long") }
        }
    }
}

/// Where a media file or library item came from (P2-H8): `{origin, sourceUrl?, author?, provider?, model?, prompt?,
/// seed?, requestId?, charged?, parentMedia?}` plus provider fields (`plugin`, `version`, `capability`). Unknown
/// fields round-trip.
public enum Provenance {
    public static let origins = ["stock", "ai", "own", "built-in"]
    static let textFields: [String: Int] = [
        "sourceUrl": 2_000, "author": 200, "provider": 200, "plugin": 200, "version": 80, "capability": 80,
        "model": 200, "prompt": 4_000, "requestId": 200, "parentMedia": 200, "libraryItem": 200,
    ]

    public static func validate(_ value: JSONValue, label: String) throws {
        guard case .object(let fields) = value else { throw ProjectError.invalid("\(label): provenance must be an object") }
        if let origin = fields["origin"] {
            guard let text = origin.string, origins.contains(text) else {
                throw ProjectError.invalid("\(label): provenance.origin must be one of \(origins.joined(separator: ", "))")
            }
        }
        for (key, limit) in textFields {
            guard let field = fields[key] else { continue }
            guard let text = field.string, text.count <= limit else {
                throw ProjectError.invalid("\(label): provenance.\(key) must be text of at most \(limit) characters")
            }
        }
        if let seed = fields["seed"], seed.int == nil, seed.string == nil {
            throw ProjectError.invalid("\(label): provenance.seed must be a number or text")
        }
        if let charged = fields["charged"] {
            guard let amount = charged.double, amount.isFinite, amount >= 0 else {
                throw ProjectError.invalid("\(label): provenance.charged must be US dollars from 0 up")
            }
        }
    }

    /// The provenance `media import` and `library add` record from their options: only the fields given.
    public static func from(
        origin: String?, sourceUrl: String?, author: String?, extra: [String: JSONValue] = [:]
    ) -> JSONValue? {
        var fields = extra
        if let origin { fields["origin"] = .string(origin) }
        if let sourceUrl { fields["sourceUrl"] = .string(sourceUrl) }
        if let author { fields["author"] = .string(author) }
        return fields.isEmpty ? nil : .object(fields)
    }
}
