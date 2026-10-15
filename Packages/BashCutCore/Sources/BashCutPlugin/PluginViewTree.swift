import BashCutProject
import Foundation

/// One component in a plugin view (API 8). The plugin sends components as JSON (`{"type": "text", "text": "…"}`);
/// the app draws them natively, so no plugin code runs in the app. `props` keeps every field except `type`, `id` and
/// `children`; the renderer reads the ones its kind knows. A type this host does not know is kept and drawn as a
/// placeholder, so a plugin written for a newer host still shows the rest of its view.
public struct PluginViewNode: Sendable, Equatable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable {
        case section, row, divider, spacer, text, badge, keyValue, progress, image, imageCompare, audio, list
        case button, textField, textArea, toggle, picker, slider
        /// A grid of tiles (thumbnails with title, badge, audio preview and buttons) like `list` items: sends `select`
        /// with the item id, `action` with `{"item", "action"}` and `click` with `"more"` from its load-more button.
        case grid
        /// A colour well: `value` is `#RRGGBB` (`#RRGGBBAA` with `alpha`); sends `change` with the hex string.
        case colorPicker
        /// A font menu of the project's fonts and the installed ones (what `fonts list` lists): `value` is a PostScript
        /// name, or a family name with `"by": "family"`; sends `change` with it.
        case fontPicker
        /// Two or three columns side by side (API 11): `children` are the columns, `widths` gives each a width in
        /// points or `"flex"` (`[200, "flex", 280]`); narrower than `splitCollapseWidth`, the fixed columns fold into
        /// disclosures above and below the flexible ones. As the only component of a window, sheet or dock view, each
        /// column scrolls on its own.
        case split
        /// A vertical list of groups of entries (API 11), each with an icon and a count: `groups` is
        /// `[{"title"?, "items": [{"id", "title", "icon"?, "count"?}]}]`, `value` the selected entry; sends `select`
        /// with the entry id.
        case nav

        /// Components that send events and so need an `id`.
        public var isInteractive: Bool { isInput || [.button, .list, .grid, .nav].contains(self) }

        /// Inputs whose current value goes with every event as `values[id]`.
        public var isInput: Bool {
            [.textField, .textArea, .toggle, .picker, .slider, .colorPicker, .fontPicker].contains(self)
        }
    }

    /// The plugin's `id`, or a path such as `_0.2` for components without one.
    public let id: String
    public let type: String
    public let props: [String: JSONValue]
    public let children: [PluginViewNode]

    public init(id: String, type: String, props: [String: JSONValue] = [:], children: [PluginViewNode] = []) {
        self.id = id
        self.type = type
        self.props = props
        self.children = children
    }

    public var kind: Kind? { Kind(rawValue: type) }

    public func string(_ key: String) -> String? { props[key]?.string }
    public func double(_ key: String) -> Double? { props[key]?.double }
    public func bool(_ key: String) -> Bool { props[key]?.bool ?? false }
    public func array(_ key: String) -> [JSONValue] { props[key]?.array ?? [] }

    /// The value an input starts with.
    public var initialValue: JSONValue {
        if let value = props["value"] { return value }
        switch kind {
        case .toggle: return .bool(false)
        case .slider: return .number(double("min") ?? 0)
        case .colorPicker: return .string(bool("alpha") ? "#FFFFFFFF" : "#FFFFFF")
        default: return .string("")
        }
    }

    /// The component as the plugin sent it, for `plugins view`.
    public var json: JSONValue {
        var fields = props
        fields["type"] = .string(type)
        if !id.hasPrefix("_") { fields["id"] = .string(id) }
        if !children.isEmpty { fields["children"] = .array(children.map(\.json)) }
        return .object(fields)
    }
}

/// A plugin view's answer to `view.render` or `view.event` (API 8):
/// `{"title"?, "body": [component…], "state"?, "refreshSeconds"?, "notify"?}`.
public struct PluginViewTree: Sendable, Equatable {
    public static let maximumNodes = 2000
    public static let maximumDepth = 12
    public static let maximumListItems = 500
    public static let maximumOptions = 200
    public static let maximumTextLength = 20_000
    public static let maximumStateBytes = 64 * 1024

