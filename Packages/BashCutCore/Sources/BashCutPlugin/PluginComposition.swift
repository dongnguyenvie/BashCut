import Foundation

// Plugin API 8: plugin UI (a rail container with declarative views) and composition (requirements on other plugins,
// capabilities a plugin calls, host features it needs).

/// Named host features (API 8). The host lists them in the session hello and in `plugins views`; a manifest's
/// `features` names the ones the plugin cannot work without. New features are added here instead of bumping the API
/// version for each one, so a plugin asks for exactly what it uses.
public enum PluginFeature {
    public static let container = "container"
    public static let views = "views"
    public static let requires = "requires"
    public static let invoke = "invoke"

    /// Every feature this host provides: `views.<component>` for each view component it can draw and
    /// `location.<place>` for each place a view can live.
    public static var all: [String] {
        [container, views, requires, invoke] + PluginViewNode.Kind.allCases.map { "views." + $0.rawValue }
            + PluginViewLocation.allCases.map { "location." + $0.rawValue }
    }

    static func isName(_ value: String) -> Bool {
        value.count <= 64 && value.range(of: "^[a-z][a-zA-Z0-9]*(?:[.-][a-zA-Z0-9]+)*$", options: .regularExpression) != nil
    }
}

/// The plugin's icon in the left rail and the panel it opens (API 8).
public struct PluginContainerContribution: Codable, Sendable, Equatable {
    /// SF Symbol name.
    public let icon: String
    /// Short label under the icon and the panel title; the plugin name when left out.
    public let title: LocalizedText?

    public init(icon: String, title: LocalizedText? = nil) {
        self.icon = icon
        self.title = title
    }

    func validate() throws {
        guard icon.range(of: "^[a-z0-9]+(?:\\.[a-z0-9]+)*$", options: .regularExpression) != nil, icon.count <= 64 else {
            throw PluginError.invalid("contributes.container.icon must be an SF Symbol name")
        }
        guard title?.isValid(limit: 24) ?? true else {
            throw PluginError.invalid("contributes.container.title needs at most 24 characters per language, English included")
        }
    }
}

/// Where a plugin view lives: in the plugin's rail panel, as a tab in the agent dock, or in a sheet opened on demand.
public enum PluginViewLocation: String, Codable, Sendable, CaseIterable { case panel, dock, sheet }

/// A plugin view (API 8). The plugin draws it by answering `view.render` and `view.event` with a component tree; see
/// `PluginViewTree`. `location` says where it shows (the rail panel by default).
public struct PluginViewContribution: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: LocalizedText
    public let location: PluginViewLocation?
    /// SF Symbol for a dock tab; the container's icon by default.
    public let icon: String?

    public init(id: String, title: LocalizedText, location: PluginViewLocation? = nil, icon: String? = nil) {
        self.id = id
        self.title = title
        self.location = location
        self.icon = icon
    }

    public static let maximumViews = 8

    public var place: PluginViewLocation { location ?? .panel }

    func validate() throws {
        guard PluginIdentifier.isKey(id) else { throw PluginError.invalid("View id \(id) must be a short key") }
        guard title.isValid(limit: 40) else {
            throw PluginError.invalid("View \(id) needs a title of at most 40 characters per language, English included")
        }
        if let icon {
            guard icon.range(of: "^[a-z0-9]+(?:\\.[a-z0-9]+)*$", options: .regularExpression) != nil, icon.count <= 64 else {
                throw PluginError.invalid("View \(id) icon must be an SF Symbol name")
            }
        }
    }
}

/// Another plugin this one needs (API 8). Until it is installed, ready and in the version range, this plugin is
/// listed but never runs.
public struct PluginRequirement: Codable, Sendable, Equatable {
    public let id: String
    /// A version range such as `>=0.2.0`, `^1.2.0`, `~1.2.0`, `1.2.3` or `*` (the default); clauses separated by
    /// spaces must all hold (`>=1.0.0 <2.0.0`).
    public let version: String?

    public init(id: String, version: String? = nil) {
        self.id = id
        self.version = version
    }

    public static let maximumRequirements = 16

    public var range: PluginVersionRange { (try? PluginVersionRange(version ?? "*")) ?? .any }

    func validate(pluginID: String) throws {
        guard PluginIdentifier.isStable(id), id != pluginID else {
            throw PluginError.invalid("requires: \(id) must be another plugin's id")
        }
        _ = try PluginVersionRange(version ?? "*")
    }
}

/// A set of semantic version clauses that must all hold.
public struct PluginVersionRange: Sendable, Equatable, CustomStringConvertible {
    enum Operator: String, CaseIterable { case greaterOrEqual = ">=", lessOrEqual = "<=", greater = ">", less = "<", equal = "=" }

