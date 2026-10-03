import Foundation

// Looks and style kits: built-in ones ship with the app; custom ones live in the project (`looks`,
// `styleKits`), so an agent or a person can add a grade once and reuse it from the Filters library and the
// commands. Saving or deleting one is a `setProjectProperties` edit, undoable like any other.

/// The color keys an item, adjustment or look may carry, with their allowed ranges; `lut` is a catalog ID.
public enum ColorGrade {
    public static let ranges: [(key: String, range: ClosedRange<Double>)] = [
        ("exposure", -10...10), ("contrast", 0...4), ("saturation", 0...4), ("lutStrength", 0...1),
    ]

    /// Checks ranges and the LUT reference; other keys round-trip. `path` names the grade in error messages.
    static func validate(_ color: [String: JSONValue], path: String, lutIDs: Set<String>) throws {
        for (key, range) in ranges {
            guard let value = color[key] else { continue }
            guard let number = value.double, number.isFinite, range.contains(number) else {
                throw ProjectError.invalid("\(path).\(key): expected a number in \(range)")
            }
        }
        if let lut = color["lut"], lut != .null, lut.string.map(lutIDs.contains) != true {
            throw ProjectError.invalid("\(path): unknown LUT")
        }
    }
}

/// The text presets the caption renderer draws (`textPreset` on a text item).
public enum TextPreset {
    public static let all = [
        "bold-outline", "cinematic-serif", "keyword-sticker", "place-card", "hook-title", "chapter-card",
    ]
}

/// A named color grade offered in the Filters library and used by style kits.
public struct ColorLook: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let color: [String: JSONValue]
    /// Built-in titles are English UI strings to localize; custom titles are user content.
    public let isBuiltIn: Bool

    public init(id: String, title: String, color: [String: JSONValue], isBuiltIn: Bool = false) {
        self.id = id
        self.title = title
        self.color = color
        self.isBuiltIn = isBuiltIn
    }

    init(fields: [String: JSONValue]) {
        self.init(
            id: fields["id"]?.string ?? "", title: fields["title"]?.string ?? "",
            color: fields["color"]?.object ?? [:])
    }

    public var json: JSONValue {
        .object(["id": .string(id), "title": .string(title), "color": .object(color), "builtIn": .bool(isBuiltIn)])
    }

    public static let builtIn: [ColorLook] = [
        .init(id: "original", title: "Original", color: [:], isBuiltIn: true),
        .init(id: "vivid", title: "Vivid", color: ["saturation": .number(1.2), "contrast": .number(1.05)], isBuiltIn: true),
        .init(
            id: "muted-film", title: "Muted film", color: ["saturation": .number(0.8), "contrast": .number(0.9)],
            isBuiltIn: true),
        .init(id: "black-white", title: "Black & white", color: ["saturation": .integer(0)], isBuiltIn: true),
    ]
}

/// A one-shot style recipe: a full-length adjustment item with a look, plus a caption preset for every
/// caption. Applying a kit again replaces the adjustment item the previous kit added. Titles, place cards and
/// other non-caption presets keep their style.
public struct StyleKit: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let lookID: String
    public let captionPreset: String
    public let isBuiltIn: Bool

    public init(id: String, title: String, lookID: String, captionPreset: String, isBuiltIn: Bool = false) {
        self.id = id
        self.title = title
        self.lookID = lookID
        self.captionPreset = captionPreset
        self.isBuiltIn = isBuiltIn
    }

    init(fields: [String: JSONValue]) {
        self.init(
            id: fields["id"]?.string ?? "", title: fields["title"]?.string ?? "",
            lookID: fields["look"]?.string ?? "", captionPreset: fields["captionPreset"]?.string ?? "")
    }

    public var json: JSONValue {
        .object([
            "id": .string(id), "title": .string(title), "look": .string(lookID),
            "captionPreset": .string(captionPreset), "builtIn": .bool(isBuiltIn),
        ])
    }

    public static let builtIn: [StyleKit] = [
        .init(id: "food-review", title: "Food review", lookID: "vivid", captionPreset: "bold-outline", isBuiltIn: true),
        .init(id: "cinematic", title: "Cinematic", lookID: "muted-film", captionPreset: "cinematic-serif", isBuiltIn: true),
    ]
}

extension Project {
    /// Built-in looks, then the project's own.
    public var looks: [ColorLook] { ColorLook.builtIn + customLooks }
    public var customLooks: [ColorLook] { (self["looks"]?.array ?? []).map { ColorLook(fields: $0.object) } }
    /// Built-in style kits, then the project's own.
    public var styleKits: [StyleKit] { StyleKit.builtIn + customStyleKits }
    public var customStyleKits: [StyleKit] {
        (self["styleKits"]?.array ?? []).map { StyleKit(fields: $0.object) }
    }

    public func look(_ id: String) -> ColorLook? { looks.first { $0.id == id } }
    public func styleKit(_ id: String) -> StyleKit? { styleKits.first { $0.id == id } }

