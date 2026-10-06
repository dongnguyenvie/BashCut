import BashCutProject
import Foundation

public struct PluginManifest: Codable, Sendable, Equatable {
    public static let schema = "bashcut.plugin/1"

    public let schema: String
    public let id: String
    public let name: LocalizedText
    public let version: String
    public let apiVersion: Int
    public let entrypoint: String
    public let capabilities: [String]
    public let providers: [PluginProvider]?
    public let dependencies: [PluginDependency]
    /// Oldest host API the plugin works with; defaults to `apiVersion`.
    public let minApiVersion: Int?
    /// Newest host API the plugin was built for; nil means any later additive version.
    public let maxApiVersion: Int?
    public let transport: PluginTransportKind?
    public let options: [PluginOption]?
    public let contributes: PluginContributions?
    /// The dock tab of an `agent.terminal` plugin (API 5).
    public let terminal: PluginTerminal?
    /// One of `PluginCategory`'s ids, for grouping in Plugins and Settings; the registry listing's wins.
    public let category: String?

    public init(
        id: String, name: LocalizedText, version: String, apiVersion: Int = 1,
        entrypoint: String, capabilities: [String], providers: [PluginProvider]? = nil,
        dependencies: [PluginDependency] = [], minApiVersion: Int? = nil, maxApiVersion: Int? = nil,
        transport: PluginTransportKind? = nil, options: [PluginOption]? = nil,
        contributes: PluginContributions? = nil, terminal: PluginTerminal? = nil, category: String? = nil
    ) {
        schema = Self.schema
        self.id = id
        self.name = name
        self.version = version
        self.apiVersion = apiVersion
        self.entrypoint = entrypoint
        self.capabilities = capabilities
        self.providers = providers
        self.dependencies = dependencies
        self.minApiVersion = minApiVersion
        self.maxApiVersion = maxApiVersion
        self.transport = transport
        self.options = options
        self.contributes = contributes
        self.terminal = terminal
        self.category = category
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(LocalizedText.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        apiVersion = try container.decode(Int.self, forKey: .apiVersion)
        entrypoint = try container.decode(String.self, forKey: .entrypoint)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        providers = try container.decodeIfPresent([PluginProvider].self, forKey: .providers)
        dependencies = try container.decodeIfPresent([PluginDependency].self, forKey: .dependencies) ?? []
        minApiVersion = try container.decodeIfPresent(Int.self, forKey: .minApiVersion)
        maxApiVersion = try container.decodeIfPresent(Int.self, forKey: .maxApiVersion)
        transport = try container.decodeIfPresent(PluginTransportKind.self, forKey: .transport)
        options = try container.decodeIfPresent([PluginOption].self, forKey: .options)
        contributes = try container.decodeIfPresent(PluginContributions.self, forKey: .contributes)
        terminal = try container.decodeIfPresent(PluginTerminal.self, forKey: .terminal)
        category = try container.decodeIfPresent(String.self, forKey: .category)
    }

    public var transportKind: PluginTransportKind { transport ?? .oneshot }
    /// The name in the app's interface language.
    public var displayName: String { name.text }
    public var actions: [PluginActionContribution] { contributes?.actions ?? [] }
    public var hooks: [PluginHookContribution] { contributes?.hooks ?? [] }
    /// Library packs the plugin ships (API 6).
    public var libraryPacks: [PluginLibraryContribution] { contributes?.library ?? [] }
    /// Agent skills the plugin ships (API 7).
    public var skills: [PluginSkillContribution] { contributes?.skills ?? [] }

    /// Why this host cannot run the plugin, or nil when its API window includes the host.
    public var incompatibility: String? {
        let needed = minApiVersion ?? apiVersion
        if needed > PluginAPI.current {
            return "Needs plugin API \(needed); this BashCut provides \(PluginAPI.current). Update BashCut."
        }
        if let maxApiVersion, maxApiVersion < PluginAPI.minimum {
            return "Built for plugin API \(maxApiVersion); this BashCut needs at least \(PluginAPI.minimum). Update the plugin."
        }
        return nil
    }

    public func validate() throws {
        func matches(_ value: String, _ pattern: String) -> Bool {
            value.range(of: pattern, options: .regularExpression) != nil
        }
        guard schema == Self.schema else { throw PluginError.invalid("Unsupported plugin schema") }
        guard apiVersion >= 1, (minApiVersion ?? apiVersion) <= apiVersion,
            (maxApiVersion ?? apiVersion) >= apiVersion
        else { throw PluginError.invalid("Unsupported plugin API version window") }
        guard matches(id, "^[a-z0-9]+(?:[.-][a-z0-9]+)+$") else {
            throw PluginError.invalid("Plugin id must be reverse-domain style")
        }
        guard name.isValid(limit: 80),
            matches(version, "^[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$")
        else { throw PluginError.invalid("Plugin name and semantic version are required") }
        try Self.validateRelativePath(entrypoint, field: "entrypoint")
        guard !capabilities.isEmpty || !(contributes?.isEmpty ?? true), Set(capabilities).count == capabilities.count,
            capabilities.allSatisfy({ matches($0, "^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$") })
        else { throw PluginError.invalid("Capabilities must be unique stable identifiers") }
        guard Set(dependencies.map(\.id)).count == dependencies.count else {
            throw PluginError.invalid("Dependency ids must be unique")
        }
        let declaredProviders = providers ?? []
        guard Set(declaredProviders.map(\.id)).count == declaredProviders.count,
            declaredProviders.allSatisfy({ capabilities.contains($0.capability) })
        else { throw PluginError.invalid("Providers must be unique and declare a plugin capability") }
        guard declaredProviders.allSatisfy({ ($0.timeoutSeconds ?? 120) >= 10 && ($0.timeoutSeconds ?? 120) <= 3600 })
        else { throw PluginError.invalid("Provider timeoutSeconds must be 10...3600") }
        for dependency in dependencies { try dependency.validate() }
        try validateExtensions()
    }

    /// Options, actions and hooks (plugin API 2).
    private func validateExtensions() throws {
        let usesExtensions = options != nil || contributes != nil || transport == .session
        guard !usesExtensions || apiVersion >= 2 else {
            throw PluginError.invalid("options, contributes and the session transport need apiVersion 2")
        }
        let options = options ?? []
        let usesAPI3 = (options + actions.flatMap { $0.params ?? [] }).contains { $0.type == .file || $0.choiceLabels != nil }
        guard !usesAPI3 || apiVersion >= 3 else {
            throw PluginError.invalid("file options and choiceLabels need apiVersion 3")
        }
        guard !(actions.flatMap { $0.params ?? [] }).contains(where: { $0.type == .secret }) else {
            throw PluginError.invalid("Action parameters cannot be secrets")
        }
        let usesAPI4 = options.contains { $0.type == .secret } || capabilities.contains(PluginAPI.agentChat)
        guard !usesAPI4 || apiVersion >= 4 else {
            throw PluginError.invalid("secret options and agent.chat need apiVersion 4")
        }
        guard !capabilities.contains(PluginAPI.agentChat) || transport == .session else {
            throw PluginError.invalid("agent.chat needs the session transport")
        }
        try validateTerminal()
        try validateLibrary()
        try validateSkills()
        guard Set(options.map(\.id)).count == options.count, options.count <= 64 else {
            throw PluginError.invalid("Option ids must be unique (at most 64)")
        }
        for option in options { try option.validate() }
        guard Set(actions.map(\.id)).count == actions.count, actions.count <= 64 else {
            throw PluginError.invalid("Action ids must be unique (at most 64)")
        }
        for action in actions { try action.validate(pluginID: id) }
        try validateHooks()
    }

    private func validateTerminal() throws {
        let declares = capabilities.contains(PluginAPI.agentTerminal)
        guard !declares || apiVersion >= 5 else { throw PluginError.invalid("agent.terminal needs apiVersion 5") }
        guard declares == (terminal != nil) else {
            throw PluginError.invalid("agent.terminal and the terminal object go together")
        }
        try terminal?.validate()
    }

    /// Library packs, `library.search`/`library.generate` and provider `kinds` (plugin API 6).
    private func validateLibrary() throws {
        let declaredProviders = providers ?? []
        let usesAPI6 = !libraryPacks.isEmpty || declaredProviders.contains { $0.kinds != nil }
            || capabilities.contains(where: PluginAPI.libraryCapabilities.contains)
        guard !usesAPI6 || apiVersion >= 6 else {
            throw PluginError.invalid("contributes.library, library.search, library.generate and provider kinds need apiVersion 6")
        }
        guard libraryPacks.count <= PluginLibraryContribution.maximumPacks,
            Set(libraryPacks.map { NSString(string: $0.path).standardizingPath }).count == libraryPacks.count
        else {
            throw PluginError.invalid(
                "contributes.library lists at most \(PluginLibraryContribution.maximumPacks) different pack folders")
        }
        for pack in libraryPacks { try pack.validate() }
        for provider in declaredProviders {
            guard let kinds = provider.kinds else { continue }
            guard PluginAPI.libraryCapabilities.contains(provider.capability) else {
                throw PluginError.invalid("Provider \(provider.id): kinds are for library.search and library.generate")
            }
            guard !kinds.isEmpty, Set(kinds).count == kinds.count,
                kinds.allSatisfy({ LibraryKind(rawValue: $0) != nil })
            else {
                throw PluginError.invalid(
                    "Provider \(provider.id): kinds must be unique library kinds ("
                        + LibraryKind.allCases.map(\.rawValue).joined(separator: ", ") + ")")
            }
        }
    }

    /// Agent skills (plugin API 7).
    private func validateSkills() throws {
        guard !skills.isEmpty else { return }
        guard apiVersion >= 7 else { throw PluginError.invalid("contributes.skills needs apiVersion 7") }
        guard skills.count <= PluginSkillContribution.maximumSkills,
            Set(skills.map { NSString(string: $0.path).standardizingPath }).count == skills.count
        else {
            throw PluginError.invalid(
                "contributes.skills lists at most \(PluginSkillContribution.maximumSkills) different skill folders")
        }
        for skill in skills { try skill.validate() }
    }

    private func validateHooks() throws {
        guard Set(hooks.map(\.event)).count == hooks.count else {
            throw PluginError.invalid("Each hook event may appear once")
        }
        for hook in hooks {
            guard let event = hook.kind else {
                throw PluginError.invalid("Unknown hook event \(hook.event)")
            }
            guard !event.isFrequent || transportKind == .session else {
                throw PluginError.invalid("Hook \(hook.event) fires often and needs \"transport\": \"session\"")
            }
            if let debounce = hook.debounceMs, !(0...60_000).contains(debounce) {
                throw PluginError.invalid("Hook \(hook.event) debounceMs must be 0...60000")
            }
        }
    }

    private static func validateRelativePath(_ path: String, field: String) throws {
        let components = NSString(string: path).pathComponents
        guard !path.isEmpty, !path.hasPrefix("/"), !components.contains("..") else {
            throw PluginError.invalid("\(field) must stay inside the plugin bundle")
        }
    }
}

public struct PluginProvider: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let capability: String
    public let name: String
    public let priority: Int
    /// Seconds a request may go without reporting progress (default 120), for providers with long silent steps.
    public let timeoutSeconds: Int?
    /// Library kinds a `library.search` or `library.generate` provider serves (API 6); nil serves every kind.
    public let kinds: [String]?