    public let title: String?
    public let body: [PluginViewNode]
    /// Opaque data the app sends back with the next request, so the plugin can stay stateless.
    public let state: JSONValue?
    /// Render again after this many seconds while the view is on screen (at least 2).
    public let refreshSeconds: Int?
    /// A short status message to show once.
    public let notify: String?
    /// Closes the view when it is in a sheet or window (a finished form).
    public let close: Bool
    /// The library item (`scope:id`) the answer to a `drag` event names (API 11): the host places it where the
    /// dragged grid tile was dropped.
    public let libraryItem: String?

    public init(
        title: String? = nil, body: [PluginViewNode], state: JSONValue? = nil, refreshSeconds: Int? = nil,
        notify: String? = nil, close: Bool = false, libraryItem: String? = nil
    ) {
        self.title = title
        self.body = body
        self.state = state
        self.refreshSeconds = refreshSeconds
        self.notify = notify
        self.close = close
        self.libraryItem = libraryItem
    }

    /// Below this width (points) a `split`'s fixed columns fold into disclosures.
    public static let splitCollapseWidth = 900.0
    /// The width range of a fixed `split` column.
    public static let splitColumnWidths: ClosedRange<Double> = 120...600
    public static let maximumNavGroups = 20

    public init(parsing result: JSONValue) throws {
        let fields = result.object
        guard case .array(let items)? = fields["body"] else {
            throw PluginError.invalid("A view answer needs a body array of components")
        }
        var count = 0
        var ids = Set<String>()
        body = try items.enumerated().map { index, item in
            try Self.node(item, path: "_\(index)", depth: 1, count: &count, ids: &ids)
        }
        title = fields["title"]?.string.map { String($0.prefix(80)) }
        if let state = fields["state"], state != .null {
            guard let size = try? JSONEncoder().encode(state).count, size <= Self.maximumStateBytes else {
                throw PluginError.invalid("View state is larger than 64 KiB")
            }
            self.state = state
        } else {
            state = nil
        }
        refreshSeconds = fields["refreshSeconds"]?.int.map { min(max($0, 2), 3600) }
        notify = fields["notify"]?.string.map { String($0.prefix(300)) }
        close = fields["close"]?.bool ?? false
        libraryItem = fields["libraryItem"]?.string.flatMap { PluginViewDrag.libraryPayload($0) != nil ? $0 : nil }
    }

