import BashCutPlugin
import BashCutProject
import Foundation

/// One provider of a capability and whether it can serve now (P2-G5).
public struct CapabilityProviderStatus: Sendable, Equatable {
    public enum State: String, Sendable {
        case ready
        /// Installed but cannot run: turned off, not approved, changed, outdated or missing a required plugin.
        case notConfigured = "not_configured"
        /// May run, but its health check found a dependency missing or failing.
        case unhealthy
    }

    public let plugin: String
    public let provider: String
    public let name: String
    public let priority: Int
    public let paid: Bool
    public var state: State
    public var detail: String?

    public var json: JSONValue {
        .object([
            "plugin": .string(plugin), "provider": .string(provider), "name": .string(name),
            "priority": .integer(priority), "paid": .bool(paid), "state": .string(state.rawValue),
            "detail": detail.map(JSONValue.string) ?? .null,
        ])
    }
}

/// Whether a capability has a provider that can serve now, and if not, why (P2-G5).
public struct CapabilityReport: Sendable, Equatable {
    public enum Reason: String, Sendable {
        /// No installed plugin provides it.
        case missing
        /// Plugins provide it, but none may run.
        case notConfigured = "not_configured"
        /// Plugins may run, but every health check failed.
        case unhealthy
    }

    public let capability: String
    public let kind: LibraryKind?
    public var providers: [CapabilityProviderStatus]
    /// False when health was not checked (or the check ran out of time); `ready` then means may-run.
    public var healthChecked: Bool

    public var reason: Reason? {
        if providers.isEmpty { return .missing }
        if providers.allSatisfy({ $0.state == .notConfigured }) { return .notConfigured }
        return providers.contains { $0.state == .ready } ? nil : .unhealthy
    }

    public var available: Bool { reason == nil }

    public var json: JSONValue {
        .object([
            "capability": .string(capability), "kind": kind.map { .string($0.rawValue) } ?? .null,
            "available": .bool(available), "reason": reason.map { .string($0.rawValue) } ?? .null,
            "healthChecked": .bool(healthChecked), "providers": .array(providers.map(\.json)),
        ])
    }

    /// What `resolve` says when nothing can serve; the same words as before reports existed.
    public var message: String {
        let scope = kind.map { " for \($0.rawValue) items" } ?? ""
        switch reason {
        case .missing?: return "Install a plugin that provides \(capability)" + scope
        case .notConfigured?:
            return "No enabled provider for \(capability). "
                + providers.map { "\($0.name): \($0.detail ?? $0.state.rawValue)" }.joined(separator: "; ")
        case .unhealthy?:
            return "No healthy provider is available for \(capability). "
                + providers.compactMap { provider in provider.detail.map { "\(provider.name): \($0)" } }
                .joined(separator: "; ")
        case nil: return "\(capability) is available"
        }
    }
}

extension CapabilityReport {
    /// Runnable providers whose plugin's health check is not ready become `unhealthy`, with the failing dependencies.
    mutating func mark(_ health: [String: PluginHealth]) {
        for index in providers.indices where providers[index].state == .ready {
            guard let result = health[providers[index].plugin], result.state != .ready else { continue }
            providers[index].state = .unhealthy
            providers[index].detail = result.dependencies.filter { $0.state != .available }
                .map { "\($0.name): \($0.detail)" }.joined(separator: "; ")
        }
    }
}

private actor HealthResults {
    private(set) var values: [String: PluginHealth] = [:]
    func add(_ health: PluginHealth) { values[health.pluginID] = health }
}

/// No provider can serve a capability (P2-G5); automation reports it with category `capability_missing`.
public struct CapabilityUnavailable: LocalizedError, Sendable, Equatable {
    public let report: CapabilityReport
    public init(_ report: CapabilityReport) { self.report = report }
    public var errorDescription: String? { report.message }
}

extension CapabilityService {
    /// Capabilities BashCut calls besides a command's own (`CommandCatalog.capabilities`): forced alignment, which
    /// `captions align` prefers over transcription, review checks, chat and terminal agents. `capabilities get` lists
    /// them all even when nothing provides them.
    public static let serviceCapabilities = [
        "captions.align", PluginAPI.reviewCheck, PluginAPI.agentChat, PluginAPI.agentTerminal,
    ]

    /// Every provider of `capability` (serving `kind`) and whether it may run, without health checks.
    public func capabilityStatus(_ capability: String, projectRoot: URL?, kind: LibraryKind? = nil) -> CapabilityReport {
        let all = catalog(projectRoot: projectRoot).plugins
        let declaring = all.filter { plugin in
            (plugin.manifest.providers ?? []).contains { $0.capability == capability && (kind.map($0.serves) ?? true) }
        }
        let problems = declaring.contains { !$0.manifest.requirements.isEmpty }
            ? PluginRequirements.problems(all) { (knownAvailability($0) ?? availability($0)) == .ready } : [:]
        var providers: [CapabilityProviderStatus] = []
        for plugin in declaring {
            let state = availability(plugin)
            let problem = problems[plugin.id] ?? (state == .ready ? nil : state.detail)
            for provider in plugin.manifest.providers ?? []
            where provider.capability == capability && (kind.map(provider.serves) ?? true) {
                providers.append(CapabilityProviderStatus(
                    plugin: plugin.id, provider: provider.id, name: plugin.manifest.displayName,
                    priority: provider.priority, paid: provider.paid ?? false,
                    state: problem == nil ? .ready : .notConfigured, detail: problem))
            }
        }
        return CapabilityReport(capability: capability, kind: kind, providers: providers, healthChecked: false)
    }

    /// `capabilityStatus` with each runnable plugin's health checked in parallel. A check still running after
    /// `timeout` leaves its providers `ready` and `healthChecked` false.
    public func checkedCapabilityStatus(
        _ capability: String, projectRoot: URL?, kind: LibraryKind? = nil, timeout: Duration = .seconds(8)
    ) async -> CapabilityReport {
        await checkedCapabilityStatuses([capability], projectRoot: projectRoot, kind: kind, timeout: timeout)[0]
    }

    /// Several capabilities at once: each runnable plugin's health is checked once, in parallel, for all of them.
    public func checkedCapabilityStatuses(
        _ capabilities: [String], projectRoot: URL?, kind: LibraryKind? = nil, timeout: Duration = .seconds(8)
    ) async -> [CapabilityReport] {
        var reports = capabilities.map { capabilityStatus($0, projectRoot: projectRoot, kind: kind) }
        let runnable = Set(reports.flatMap { $0.providers.filter { $0.state == .ready }.map(\.plugin) })
        let plugins = catalog(projectRoot: projectRoot).plugins.filter { runnable.contains($0.id) }
        // Unstructured, so a slow probe cannot hold the answer past the deadline; its result is dropped.
        let results = HealthResults()
        for plugin in plugins { Task { await results.add(await health(plugin)) } }
        let deadline = ContinuousClock.now + timeout
        var checked = await results.values
        while checked.count < plugins.count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
            checked = await results.values
        }
        for index in reports.indices {
            let mine = Set(reports[index].providers.filter { $0.state == .ready }.map(\.plugin))
            reports[index].healthChecked = mine.isSubset(of: Set(checked.keys))
            reports[index].mark(checked)
        }
        return reports
    }
}