    public init(
        id: String, capability: String, name: String, priority: Int = 0, timeoutSeconds: Int? = nil, kinds: [String]? = nil
    ) {
        self.id = id
        self.capability = capability
        self.name = name
        self.priority = priority
        self.timeoutSeconds = timeoutSeconds
        self.kinds = kinds
    }

    /// Whether a library provider serves `kind`.
    public func serves(_ kind: LibraryKind) -> Bool { kinds?.contains(kind.rawValue) ?? true }

    /// `priority` may be left out of a manifest; it defaults to 0, as the plugin guide says.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        capability = try container.decode(String.self, forKey: .capability)
        name = try container.decode(String.self, forKey: .name)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds)
        kinds = try container.decodeIfPresent([String].self, forKey: .kinds)
    }
}

public struct PluginDependency: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case executable, python, model, systemLibrary }

    public let id: String
    public let name: String
    public let kind: Kind
    public let probe: PluginCommand
    public let install: PluginInstallRecipe?
    public let estimatedBytes: Int64?

    public init(
        id: String, name: String, kind: Kind, probe: PluginCommand,
        install: PluginInstallRecipe? = nil, estimatedBytes: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.probe = probe
        self.install = install
        self.estimatedBytes = estimatedBytes
    }

    fileprivate func validate() throws {
        guard !id.isEmpty, !name.isEmpty else { throw PluginError.invalid("Invalid dependency") }
        try probe.validate()
        try install?.command.validate()
        if let estimatedBytes, estimatedBytes < 0 { throw PluginError.invalid("Invalid download size") }
    }
}