    /// Saves (adds or replaces) a custom look. Built-in IDs are reserved.
    public func savingLook(_ look: ColorLook) throws -> EditOperation {
        guard !ColorLook.builtIn.contains(where: { $0.id == look.id }) else {
            throw ProjectError.invalid("\(look.id) is a built-in look; choose another ID")
        }
        let entry = JSONValue.object(["id": .string(look.id), "title": .string(look.title), "color": .object(look.color)])
        return .setProjectProperties(patch: ["looks": .array(replacing(look.id, in: self["looks"], with: entry))])
    }

    /// Deletes a custom look; refused while a custom style kit uses it.
    public func deletingLook(_ id: String) throws -> EditOperation {
        guard customLooks.contains(where: { $0.id == id }) else { throw ProjectError.invalid("Unknown custom look: \(id)") }
        if let kit = customStyleKits.first(where: { $0.lookID == id }) {
            throw ProjectError.invalid("Style kit \(kit.id) uses look \(id); delete or change the kit first")
        }
        return .setProjectProperties(patch: ["looks": .array(replacing(id, in: self["looks"], with: nil))])
    }

    /// Saves (adds or replaces) a custom style kit. Built-in IDs are reserved.
    public func savingStyleKit(_ kit: StyleKit) throws -> EditOperation {
        guard !StyleKit.builtIn.contains(where: { $0.id == kit.id }) else {
            throw ProjectError.invalid("\(kit.id) is a built-in style kit; choose another ID")
        }
        let entry = JSONValue.object([
            "id": .string(kit.id), "title": .string(kit.title), "look": .string(kit.lookID),
            "captionPreset": .string(kit.captionPreset),
        ])
        return .setProjectProperties(
            patch: ["styleKits": .array(replacing(kit.id, in: self["styleKits"], with: entry))])
    }

    public func deletingStyleKit(_ id: String) throws -> EditOperation {
        guard customStyleKits.contains(where: { $0.id == id }) else {
            throw ProjectError.invalid("Unknown custom style kit: \(id)")
        }
        return .setProjectProperties(patch: ["styleKits": .array(replacing(id, in: self["styleKits"], with: nil))])
    }

    /// The catalog with the entry `id` replaced in place, appended, or (with nil) removed; other entries keep
    /// their unknown fields.
    private func replacing(_ id: String, in catalog: JSONValue?, with entry: JSONValue?) -> [JSONValue] {
        var values = catalog?.array ?? []
        if let index = values.firstIndex(where: { $0.object["id"]?.string == id }) {
            if let entry { values[index] = entry } else { values.remove(at: index) }
        } else if let entry {
            values.append(entry)
        }
        return values
    }

    func validateStyleCatalog() throws {
        let lutIDs = Set(colorLUTs.map(\.id))
        let looks = try catalogEntries("looks")
        for entry in looks {
            let look = ColorLook(fields: entry)
            try validateCatalogEntry(id: look.id, title: look.title, kind: "look", builtIn: ColorLook.builtIn.map(\.id))
            guard case .object = entry["color"] ?? .object([:]) else {
                throw ProjectError.invalid("look.\(look.id).color: expected an object")
            }
            try ColorGrade.validate(look.color, path: "look.\(look.id).color", lutIDs: lutIDs)
        }
        let kits = try catalogEntries("styleKits")
        for entry in kits {
            let kit = StyleKit(fields: entry)
            try validateCatalogEntry(id: kit.id, title: kit.title, kind: "styleKit", builtIn: StyleKit.builtIn.map(\.id))
            guard look(kit.lookID) != nil else { throw ProjectError.invalid("styleKit.\(kit.id).look: unknown look") }
            guard TextPreset.all.contains(kit.captionPreset) else {
                throw ProjectError.invalid("styleKit.\(kit.id).captionPreset: unknown text preset")
            }
        }
        for (key, entries) in [("looks", looks), ("styleKits", kits)] {
            let ids = entries.compactMap { $0["id"]?.string }
            guard Set(ids).count == ids.count else { throw ProjectError.invalid("\(key): duplicate IDs") }
        }
    }

    /// The objects in a catalog array, at most 1 000.
    private func catalogEntries(_ key: String) throws -> [[String: JSONValue]] {
        guard let value = self[key] else { return [] }
        guard case .array(let values) = value, values.count <= 1_000 else {
            throw ProjectError.invalid("\(key): expected an array of at most 1000 entries")
        }
        return try values.map {
            guard case .object(let entry) = $0 else { throw ProjectError.invalid("\(key): expected objects") }
            return entry
        }
    }

    private func validateCatalogEntry(id: String, title: String, kind: String, builtIn: [String]) throws {
        guard id.range(of: StyleCatalog.idPattern, options: .regularExpression) != nil else {
            throw ProjectError.invalid("\(kind).\(id): ID must be 1–64 lowercase letters, digits or hyphens")
        }
        guard !builtIn.contains(id) else { throw ProjectError.invalid("\(kind).\(id): ID is built in") }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 120 else {
            throw ProjectError.invalid("\(kind).\(id): title must be 1–120 characters")
        }
    }
}

/// Shared rules for catalog entries.
public enum StyleCatalog {
    public static let idPattern = "^[a-z0-9][a-z0-9-]{0,63}$"
}