    struct Clause: Sendable, Equatable {
        let op: Operator
        let version: String
    }

    let clauses: [Clause]
    public let description: String

    public static let any = PluginVersionRange(clauses: [], description: "*")

    private init(clauses: [Clause], description: String) {
        self.clauses = clauses
        self.description = description
    }

    public init(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { throw PluginError.invalid("Invalid version range \(text)") }
        description = trimmed
        if trimmed == "*" {
            clauses = []
            return
        }
        var clauses: [Clause] = []
        for part in trimmed.split(separator: " ").map(String.init) {
            clauses += try Self.parse(part, original: text)
        }
        self.clauses = clauses
    }

    private static func parse(_ part: String, original: String) throws -> [Clause] {
        func version(_ text: String) throws -> SemanticVersion {
            guard let parsed = SemanticVersion(text) else { throw PluginError.invalid("Invalid version range \(original)") }
            return parsed
        }
        if part.hasPrefix("^") || part.hasPrefix("~") {
            let base = try version(String(part.dropFirst()))
            let numbers = base.numbers
            let upper: [Int]
            if part.hasPrefix("~") {
                upper = [numbers[0], numbers[1] + 1, 0]
            } else if numbers[0] > 0 {
                upper = [numbers[0] + 1, 0, 0]
            } else if numbers[1] > 0 {
                upper = [0, numbers[1] + 1, 0]
            } else {
                upper = [0, 0, numbers[2] + 1]
            }
            return [
                Clause(op: .greaterOrEqual, version: base.description),
                Clause(op: .less, version: upper.map(String.init).joined(separator: ".")),
            ]
        }
        for op in Operator.allCases where part.hasPrefix(op.rawValue) {
            let rest = String(part.dropFirst(op.rawValue.count))
            return [Clause(op: op, version: try version(rest).description)]
        }
        return [Clause(op: .equal, version: try version(part).description)]
    }

    /// Whether `version` (a plugin's semantic version) is in the range.
    public func contains(_ version: String) -> Bool {
        guard let value = SemanticVersion(version) else { return false }
        return clauses.allSatisfy { clause in
            guard let bound = SemanticVersion(clause.version) else { return false }
            switch clause.op {
            case .greaterOrEqual: return value >= bound
            case .lessOrEqual: return value <= bound
            case .greater: return value > bound
            case .less: return value < bound
            case .equal: return value == bound
            }
        }
    }
}

/// Why a plugin's requirements are not met, for every plugin in a catalog (API 8). A requirement holds when the
/// required plugin is installed in the version range and is itself ready (its own requirements included).
public enum PluginRequirements {
    /// Plugin ID → reason for each plugin whose requirements fail. `ready` says whether a plugin may run on its own
    /// (trusted, enabled, compatible); requirements chain, and a cycle fails every plugin in it.
    public static func problems(
        _ plugins: [InstalledPlugin], ready: (InstalledPlugin) -> Bool
    ) -> [String: String] {
        let byID = Dictionary(plugins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var memo: [String: String?] = [:]
        func problem(_ plugin: InstalledPlugin, visiting: Set<String>) -> String? {
            if let known = memo[plugin.id] { return known }
            var reason: String?
            for requirement in plugin.manifest.requirements {
                let range = requirement.range
                guard let required = byID[requirement.id] else {
                    reason = "Needs the plugin \(requirement.id)" + (range == .any ? "" : " \(range)")
                    break
                }
                let name = required.manifest.displayName
                guard range.contains(required.manifest.version) else {
                    reason = "Needs \(name) \(range); \(required.manifest.version) is installed"
                    break
                }
                guard !visiting.contains(required.id) else {
                    reason = "Requirements form a loop through \(name)"
                    break
                }
                guard ready(required) else {
                    reason = "Needs \(name), which is not ready"
                    break
                }
                if problem(required, visiting: visiting.union([plugin.id])) != nil {
                    reason = "Needs \(name), which is missing its own requirements"
                    break
                }
            }
            memo[plugin.id] = .some(reason)
            return reason
        }
        var result: [String: String] = [:]
        for plugin in plugins {
            if let reason = problem(plugin, visiting: [plugin.id]) { result[plugin.id] = reason }
        }
        return result
    }

    /// Requirements of `plugin` that no installed plugin satisfies, for offering installs.
    public static func missing(_ plugin: InstalledPlugin, installed: [InstalledPlugin]) -> [PluginRequirement] {
        plugin.manifest.requirements.filter { requirement in
            !installed.contains { $0.id == requirement.id && requirement.range.contains($0.manifest.version) }
        }
    }
}