/// Commands are argv arrays and never shell strings, so manifests cannot smuggle shell expansion.
public struct PluginCommand: Codable, Sendable, Equatable {
    public let executable: String
    public let arguments: [String]
    public init(executable: String, arguments: [String] = []) {
        self.executable = executable
        self.arguments = arguments
    }

    /// `arguments` may be left out of a manifest; it defaults to none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        executable = try container.decode(String.self, forKey: .executable)
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
    }

    fileprivate func validate() throws {
        guard !executable.isEmpty, !executable.contains("\0"),
            !arguments.contains(where: { $0.contains("\0") })
        else {
            throw PluginError.invalid("Invalid dependency command")
        }
        if executable.contains("/") {
            let components = NSString(string: executable).pathComponents
            guard !executable.hasPrefix("/"), !components.contains("..") else {
                throw PluginError.invalid("Dependency commands must stay inside the plugin bundle")
            }
        }
    }
}

public struct PluginInstallRecipe: Codable, Sendable, Equatable {
    public let summary: String
    public let command: PluginCommand
    public init(summary: String, command: PluginCommand) {
        self.summary = summary
        self.command = command
    }
}

public enum PluginError: Error, LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? {
        guard case .invalid(let message) = self else { return nil }
        return message
    }
}

public struct PluginRPCRequest: Codable, Sendable, Equatable {
    public let id: String
    public let apiVersion: Int
    public let method: String
    public let provider: String?
    public let params: JSONValue

    public init(
        id: String = UUID().uuidString, apiVersion: Int = 1, method: String,
        provider: String? = nil, params: JSONValue = .object([:])
    ) {
        self.id = id
        self.apiVersion = apiVersion
        self.method = method
        self.provider = provider
        self.params = params
    }
}

public struct PluginRPCFailure: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct PluginRPCResponse: Codable, Sendable, Equatable {
    public let id: String
    public let result: JSONValue?
    public let error: PluginRPCFailure?
    public init(id: String, result: JSONValue? = nil, error: PluginRPCFailure? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }
}
