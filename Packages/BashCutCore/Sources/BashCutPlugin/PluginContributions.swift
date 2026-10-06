import BashCutProject
import Foundation

/// Host plugin API versions. Changes are additive: a host serves every version from `minimum` to `current`.
/// Version 2 adds `options`, `contributes` (actions and hooks) and the `session` transport. Version 3 adds option
/// `choiceLabels` and the `file` option type, the `BASHCUT_PLUGIN_DATA`/`BASHCUT_PLUGIN_CACHE` folders and
/// `::progress` lines from install recipes. Version 4 adds the `secret` option type and the session host channel
/// (`event` and `call` lines during a request), used by the `agent.chat` capability. Version 5 adds the
/// `agent.terminal` capability and the manifest's `terminal` object. Version 6 adds `contributes.library` (library
/// packs), the `library.search` and `library.generate` capabilities and provider `kinds`.
public enum PluginAPI {
    public static let minimum = 1
    public static let current = 6
    /// The chat-agent capability; its requests carry a host channel (API 4).
    public static let agentChat = "agent.chat"
    /// An agent CLI in a dock terminal tab (API 5); its manifest has a `terminal` object.
    public static let agentTerminal = "agent.terminal"
    /// Finds library items online or elsewhere for a panel (API 6); providers may list the `kinds` they serve.
    public static let librarySearch = "library.search"
    /// Makes new library items from a prompt (API 6); providers may list the `kinds` they serve.
    public static let libraryGenerate = "library.generate"
    /// The capabilities whose providers return library item candidates.
    public static let libraryCapabilities = [librarySearch, libraryGenerate]
}

/// How the dock shows a terminal agent (`agent.terminal`, API 5) and what its CLI may inherit.
public struct PluginTerminal: Codable, Sendable, Equatable {
    /// SF Symbol name for the tab.
    public let icon: String?
    /// Variable names the CLI inherits from the app's environment; a trailing `*` matches a prefix.
    public let environment: [String]?

    public init(icon: String? = nil, environment: [String]? = nil) {
        self.icon = icon
        self.environment = environment
    }

    public var symbol: String { icon ?? "terminal" }

    func validate() throws {
        if let icon {
            guard icon.range(of: "^[a-z0-9]+(?:\\.[a-z0-9]+)*$", options: .regularExpression) != nil, icon.count <= 64
            else { throw PluginError.invalid("terminal.icon must be an SF Symbol name") }
        }
        let environment = environment ?? []
        guard environment.count <= 32 else { throw PluginError.invalid("terminal.environment lists at most 32 names") }
        for name in environment {
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*\\*?$", options: .regularExpression) != nil,
                !name.hasPrefix("BASHCUT_"), name != "PATH"
            else { throw PluginError.invalid("terminal.environment cannot include \(name)") }
        }
    }
}

/// How the app reaches a plugin. `oneshot` starts one process per request; `session` keeps one process
/// per plugin that answers NDJSON requests until it is idle.
public enum PluginTransportKind: String, Codable, Sendable { case oneshot, session }

// MARK: - Options

