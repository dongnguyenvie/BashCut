import Foundation

// Plugin API 8: plugin UI (a rail container with declarative views) and composition (requirements on other plugins,
// capabilities a plugin calls, host features it needs).

/// Named host features (API 8). The host lists them in the session hello and in `plugins list --views`; a manifest's
/// `features` names the ones the plugin cannot work without. New features are added here instead of bumping the API
/// version for each one, so a plugin asks for exactly what it uses.
public enum PluginFeature {
    public static let container = "container"
    public static let views = "views"
    public static let requires = "requires"
    public static let invoke = "invoke"
    /// The `plugins.option` host call for the plugin's own options (#411).
    public static let optionsSet = "options.set"

    /// `providers[].maxTakes` on `voice.synthesize` providers (#410).
    public static let voiceMaxTakes = "voice.maxTakes"
    /// `providers[].clone` on `voice.synthesize` providers and saved clones sent as `reference` (#532).
    public static let voiceSavedClones = "voice.savedClones"
    /// `views[].when` on inspector views (#405).
    public static let inspectorWhen = "inspector.when"

    /// `viewUpdate` lines outside a request (#409).
    public static let viewUpdate = "viewUpdate"

    /// Plugin overlays on the timeline and viewer (#407).
    public static let overlays = "overlays"

    /// Dragging files from list rows and images onto the timeline and the Media panel (#408).
    public static let viewsDrag = "views.drag"

    /// Skill and library packs without an entrypoint (#506).
    public static let skillsOnly = "skillsOnly"

    /// The Tools panel: `tools` action placement, `views[].kind: tool` and `advanced` options (API 10).
    public static let tools = "tools"

    /// `contributes.exportSteps`: blocking steps before a final export (API 12, #634).
    public static let exportSteps = "exportSteps"

    /// `options[].check` on secrets: Settings asks the plugin (`options.check`) before saving a key.
    public static let optionsCheck = "options.check"

    /// The item field `blur` on video and image clips (a cropped, blurred copy hides one area of a picture).
    public static let clipBlur = "clip.blur"

    /// The item fields `pixelate` (a mosaic) and `feather` (edges fading out) on video and image clips.
    public static let clipMosaic = "clip.mosaic"

    /// Features that are not a view component or place.
    static let named = [
        container, views, requires, invoke, optionsSet, voiceMaxTakes, voiceSavedClones, inspectorWhen, viewUpdate,
        overlays, viewsDrag, skillsOnly, tools, exportSteps, optionsCheck, clipBlur, clipMosaic,
    ]

    /// Every feature this host provides: `views.<component>` for each view component it can draw and
    /// `location.<place>` for each place a view can live.
    public static var all: [String] {
        named + PluginViewNode.Kind.allCases.map { "views." + $0.rawValue }
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

/// Where a plugin view lives: in the plugin's rail panel, as a tab in the agent dock, in a sheet opened on demand, in
/// the Inspector under the selected item's controls (rendered again whenever the selection changes; its request
/// `context` carries the selection and its media, and a view with an empty body shows nothing there), or in a
/// non-modal window of its own (API 11) that keeps its state when it closes and can dock over the viewer.
public enum PluginViewLocation: String, Codable, Sendable, CaseIterable { case panel, dock, sheet, inspector, window }

/// What a view is for (API 10). A `panel` view fills the plugin's rail panel (the default); a `tool` view is listed in
/// the Tools panel next to the built-in tools. Asset libraries need neither: providers reach the asset panels through
/// `PluginProvider.kinds`.
public enum PluginViewKind: String, Codable, Sendable, CaseIterable { case panel, tool }

/// A plugin view (API 8). The plugin draws it by answering `view.render` and `view.event` with a component tree; see
/// `PluginViewTree`. `location` says where it shows (the rail panel by default).
public struct PluginViewContribution: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: LocalizedText
    public let location: PluginViewLocation?
    /// SF Symbol for a dock tab; the container's icon by default.
    public let icon: String?
    /// For an inspector view: a [when condition](PluginWhen) on the selection (`selection.kind == text`,
    /// `media.kind == video`); the view is not asked to render for items it does not match (#405, `inspector.when`).
    public let when: String?
    /// `panel` (default) or `tool` (API 10): a tool view is listed in the Tools panel and needs no rail container.
    public let kind: PluginViewKind?

    public init(
        id: String, title: LocalizedText, location: PluginViewLocation? = nil, icon: String? = nil, when: String? = nil,
        kind: PluginViewKind? = nil
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.icon = icon
        self.when = when
        self.kind = kind
    }

    public var effectiveKind: PluginViewKind { kind ?? .panel }

    /// True for a view the Tools panel lists (a `tool` view in the panel location).
    public var isTool: Bool { effectiveKind == .tool }

    /// The parsed `when`, nil when there is none.
    public var condition: PluginWhen? { when.flatMap { try? PluginWhen(parsing: $0) } }

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
        if isTool {
            guard place == .panel else { throw PluginError.invalid("View \(id): kind tool needs location panel") }
        }
        if let when {
            guard place == .inspector else { throw PluginError.invalid("View \(id): when is for inspector views") }
            _ = try PluginWhen(parsing: when)
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
