import Foundation

/// Platform facts as data (P1-F1, #469): each field is `{value, kind, source, checked, confidence}` so an agent can
/// read where a number comes from and how sure it is; `kind` separates hard limits (an upload fails or the format
/// changes) from recommended values and plain information. The table ships with BashCut (`builtIn`); a plugin may
/// ship a newer one (`contributes.platforms`), and a project's `review.platform` still overrides the zones and length.
public struct PlatformFact: Sendable, Equatable {
    public enum Kind: String, Sendable { case hard, recommended, info }

    public let value: JSONValue
    public let kind: Kind
    public let source: String
    /// When the value was last checked (`YYYY-MM`).
    public let checked: String
    /// official (the platform says so), measured (screenshots measured), consensus (several tools agree) or unverified.
    public let confidence: String

    public var json: JSONValue {
        .object([
            "value": value, "kind": .string(kind.rawValue), "source": .string(source), "checked": .string(checked),
            "confidence": .string(confidence),
        ])
    }
}

public struct PlatformTable: Sendable, Equatable {
    public struct Record: Sendable, Equatable {
        public let id: String
        public let title: String
        public let vertical: Bool
        public let fields: [String: PlatformFact]

        public func number(_ key: String) -> Double? { fields[key]?.value.double }
    }

    /// `YYYY-MM-DD`; a newer table replaces an older one.
    public let version: String
    /// `built-in` or the plugin that shipped it.
    public let origin: String
    public let platforms: [Record]

    public static let confidences = ["official", "measured", "consensus", "unverified"]
    /// Fields every platform must give, for the checks that read them.
    public static let requiredFields = [
        "maxSeconds", "targetLUFS", "maxTruePeakDbTP", "safeArea.top", "safeArea.bottom", "safeArea.sideWidth",
        "safeArea.sideHeight", "safeArea.margin",
    ]

    /// Parses and checks a table: every platform has the required numeric fields, every field its provenance.
    public init(json: JSONValue, origin: String) throws {
        guard let version = json.object["version"]?.string, version.count == 10,
            case .array(let list)? = json.object["platforms"], !list.isEmpty, list.count <= 100
        else { throw ProjectError.invalid("platforms: expected {version: YYYY-MM-DD, platforms: [...]}") }
        self.version = version
        self.origin = origin
        platforms = try list.map { entry in
            let fields = entry.object
            guard let id = fields["id"]?.string, !id.isEmpty, let title = fields["title"]?.string,
                let vertical = fields["vertical"]?.bool, case .object(let raw)? = fields["fields"]
            else { throw ProjectError.invalid("platforms: each needs id, title, vertical and fields") }
            let facts = try raw.mapValues { value -> PlatformFact in
                let fact = value.object
                guard let kind = fact["kind"]?.string.flatMap(PlatformFact.Kind.init(rawValue:)),
                    let source = fact["source"]?.string, !source.isEmpty, let checked = fact["checked"]?.string,
                    let confidence = fact["confidence"]?.string, Self.confidences.contains(confidence),
                    let value = fact["value"]
                else { throw ProjectError.invalid("platforms.\(id): each field needs value, kind, source, checked, confidence") }
                return PlatformFact(value: value, kind: kind, source: source, checked: checked, confidence: confidence)
            }
            if let missing = Self.requiredFields.first(where: { key in
                facts[key].map { $0.value == .null ? key != "maxSeconds" : $0.value.double == nil } ?? true
            }) {
                throw ProjectError.invalid("platforms.\(id): \(missing) must be a number")
            }
            return Record(id: id, title: title, vertical: vertical, fields: facts)
        }
        guard Set(platforms.map(\.id)).count == platforms.count else { throw ProjectError.invalid("platforms: IDs must be unique") }
    }

    public var json: JSONValue {
        .object(["version": .string(version), "origin": .string(origin), "platforms": .array(platforms.map { record in
            .object([
                "id": .string(record.id), "title": .string(record.title), "vertical": .bool(record.vertical),
                "fields": .object(record.fields.mapValues(\.json)),
            ])
        })])
    }
}

/// The table in use: the built-in one, or a newer one a plugin installed.
public enum PlatformData {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var installed: PlatformTable?

    // swiftlint:disable:next force_try
    public static let builtIn = try! PlatformTable(json: try! JSONValue(parsing: Data(builtInJSON.utf8)), origin: "built-in")

    public static var current: PlatformTable {
        lock.lock()
        defer { lock.unlock() }
        return installed ?? builtIn
    }

    /// Whether `table` would replace the built-in one: only a newer version does.
    public static func accepts(_ table: PlatformTable) -> Bool { table.version > builtIn.version }

    /// Uses `table` while it is newer than the built-in one; nil goes back to the built-in table. Returns whether it
    /// is in use.
    @discardableResult
    public static func install(_ table: PlatformTable?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let table, accepts(table) else {
            installed = nil
            return false
        }
        installed = table
        return true
    }
}