/// One setting a plugin declares. The app renders it natively (plugins never ship UI code) and sends the
/// value with each request. Action parameters use the same type.
public struct PluginOption: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case string, enumeration = "enum", number, integer, bool, file, secret }
    /// Where a value is stored: per project (undoable project data) or per user (app support).
    public enum Scope: String, Codable, Sendable { case project, user }

    public let id: String
    public let title: LocalizedText
    public let help: LocalizedText?
    public let type: Kind
    public let defaultValue: JSONValue?
    public let choices: [String]?
    public let minimum: Double?
    public let maximum: Double?
    public let maxLength: Int?
    public let scope: Scope?
    /// Display text for `enum` choices, keyed by choice (`"Mai Anh": {"en": "Mai Anh — female, North"}`).
    public let choiceLabels: [String: LocalizedText]?
    /// File extensions a `file` option accepts (`["wav", "m4a"]`); any file when empty.
    public let fileTypes: [String]?
    /// The plugin's secrets belong to this option's value (a provider or endpoint): changing it selects
    /// another stored key instead of sending the current one elsewhere.
    public let bindsSecrets: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, help, type, choices, minimum, maximum, maxLength, scope, choiceLabels, fileTypes, bindsSecrets
        case defaultValue = "default"
    }

    public init(
        id: String, title: LocalizedText, help: LocalizedText? = nil, type: Kind,
        default defaultValue: JSONValue? = nil, choices: [String]? = nil, minimum: Double? = nil,
        maximum: Double? = nil, maxLength: Int? = nil, scope: Scope? = nil,
        choiceLabels: [String: LocalizedText]? = nil, fileTypes: [String]? = nil, bindsSecrets: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.help = help
        self.type = type
        self.defaultValue = defaultValue
        self.choices = choices
        self.minimum = minimum
        self.maximum = maximum
        self.maxLength = maxLength
        self.choiceLabels = choiceLabels
        self.fileTypes = fileTypes
        self.scope = scope
        self.bindsSecrets = bindsSecrets
    }

    public var effectiveScope: Scope { scope ?? .user }

    /// The text shown for an `enum` choice.
    public func label(for choice: String) -> String { choiceLabels?[choice]?.text ?? choice }

    /// The value the app uses when nothing is stored: the declared default or a type-appropriate empty value.
    public var fallback: JSONValue {
        if let defaultValue { return defaultValue }
        switch type {
        case .string, .file, .secret: return .string("")
        case .enumeration: return .string(choices?.first ?? "")
        case .number: return .number(minimum ?? 0)
        case .integer: return .integer(Int(minimum ?? 0))
        case .bool: return .bool(false)
        }
    }

    func validate() throws {
        guard PluginIdentifier.isKey(id) else { throw PluginError.invalid("Option id \(id) must be a lowercase key") }
        guard title.isValid(limit: 80), help?.isValid(limit: 500) ?? true else {
            throw PluginError.invalid("Option \(id) needs a title (and help) per language, English included")
        }
        if let choiceLabels {
            guard type == .enumeration, Set(choiceLabels.keys).isSubset(of: choices ?? []),
                choiceLabels.values.allSatisfy({ $0.isValid(limit: 120) })
            else { throw PluginError.invalid("Option \(id) choiceLabels must label its enum choices") }
        }
        if let fileTypes {
            guard type == .file, fileTypes.allSatisfy({ $0.range(of: "^[a-z0-9]{1,10}$", options: .regularExpression) != nil })
            else { throw PluginError.invalid("Option \(id) fileTypes must be lowercase extensions of a file option") }
        }
        if type == .enumeration {
            guard let choices, !choices.isEmpty, Set(choices).count == choices.count, choices.count <= 100 else {
                throw PluginError.invalid("Option \(id) needs unique choices")
            }
        }
        try validateBounds()
        if let defaultValue { _ = try check(defaultValue) }
    }

    private func validateBounds() throws {
        if type == .secret, effectiveScope != .user || defaultValue != nil {
            throw PluginError.invalid("Secret option \(id) must have user scope and no default")
        }
        if bindsSecrets == true, type == .secret || type == .file {
            throw PluginError.invalid("Option \(id) cannot bind secrets: use a string, enum, number or bool option")
        }
        if let minimum, let maximum, minimum > maximum {
            throw PluginError.invalid("Option \(id) minimum is above its maximum")
        }
        if let maxLength, !(1...100_000).contains(maxLength) {
            throw PluginError.invalid("Option \(id) maxLength must be 1...100000")
        }
    }

    /// Returns the value normalized to the option's type, or throws when it does not fit.
    public func check(_ value: JSONValue) throws -> JSONValue {
        switch (type, value) {
        case (.bool, .bool): return value
        case (.file, .string(let text)):
            guard text.count <= 4_096, !text.contains("\0") else { throw PluginError.invalid("\(id) is not a file path") }
            let ext = (text as NSString).pathExtension.lowercased()
            guard text.isEmpty || (fileTypes ?? []).isEmpty || (fileTypes ?? []).contains(ext) else {
                throw PluginError.invalid("\(id) must be a \((fileTypes ?? []).joined(separator: ", ")) file")
            }
            return value
        case (.string, .string(let text)), (.secret, .string(let text)):
            guard text.count <= (maxLength ?? 10_000) else { throw PluginError.invalid("\(id) is too long") }
            return value
        case (.enumeration, .string(let text)):
            guard choices?.contains(text) == true else {
                throw PluginError.invalid("\(id) must be one of \((choices ?? []).joined(separator: ", "))")
            }
            return value
        case (.integer, .integer), (.integer, .number), (.number, .integer), (.number, .number):
            return try checkNumber(value)
        default:
            throw PluginError.invalid("\(id) must be a \(type.rawValue)")
        }
    }

    /// Reads a command-line or text-field value as the option's type.
    public func parse(_ text: String) throws -> JSONValue {
        switch type {
        case .string, .enumeration, .file, .secret: return try check(.string(text))
        case .bool:
            switch text.lowercased() {
            case "true", "on", "yes", "1": return .bool(true)
            case "false", "off", "no", "0": return .bool(false)
            default: throw PluginError.invalid("\(id) must be on or off")
            }
        case .integer:
            guard let number = Int(text) else { throw PluginError.invalid("\(id) must be an integer") }
            return try check(.integer(number))
        case .number:
            guard let number = Double(text) else { throw PluginError.invalid("\(id) must be a number") }
            return try check(.number(number))
        }
    }

    private func checkNumber(_ value: JSONValue) throws -> JSONValue {
        guard let number = value.double, number.isFinite else { throw PluginError.invalid("\(id) must be a finite number") }
        try checkRange(number)
        if type == .number { return .number(number) }
        guard number.rounded() == number, abs(number) < 1e15 else { throw PluginError.invalid("\(id) must be an integer") }
        return .integer(Int(number))
    }

    private func checkRange(_ number: Double) throws {
        if let minimum, number < minimum { throw PluginError.invalid("\(id) must be at least \(minimum)") }
        if let maximum, number > maximum { throw PluginError.invalid("\(id) must be at most \(maximum)") }
    }

    /// JSON Schema for one option, published to MCP clients.
    public var jsonSchema: JSONValue {
        var schema: [String: JSONValue] = ["description": .string((help ?? title).text(for: "en"))]
        switch type {
        case .string, .secret: schema["type"] = .string("string")
        case .file:
            schema["type"] = .string("string")
            schema["format"] = .string("path")
        case .enumeration:
            schema["type"] = .string("string")
            schema["enum"] = .array((choices ?? []).map(JSONValue.string))
        case .number: schema["type"] = .string("number")
        case .integer: schema["type"] = .string("integer")
        case .bool: schema["type"] = .string("boolean")
        }
        if let minimum { schema["minimum"] = .number(minimum) }
        if let maximum { schema["maximum"] = .number(maximum) }
        if let defaultValue { schema["default"] = defaultValue }
        return .object(schema)
    }
}

