import Foundation

/// Text a plugin shows to people, in one or more languages: `"Auto Grade"` or
/// `{"en": "Auto Grade", "vi": "Tự chỉnh màu"}`. A plain string is English. Keys are language codes
/// (`en`, `vi`, `pt-BR`); `en` is required when more than one language is given.
public struct LocalizedText: Codable, Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let values: [String: String]

    public init(_ values: [String: String]) { self.values = values }
    public init(stringLiteral value: String) { values = ["en": value] }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            values = ["en": text]
        } else {
            values = try container.decode([String: String].self)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if values.count == 1, let english = values["en"] { try container.encode(english) } else { try container.encode(values) }
    }

    /// The app's interface language, which plugin text follows.
    public static var preferredLanguage: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// The text for `language` (`pt-BR` falls back to `pt`), then English, then any language.
    public func text(for language: String) -> String {
        let base = String(language.split(separator: "-").first ?? "")
        return values[language] ?? values[base] ?? values["en"] ?? values.keys.sorted().first.flatMap { values[$0] } ?? ""
    }

    /// The text in the app's interface language.
    public var text: String { text(for: Self.preferredLanguage) }
    public var description: String { text(for: "en") }

    /// Every value is nonempty and at most `limit` characters, and several languages include English.
    func isValid(limit: Int) -> Bool {
        !values.isEmpty && (values.count == 1 || values["en"] != nil)
            && values.keys.allSatisfy { $0.range(of: "^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$", options: .regularExpression) != nil }
            && values.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= limit }
    }
}