    private static func node(
        _ value: JSONValue, path: String, depth: Int, count: inout Int, ids: inout Set<String>
    ) throws -> PluginViewNode {
        count += 1
        guard count <= maximumNodes else { throw PluginError.invalid("A view has more than \(maximumNodes) components") }
        guard depth <= maximumDepth else { throw PluginError.invalid("A view nests deeper than \(maximumDepth) levels") }
        guard case .object(var fields) = value, let type = fields.removeValue(forKey: "type")?.string,
            type.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,31}$", options: .regularExpression) != nil
        else { throw PluginError.invalid("Each view component needs a type") }
        let declaredID = fields.removeValue(forKey: "id")?.string
        let kind = PluginViewNode.Kind(rawValue: type)
        if let declaredID {
            guard declaredID.range(of: "^[a-zA-Z][a-zA-Z0-9_.-]{0,63}$", options: .regularExpression) != nil else {
                throw PluginError.invalid("View component id \(declaredID) must be a short key")
            }
            guard ids.insert(declaredID).inserted else { throw PluginError.invalid("View component id \(declaredID) is used twice") }
        } else if kind?.isInteractive == true {
            throw PluginError.invalid("A \(type) component needs an id")
        }
        let childValues = fields.removeValue(forKey: "children")?.array ?? []
        try check(&fields, kind: kind, id: declaredID, columns: childValues.count)
        let children = try childValues.enumerated().map { index, child in
            try node(child, path: "\(path).\(index)", depth: depth + 1, count: &count, ids: &ids)
        }
        return PluginViewNode(id: declaredID ?? path, type: type, props: fields, children: children)
    }

    /// Cuts long texts and checks list and grid items and picker options.
    private static func check(
        _ fields: inout [String: JSONValue], kind: PluginViewNode.Kind?, id: String?, columns: Int
    ) throws {
        for (key, field) in fields {
            if case .string(let text) = field, text.count > maximumTextLength {
                fields[key] = .string(String(text.prefix(maximumTextLength)))
            }
        }
        if let kind, [.list, .grid].contains(kind) {
            let items = fields["items"]?.array ?? []
            guard items.count <= maximumListItems else {
                throw PluginError.invalid("A \(kind.rawValue) shows at most \(maximumListItems) items")
            }
            guard items.allSatisfy({ !($0.object["id"]?.string?.isEmpty ?? true) }) else {
                throw PluginError.invalid("\(kind == .grid ? "Grid" : "List") \(id ?? "") items need an id")
            }
        }
        try checkLayout(fields, kind: kind, columns: columns, id: id)
        if kind == .picker, (fields["options"]?.array.count ?? 0) > maximumOptions {
            throw PluginError.invalid("A picker offers at most \(maximumOptions) options")
        }
        if kind == .colorPicker, let value = fields["value"], value != .null {
            guard let hex = value.string.flatMap({ PluginViewColor.normalized($0, alpha: fields["alpha"]?.bool ?? false) })
            else { throw PluginError.invalid("colorPicker \(id ?? "") value must be #RRGGBB or #RRGGBBAA") }
            fields["value"] = .string(hex)
        }
        if kind == .fontPicker, let by = fields["by"]?.string, !["font", "family"].contains(by) {
            throw PluginError.invalid("fontPicker \(id ?? "") by must be font or family")
        }
    }

    private static func checkLayout(
        _ fields: [String: JSONValue], kind: PluginViewNode.Kind?, columns: Int, id: String?
    ) throws {
        switch kind {
        case .split: try checkSplit(fields, columns: columns, id: id)
        case .nav: try checkNav(fields, id: id)
        default: break
        }
    }

    /// A split has 2 or 3 columns; `widths`, when given, has one entry per column: points or `"flex"`.
    private static func checkSplit(_ fields: [String: JSONValue], columns: Int, id: String?) throws {
        guard (2...3).contains(columns) else { throw PluginError.invalid("split \(id ?? "") needs 2 or 3 children (its columns)") }
        guard let widths = fields["widths"], widths != .null else { return }
        guard case .array(let entries) = widths, entries.count == columns else {
            throw PluginError.invalid("split \(id ?? "") widths needs one entry per column")
        }
        for entry in entries {
            if entry.string == "flex" { continue }
            guard let points = entry.double, splitColumnWidths.contains(points) else {
                throw PluginError.invalid("split \(id ?? "") widths are \(Int(splitColumnWidths.lowerBound))–"
                    + "\(Int(splitColumnWidths.upperBound)) points or \"flex\"")
            }
        }
    }

    /// A nav has at most `maximumNavGroups` groups and `maximumListItems` entries, each with an id.
    private static func checkNav(_ fields: [String: JSONValue], id: String?) throws {
        let groups = fields["groups"]?.array ?? []
        guard groups.count <= maximumNavGroups else {
            throw PluginError.invalid("nav \(id ?? "") has more than \(maximumNavGroups) groups")
        }
        let entries = groups.flatMap { $0.object["items"]?.array ?? [] }
        guard entries.count <= maximumListItems else {
            throw PluginError.invalid("nav \(id ?? "") shows at most \(maximumListItems) entries")
        }
        guard entries.allSatisfy({ !($0.object["id"]?.string?.isEmpty ?? true) }) else {
            throw PluginError.invalid("nav \(id ?? "") entries need an id")
        }
    }

    /// Every component, depth first.
    public var nodes: [PluginViewNode] {
        var result: [PluginViewNode] = []
        func walk(_ nodes: [PluginViewNode]) {
            for node in nodes {
                result.append(node)
                walk(node.children)
            }
        }
        walk(body)
        return result
    }

    public func node(_ id: String) -> PluginViewNode? { nodes.first { $0.id == id } }

    /// The `split` that is the whole body: a window, sheet or dock host lets it fill the height, each column scrolling.
    public var fillingSplit: PluginViewNode? { body.count == 1 && body[0].kind == .split ? body[0] : nil }

    /// Input id → the value the plugin set.
    public var inputValues: [String: JSONValue] {
        Dictionary(nodes.filter { $0.kind?.isInput == true }.map { ($0.id, $0.initialValue) }, uniquingKeysWith: { _, last in last })
    }

    /// The answer as JSON for `plugins view`.
    public var json: JSONValue {
        var fields: [String: JSONValue] = ["body": .array(body.map(\.json))]
        if let title { fields["title"] = .string(title) }
        if let refreshSeconds { fields["refreshSeconds"] = .integer(refreshSeconds) }
        if let libraryItem { fields["libraryItem"] = .string(libraryItem) }
        return .object(fields)
    }
}