extension Array where Element == PluginOption {
    /// Validates `values` against the options, fills defaults and rejects unknown keys.
    public func resolve(_ values: [String: JSONValue]) throws -> [String: JSONValue] {
        if let unknown = values.keys.sorted().first(where: { key in !contains { $0.id == key } }) {
            throw PluginError.invalid("Unknown parameter \(unknown)")
        }
        var resolved: [String: JSONValue] = [:]
        for option in self {
            if let value = values[option.id], value != .null {
                resolved[option.id] = try option.check(value)
            } else {
                resolved[option.id] = option.fallback
            }
        }
        return resolved
    }
}

// MARK: - Contributions

/// What a plugin adds to the editor. Everything is declarative: the app draws the UI, decides visibility
/// with `when`, and turns results into validated, undoable edits.
public struct PluginContributions: Codable, Sendable, Equatable {
    public let actions: [PluginActionContribution]?
    public let hooks: [PluginHookContribution]?
    /// Library packs the plugin ships (API 6): read-only items in the panels while the plugin is installed.
    public let library: [PluginLibraryContribution]?

    public init(
        actions: [PluginActionContribution]? = nil, hooks: [PluginHookContribution]? = nil,
        library: [PluginLibraryContribution]? = nil
    ) {
        self.actions = actions
        self.hooks = hooks
        self.library = library
    }

