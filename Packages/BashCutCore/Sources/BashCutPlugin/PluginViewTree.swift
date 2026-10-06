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

        /// Components that send events and so need an `id`.
        public var isInteractive: Bool {
            [.button, .textField, .textArea, .toggle, .picker, .slider, .list].contains(self)
        }

        /// Inputs whose current value goes with every event as `values[id]`.
        public var isInput: Bool { [.textField, .textArea, .toggle, .picker, .slider].contains(self) }
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

    public init(
        title: String? = nil, body: [PluginViewNode], state: JSONValue? = nil, refreshSeconds: Int? = nil,
        notify: String? = nil
    ) {
        self.title = title
        self.body = body
        self.state = state
        self.refreshSeconds = refreshSeconds
        self.notify = notify
    }

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
        try check(&fields, kind: kind, id: declaredID)
        let children = try childValues.enumerated().map { index, child in
            try node(child, path: "\(path).\(index)", depth: depth + 1, count: &count, ids: &ids)
        }
        return PluginViewNode(id: declaredID ?? path, type: type, props: fields, children: children)
    }

    /// Cuts long texts and checks list items and picker options.
    private static func check(_ fields: inout [String: JSONValue], kind: PluginViewNode.Kind?, id: String?) throws {
        for (key, field) in fields {
            if case .string(let text) = field, text.count > maximumTextLength {
                fields[key] = .string(String(text.prefix(maximumTextLength)))
            }
        }
        if kind == .list {
            let items = fields["items"]?.array ?? []
            guard items.count <= maximumListItems else {
                throw PluginError.invalid("A list shows at most \(maximumListItems) items")
            }
            guard items.allSatisfy({ !($0.object["id"]?.string?.isEmpty ?? true) }) else {
                throw PluginError.invalid("List \(id ?? "") items need an id")
            }
        }
        if kind == .picker, (fields["options"]?.array.count ?? 0) > maximumOptions {
            throw PluginError.invalid("A picker offers at most \(maximumOptions) options")
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

    /// Input id → the value the plugin set.
    public var inputValues: [String: JSONValue] {
        Dictionary(nodes.filter { $0.kind?.isInput == true }.map { ($0.id, $0.initialValue) }, uniquingKeysWith: { _, last in last })
    }

    /// The answer as JSON for `plugins view`.
    public var json: JSONValue {
        var fields: [String: JSONValue] = ["body": .array(body.map(\.json))]
        if let title { fields["title"] = .string(title) }
        if let refreshSeconds { fields["refreshSeconds"] = .integer(refreshSeconds) }
        return .object(fields)
    }
}

/// Something the user did in a view: `click` (button), `change` (input), `submit` (text field Return), `select` (list
/// row, value = item id) or `action` (list row button, value = `{"item", "action"}`).
public struct PluginViewEvent: Sendable, Equatable {
    public enum Kind: String, CaseIterable, Sendable { case click, change, submit, select, action }

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
