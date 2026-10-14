import Foundation

/// The style lock of generated illustrations (#550): one style prompt, reference pictures (a character, a style
/// sample) and a seed when the provider takes one, stored as the project's `illustration` or a brand kit's
/// `illustration`. Every `image generate` call reuses it, so the agent never repeats the style text. `disclosure` is
/// the label put on screen over generated pictures (the brand's `disclosure` otherwise). Core only stores and passes
/// it: what the words say and which model reads them are the provider's and the agent's.
public struct IllustrationLock: Sendable, Equatable {
    public static let maximumReferences = 8

    public var style: String?
    /// Pictures as project-relative or absolute paths, or sticker library references.
    public var references: [String]
    public var seed: Int?
    public var disclosure: String?

    public init(style: String? = nil, references: [String] = [], seed: Int? = nil, disclosure: String? = nil) {
        self.style = style
        self.references = references
        self.seed = seed
        self.disclosure = disclosure
    }

    /// Reads and checks a stored lock.
    public init(_ value: JSONValue, label: String = "illustration") throws {
        guard case .object(let fields) = value else { throw ProjectError.invalid("\(label): expected an object") }
        for key in fields.keys where !["style", "references", "seed", "disclosure"].contains(key) {
            throw ProjectError.invalid("\(label).\(key): unknown; use style, references, seed or disclosure")
        }
        if let style = fields["style"], style != .null {
            guard let text = style.string, (1...4_000).contains(text.count) else {
                throw ProjectError.invalid("\(label).style: expected a text of 1–4000 characters")
            }
            self.style = text
        }
        references = []
        if let list = fields["references"], list != .null {
            guard case .array(let values) = list, values.count <= Self.maximumReferences,
                values.allSatisfy({ $0.string.map { (1...1_024).contains($0.count) } ?? false })
            else {
                throw ProjectError.invalid(
                    "\(label).references: expected up to \(Self.maximumReferences) paths or sticker library ids")
            }
            references = values.compactMap(\.string)
        }
        if let seed = fields["seed"], seed != .null {
            guard let number = seed.int, (0...Int(UInt32.max)).contains(number) else {
                throw ProjectError.invalid("\(label).seed: expected an integer 0–4294967295")
            }
            self.seed = number
        }
        if let disclosure = fields["disclosure"], disclosure != .null {
            guard let text = disclosure.string, (1...200).contains(text.count) else {
                throw ProjectError.invalid("\(label).disclosure: expected a text of 1–200 characters")
            }
            self.disclosure = text
        }
    }

    public var isEmpty: Bool { style == nil && references.isEmpty && seed == nil && disclosure == nil }

    public var json: JSONValue {
        var fields: [String: JSONValue] = [:]
        if let style { fields["style"] = .string(style) }
        if !references.isEmpty { fields["references"] = .array(references.map(JSONValue.string)) }
        if let seed { fields["seed"] = .integer(seed) }
        if let disclosure { fields["disclosure"] = .string(disclosure) }
        return .object(fields)
    }
}

extension Project {
    /// The style lock in use and where it comes from: the project's `illustration`, else the applied brand's.
    public var illustration: (lock: IllustrationLock, source: String)? {
        if let value = self["illustration"], value != .null, let lock = try? IllustrationLock(value) {
            return (lock, "project")
        }
        if let value = self["brand"]?.object["illustration"], value != .null, let lock = try? IllustrationLock(value) {
            return (lock, "brand")
        }
        return nil
    }

    /// The label generated pictures carry on screen: the style lock's, else the brand's; nil when neither sets one.
    public var disclosureText: String? {
        illustration?.lock.disclosure ?? (self["brand"]?.object["disclosure"]?.string).flatMap { $0.isEmpty ? nil : $0 }
    }

    func validateIllustration() throws {
        if let value = self["illustration"], value != .null { _ = try IllustrationLock(value) }
    }
}

extension Media {
    /// Made by an `image.generate` provider (#550): review asks for the disclosure label over it.
    public var isGenerated: Bool { self["generated"] == .bool(true) }
}