    public var isEmpty: Bool { (actions ?? []).isEmpty && (hooks ?? []).isEmpty && (library ?? []).isEmpty }
}

/// A command the plugin adds: a menu item, toolbar button, context-menu entry or panel button.
public struct PluginActionContribution: Codable, Sendable, Equatable, Identifiable {
    /// Read-only data the app adds to the request beyond the selection and playhead.
    public enum ContextPart: String, Codable, Sendable, CaseIterable { case timeline, media, project }

    public let id: String
    public let title: LocalizedText
    /// SF Symbol name for buttons.
    public let icon: String?
    public let placements: [String]
    public let when: String?
    public let params: [PluginOption]?
    /// `cmd+shift+g`; ignored when it collides with a built-in shortcut.
    public let shortcut: String?
    public let context: [ContextPart]?
    /// Asks the user before the action runs (destructive or slow actions).
    public let confirm: LocalizedText?

    public init(
        id: String, title: LocalizedText, icon: String? = nil, placements: [String],
        when: String? = nil, params: [PluginOption]? = nil, shortcut: String? = nil,
        context: [ContextPart]? = nil, confirm: LocalizedText? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.placements = placements
        self.when = when
        self.params = params
        self.shortcut = shortcut
        self.context = context
        self.confirm = confirm
    }

    /// Placements the app owns. `panel.<library panel>` and `inspector.<tab>` name a panel or inspector tab.
    public static let placementPattern =
        "^(menu\\.plugins|toolbar|clip\\.context|track\\.context|media\\.context|timeline\\.context|"
        + "panel\\.[a-z]+|inspector\\.[a-z]+)$"

    func validate(pluginID: String) throws {
        guard id.hasPrefix(pluginID + "."), PluginIdentifier.isStable(id) else {
            throw PluginError.invalid("Action id \(id) must start with the plugin id \(pluginID).")
        }
        guard title.isValid(limit: 80), confirm?.isValid(limit: 500) ?? true else {
            throw PluginError.invalid("Action \(id) needs a title of at most 80 characters per language, English included")
        }
        guard !placements.isEmpty, Set(placements).count == placements.count,
            placements.allSatisfy({ $0.range(of: Self.placementPattern, options: .regularExpression) != nil })
        else { throw PluginError.invalid("Action \(id) has an unknown placement") }
        if let when { _ = try PluginWhen(parsing: when) }
        let params = params ?? []
        guard Set(params.map(\.id)).count == params.count, params.count <= 32 else {
            throw PluginError.invalid("Action \(id) parameters must be unique (at most 32)")
        }
        for parameter in params { try parameter.validate() }
        if let shortcut, shortcut.isEmpty || shortcut.count > 32 {
            throw PluginError.invalid("Action \(id) has an invalid shortcut")
        }
    }
}

/// An editor event a plugin subscribes to.
public struct PluginHookContribution: Codable, Sendable, Equatable {
    public let event: String
    /// Waits this long after the last matching event and delivers only the latest one.
    public let debounceMs: Int?
    /// The hook may return proposed edits; without it, returned operations are ignored.
    public let edits: Bool?
    /// Extra read-only data sent with the event, like an action's `context`.
    public let context: [PluginActionContribution.ContextPart]?

    public init(
        event: String, debounceMs: Int? = nil, edits: Bool? = nil,
        context: [PluginActionContribution.ContextPart]? = nil
    ) {
        self.event = event
        self.debounceMs = debounceMs
        self.edits = edits
        self.context = context
    }

    public init(from decoder: any Decoder) throws {
        if let event = try? decoder.singleValueContainer().decode(String.self) {
            self.init(event: event)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            event: try container.decode(String.self, forKey: .event),
            debounceMs: try container.decodeIfPresent(Int.self, forKey: .debounceMs),
            edits: try container.decodeIfPresent(Bool.self, forKey: .edits),
            context: try container.decodeIfPresent([PluginActionContribution.ContextPart].self, forKey: .context))
    }

