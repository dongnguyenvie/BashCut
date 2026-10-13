import Foundation

/// A brand kit (#453): one palette, one font pair, a logo, a mascot with poses, a voice and a disclosure line that a
/// channel keeps on every video. Stored as a `brand` library item's params and, once applied, as the project's
/// `brand` property, where recipes, graphics providers and voice skills read it.
///
/// Params: `palette` {accent, background, text, secondary} as `#RRGGBB`; `fonts` {heading, body} as font names;
/// `logo` and each `mascot` pose a sticker library reference (`id` or `scope:id`); `voice` {provider, voice}; and
/// `disclosure` (a label such as "Ảnh tạo bằng AI"); `illustration`, the style lock of generated pictures
/// (`IllustrationLock`, #550). Every field is optional, but a kit sets at least one. Other keys
/// round-trip.
///
/// Text items opt in with `brandRoles` {textStyle path: role}: `fill`, `stroke`, `highlight`, `background.color`,
/// `shadow.color` and `accentBars.color` (every bar) take a colour role, `font` a font role. Applying a kit sets the
/// project's `brand` and restyles every such item in one undo step, so two kits give two consistent looks without
/// touching the timeline by hand.
public struct LibraryBrand: Sendable, Equatable {
    public static let colorRoles = ["accent", "background", "text", "secondary"]
    public static let fontRoles = ["heading", "body"]
    /// The `textStyle` paths a text item can tie to a colour role.
    public static let colorPaths = ["fill", "stroke", "highlight", "background.color", "shadow.color", "accentBars.color"]
    public static let fontPath = "font"
    static let maximumPoses = 16

    public var palette: [String: String]
    public var fonts: [String: String]
    public var params: [String: JSONValue]

    /// Reads and checks `params`.
    public init(params: [String: JSONValue], label: String = "brand") throws {
        palette = try Self.roles(params["palette"], allowed: Self.colorRoles, label: "\(label).palette") { value in
            value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil ? nil : "#RRGGBB"
        }
        fonts = try Self.roles(params["fonts"], allowed: Self.fontRoles, label: "\(label).fonts") { value in
            (1...128).contains(value.count) ? nil : "a font name of 1–128 characters"
        }
        try Self.validateAssets(params, label: label)
        self.params = params
    }

    /// The logo, mascot poses, voice and disclosure, and that the kit sets something.
    private static func validateAssets(_ params: [String: JSONValue], label: String) throws {
        if let logo = params["logo"], logo != .null {
            guard let text = logo.string, Self.isReference(text) else {
                throw ProjectError.invalid("\(label).logo: expected a sticker library id")
            }
        }
        if let mascot = params["mascot"], mascot != .null {
            guard case .object(let poses) = mascot, poses.count <= Self.maximumPoses,
                poses.allSatisfy({ (1...40).contains($0.key.count) && ($0.value.string.map(Self.isReference) ?? false) })
            else {
                throw ProjectError.invalid(
                    "\(label).mascot: expected up to \(Self.maximumPoses) poses {name: sticker library id}")
            }
        }
        if let voice = params["voice"], voice != .null {
            guard case .object(let fields) = voice, !fields.isEmpty,
                fields.allSatisfy({ ["provider", "voice"].contains($0.key) && ($0.value.string.map { (1...160).contains($0.count) } ?? false) })
            else { throw ProjectError.invalid("\(label).voice: expected {provider, voice} texts") }
        }
        if let illustration = params["illustration"], illustration != .null {
            _ = try IllustrationLock(illustration, label: "\(label).illustration")
        }
        try validateDisclosure(params, label: label)
    }

    /// The disclosure label, and that the kit sets something.
    private static func validateDisclosure(_ params: [String: JSONValue], label: String) throws {
        if let disclosure = params["disclosure"], disclosure != .null {
            guard let text = disclosure.string, (1...200).contains(text.count) else {
                throw ProjectError.invalid("\(label).disclosure: expected a text of 1–200 characters")
            }
        }
        let used = ["palette", "fonts", "logo", "mascot", "voice", "disclosure", "illustration"].filter { key in
            guard let value = params[key], value != .null else { return false }
            if case .object(let fields) = value { return !fields.isEmpty }
            return true
        }
        guard !used.isEmpty else {
            throw ProjectError.invalid("\(label): set at least one of palette, fonts, logo, mascot, voice, disclosure or illustration")
        }
    }

