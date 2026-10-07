import Foundation

/// A licence (P2-H8) for media and library items: free text, or an object `{id?, version?, text?, url?, attribution?,
/// commercial?, redistribute?, attributionRequired?, shareAlike?, …}` with an open `id` (such as cc-by,
/// royalty-free, own). BashCut never parses or interprets it: what the licence allows is what the agent or the user
/// recorded on the item itself. Unknown fields round-trip.
public struct LicenseTerms: Sendable, Equatable {
    /// What the item says the licence allows; nil when not recorded.
    public struct Facts: Sendable, Equatable {
        public let commercial: Bool?
        public let redistribute: Bool?
        public let attributionRequired: Bool?
        public let shareAlike: Bool?
    }

    public var fields: [String: JSONValue]

    public init(fields: [String: JSONValue]) { self.fields = fields }

    /// A stored `license`: free text (kept as `text`) or an object; nil for anything else.
    public init?(json: JSONValue) {
        switch json {
        case .string(let text): fields = ["text": .string(text)]
        case .object(let object): fields = object
        default: return nil
        }
    }

    public var id: String? { fields["id"]?.string }
    public var version: String? { fields["version"]?.string }
    public var text: String? { fields["text"]?.string }
    public var url: String? { fields["url"]?.string }
    public var attribution: String? { fields["attribution"]?.string }

    public var facts: Facts {
        Facts(commercial: fields["commercial"]?.bool, redistribute: fields["redistribute"]?.bool,
              attributionRequired: fields["attributionRequired"]?.bool, shareAlike: fields["shareAlike"]?.bool)
    }

    public var json: JSONValue { .object(fields) }

    /// How to show it: the text it was written as, or its ID and version.
    public var displayName: String {
        if let text { return text }
        let name = id ?? "licence"
        return version.map { "\(name) \($0)" } ?? name
    }

    /// A `--license` option: a JSON object when it reads as one, else the text as written.
    public static func argument(_ text: String) -> JSONValue {
        if text.hasPrefix("{"), let data = text.data(using: .utf8),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data), case .object = value
        {
            return value
        }
        return .string(text)
    }

    /// Rejects a `license` that is neither text nor an object, or whose text fields are not text up to 1000
    /// characters, or whose facts are not booleans.
    public static func validate(_ value: JSONValue, label: String) throws {
        if let text = value.string {
            guard text.count <= 1_000 else { throw ProjectError.invalid("\(label): license must be at most 1000 characters") }
            return
        }
        guard let terms = LicenseTerms(json: value) else {
            throw ProjectError.invalid("\(label): license must be text or an object")
        }
        for key in ["id", "version", "text", "url", "attribution"] {
            guard let field = terms.fields[key] else { continue }
            guard let text = field.string, text.count <= 1_000 else {
                throw ProjectError.invalid("\(label): license.\(key) must be text of at most 1000 characters")
            }
        }
        for key in ["commercial", "redistribute", "attributionRequired", "shareAlike"] {
            if let field = terms.fields[key], field.bool == nil {
                throw ProjectError.invalid("\(label): license.\(key) must be true or false")
            }
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