    public var proposesEdits: Bool { edits ?? false }
    public var kind: PluginEvent? { PluginEvent(rawValue: event) }
}

/// Every event the app sends to hooks. Hooks are notify-only: the event has already happened and a plugin
/// cannot block or change it; it may only propose a follow-up edit.
public enum PluginEvent: String, CaseIterable, Sendable, Codable {
    case appLaunched = "app.launched"
    case projectOpened = "project.opened"
    case projectSaved = "project.saved"
    case projectClosed = "project.closed"
    case projectCreated = "project.created"
    case editCommitted = "edit.committed"
    case editUndone = "edit.undone"
    case editRedone = "edit.redone"
    case selectionChanged = "selection.changed"
    case playbackStopped = "playback.stopped"
    case mediaImported = "media.imported"
    case captionsGenerated = "captions.generated"
    case beatsDetected = "beats.detected"
    case voiceGenerated = "voice.generated"
    case exportStarted = "export.started"
    case exportFinished = "export.finished"
    case exportFailed = "export.failed"
    case jobFinished = "job.finished"
    case pluginActionFinished = "plugin.action.finished"

    /// Events that can fire many times a minute. They need the `session` transport.
    public var isFrequent: Bool {
        [.editCommitted, .editUndone, .editRedone, .selectionChanged, .playbackStopped].contains(self)
    }

    /// Debounce used when the hook does not set one.
    public var defaultDebounceMs: Int { isFrequent ? 400 : 0 }
}

// MARK: - When expressions

/// A tiny condition the app evaluates to show or enable an action, so no plugin code runs for it:
/// clauses joined by `&&`, each `key`, `!key`, `key == value` or `key != value`; a value may list
/// alternatives with `|` (`selection.kind == video|audio`).
public struct PluginWhen: Sendable, Equatable {
    public static let keys: Set<String> = [
        "project", "selection", "selection.kind", "selection.role", "track", "track.kind", "track.role",
        "media", "media.kind", "timeline", "playing", "source",
    ]

    struct Clause: Sendable, Equatable {
        let key: String
        let negated: Bool
        let values: [String]?
    }

    let clauses: [Clause]

    public init(parsing text: String) throws {
        var clauses: [Clause] = []
        for raw in text.components(separatedBy: "&&") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { throw PluginError.invalid("Empty clause in when: \(text)") }
            let clause: Clause
            if let range = part.range(of: "!=") ?? part.range(of: "==") {
                let key = part[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let values = part[range.upperBound...].split(separator: "|").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
                    throw PluginError.invalid("Missing value in when: \(part)")
                }
                clause = Clause(key: key, negated: part[range] == "!=", values: values)
            } else if part.hasPrefix("!") {
                clause = Clause(key: part.dropFirst().trimmingCharacters(in: .whitespaces), negated: true, values: nil)
            } else {
                clause = Clause(key: part, negated: false, values: nil)
            }
            guard Self.keys.contains(clause.key) else {
                throw PluginError.invalid("Unknown when key \(clause.key); use \(Self.keys.sorted().joined(separator: ", "))")
            }
            clauses.append(clause)
        }
        self.clauses = clauses
    }

    /// `facts` maps keys to their current values; a missing key is false.
    public func evaluate(_ facts: [String: String]) -> Bool {
        clauses.allSatisfy { clause in
            let value = facts[clause.key]
            let holds: Bool
            if let values = clause.values {
                holds = value.map(values.contains) ?? false
            } else {
                holds = value.map { !$0.isEmpty && $0 != "false" } ?? false
            }
            return holds != clause.negated
        }
    }
}

enum PluginIdentifier {
    static func isStable(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9]+(?:[.-][a-z0-9]+)+$", options: .regularExpression) != nil
    }

    static func isKey(_ value: String) -> Bool {
        value.range(of: "^[a-zA-Z][a-zA-Z0-9_-]{0,63}$", options: .regularExpression) != nil
    }
}