/// Hex colours of `colorPicker` components (`views.colorPicker`).
public enum PluginViewColor {
    /// `#RRGGBB` or `#RRGGBBAA` (3- and 4-digit short forms too) in upper case; with `alpha` the result always has an
    /// alpha byte (`FF` when the value had none), without it the alpha byte is dropped. Nil for anything else.
    public static func normalized(_ text: String, alpha: Bool = false) -> String? {
        var digits = text.trimmingCharacters(in: .whitespaces)
        guard digits.hasPrefix("#") else { return nil }
        digits.removeFirst()
        guard digits.allSatisfy(\.isHexDigit), [3, 4, 6, 8].contains(digits.count) else { return nil }
        if digits.count <= 4 { digits = digits.map { "\($0)\($0)" }.joined() }
        digits = digits.uppercased()
        if alpha { return "#" + (digits.count == 6 ? digits + "FF" : digits) }
        return "#" + digits.prefix(6)
    }

    /// The red, green, blue and alpha components (0–1) of a hex colour; nil when it is not one.
    public static func components(_ text: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        guard let hex = normalized(text, alpha: true), let value = UInt64(hex.dropFirst(), radix: 16) else { return nil }
        func byte(_ shift: UInt64) -> Double { Double((value >> shift) & 255) / 255 }
        return (byte(24), byte(16), byte(8), byte(0))
    }

    /// The hex text for components (0–1, clamped).
    public static func hex(red: Double, green: Double, blue: Double, alpha: Double = 1, includeAlpha: Bool = false) -> String {
        func byte(_ value: Double) -> Int { Int((min(1, max(0, value.isFinite ? value : 0)) * 255).rounded()) }
        let rgb = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return includeAlpha ? rgb + String(format: "%02X", byte(alpha)) : rgb
    }
}

/// Something the user did in a view: `click` (button), `change` (input), `submit` (text field Return), `select` (list
/// row, grid cell or nav entry, value = item id), `action` (list row or grid cell button, value = `{"item", "action"}`)
/// or `drag` (API 11: a grid tile with `drag: "download"` dropped on the timeline, value = `{"item"}`; the answer's
/// `libraryItem` is placed where it was dropped); a grid's load-more button sends `click` with value `"more"`.
public struct PluginViewEvent: Sendable, Equatable {
    public enum Kind: String, CaseIterable, Sendable { case click, change, submit, select, action, drag }

    public let node: String
    public let kind: Kind
    public let value: JSONValue

    public init(node: String, kind: Kind, value: JSONValue = .null) {
        self.node = node
        self.kind = kind
        self.value = value
    }

    public var json: JSONValue { .object(["node": .string(node), "type": .string(kind.rawValue), "value": value]) }

    /// Whether this event only replaces an earlier, still-waiting one (typing, dragging), so the earlier can be dropped.
    public func supersedes(_ other: PluginViewEvent) -> Bool { kind == .change && other.kind == .change && node == other.node }
}