    private static func roles(
        _ value: JSONValue?, allowed: [String], label: String, problem: (String) -> String?
    ) throws -> [String: String] {
        guard let value, value != .null else { return [:] }
        guard case .object(let fields) = value else { throw ProjectError.invalid("\(label): expected an object") }
        var result: [String: String] = [:]
        for (key, field) in fields {
            guard allowed.contains(key) else {
                throw ProjectError.invalid("\(label).\(key): unknown; use \(allowed.joined(separator: ", "))")
            }
            guard let text = field.string else { throw ProjectError.invalid("\(label).\(key): expected text") }
            if let expected = problem(text) { throw ProjectError.invalid("\(label).\(key): expected \(expected)") }
            result[key] = text
        }
        return result
    }

    /// A library reference: `id` or `scope:id`.
    static func isReference(_ text: String) -> Bool {
        text.range(of: "^([a-z-]+:)?[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil
    }

    /// The kit's value for a role: a colour or a font name; nil when the kit leaves it unset.
    public func value(of role: String) -> String? { palette[role] ?? fonts[role] }

    /// Checks an item's `brandRoles`: colour paths to colour roles, `font` to a font role.
    public static func validateRoles(_ value: JSONValue, label: String) throws {
        guard case .object(let fields) = value, !fields.isEmpty else {
            throw ProjectError.invalid("\(label): expected {textStyle path: role}")
        }
        for (path, role) in fields {
            let roles = path == fontPath ? fontRoles : colorRoles
            guard path == fontPath || colorPaths.contains(path) else {
                throw ProjectError.invalid(
                    "\(label).\(path): unknown; use \((colorPaths + [fontPath]).joined(separator: ", "))")
            }
            guard let name = role.string, roles.contains(name) else {
                throw ProjectError.invalid("\(label).\(path): expected one of \(roles.joined(separator: ", "))")
            }
        }
    }

    /// The `textStyle` of a text item tied to roles by `brandRoles`, with the kit's values put in; nil when the item
    /// has no roles or nothing changes. Roles the kit leaves unset keep the item's value.
    public func restyled(_ item: Item) -> JSONValue? {
        guard let roles = item["brandRoles"]?.object, !roles.isEmpty else { return nil }
        let before = item["textStyle"]?.object ?? [:]
        let style = restyled(before, roles: roles)
        return style == before ? nil : .object(style)
    }

    /// `style` with each path in `roles` set to its role's value in this kit.
    public func restyled(_ style: [String: JSONValue], roles: [String: JSONValue]) -> [String: JSONValue] {
        var style = style
        for (path, role) in roles.sorted(by: { $0.key < $1.key }) {
            guard let name = role.string, let value = value(of: name) else { continue }
            let parts = path.split(separator: ".").map(String.init)
            if parts.count == 1 {
                style[path] = .string(value)
            } else if parts[0] == "accentBars" {
                guard case .array(let bars)? = style["accentBars"] else { continue }
                style["accentBars"] = .array(bars.map { bar in
                    guard case .object(var fields) = bar else { return bar }
                    fields["color"] = .string(value)
                    return .object(fields)
                })
            } else {
                var group = style[parts[0]]?.object ?? [:]
                group[parts[1]] = .string(value)
                style[parts[0]] = .object(group)
            }
        }
        return style
    }
}

extension Project {
    /// The applied brand kit; nil when none is set or it does not parse.
    public var brand: LibraryBrand? {
        guard let params = self["brand"]?.object else { return nil }
        return try? LibraryBrand(params: params)
    }

    /// The edits that make the project use the kit `params` (named by `reference`): the `brand` property, then every
    /// text item tied to roles restyled. One group, so it is one undo step.
    public func brandOperations(_ params: [String: JSONValue], reference: String, name: String) throws -> [EditOperation] {
        let kit = try LibraryBrand(params: params)
        var stored = params
        stored["library"] = .string(reference)
        stored["name"] = .string(name)
        var operations: [EditOperation] = [.setProjectProperties(patch: ["brand": .object(stored)])]
        for item in tracks.flatMap(\.items) {
            guard let style = kit.restyled(item) else { continue }
            operations.append(.setProperties(item: item.id, patch: ["textStyle": style]))
        }
        return operations
    }

    fileprivate func validateBrandItems() throws {
        for item in tracks.flatMap(\.items) {
            guard let roles = item["brandRoles"], roles != .null else { continue }
            try LibraryBrand.validateRoles(roles, label: "item.\(item.id).brandRoles")
        }
    }

    /// `brand` (#453): a kit's params, plus the library reference and name it came from.
    func validateBrand() throws {
        if let value = self["brand"], value != .null {
            guard case .object(var params) = value else { throw ProjectError.invalid("brand: expected an object") }
            for key in ["library", "name"] {
                if let field = params.removeValue(forKey: key), field.string.map({ (1...160).contains($0.count) }) != true {
                    throw ProjectError.invalid("brand.\(key): expected text")
                }
            }
            _ = try LibraryBrand(params: params, label: "brand")
        }
        try validateBrandItems()
    }
}
