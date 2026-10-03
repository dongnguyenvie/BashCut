import BashCutProject
import Foundation

/// Progress a plugin reports while it works: a fraction from 0 through 1 when known, and a status line.
public typealias PluginProgressHandler = @Sendable (_ fraction: Double?, _ message: String?) -> Void

/// A failed host call, sent back to the plugin as `{"code","message"}`.
public struct PluginCallFailure: Error, Sendable, Equatable {
    public let code: Int
    public let message: String
    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// What a running session request may ask of the app (plugin API 4): `event` lines for the caller's UI, in the
/// order the plugin sent them, and `call` lines that run an app command and get its result back as `callResult`.
public struct PluginHostChannel: Sendable {
    public let event: @Sendable (JSONValue) -> Void
    public let call: @Sendable (_ method: String, _ params: JSONValue) async -> Result<JSONValue, PluginCallFailure>
    public init(
        event: @escaping @Sendable (JSONValue) -> Void,
        call: @escaping @Sendable (_ method: String, _ params: JSONValue) async -> Result<JSONValue, PluginCallFailure>
    ) {
        self.event = event
        self.call = call
    }
}

/// How a capability request reaches a plugin. `PluginProcessRunner` is the one-shot transport: one
/// isolated process per request. `PluginSessionTransport` keeps one long-lived process per plugin answering
/// many requests; `PluginRouter` picks between them from the manifest, so `CapabilityService` and its
/// adapters do not change with the transport.
public protocol PluginTransport: Sendable {
    /// Sends one JSON-RPC request and returns its `result`; plugin errors and malformed replies throw.
    func call(plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue) async throws -> JSONValue
    /// The same call, with progress reports when the transport supports them.
    func call(
        plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue,
        progress: PluginProgressHandler?
    ) async throws -> JSONValue
    // swiftlint:disable function_parameter_count
    /// The same call with a host channel; only the session transport supports one.
    func call(
        plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue,
        progress: PluginProgressHandler?, host: PluginHostChannel
    ) async throws -> JSONValue
    // swiftlint:enable function_parameter_count
    /// Probes the plugin's declared dependencies.
    func health(plugin: InstalledPlugin) async -> PluginHealth
}

extension PluginTransport {
    public func call(
        plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue,
        progress: PluginProgressHandler?
    ) async throws -> JSONValue {
        try await call(plugin: plugin, method: method, provider: provider, params: params)
    }

    // swiftlint:disable:next function_parameter_count
    public func call(
        plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue,
        progress: PluginProgressHandler?, host: PluginHostChannel
    ) async throws -> JSONValue {
        throw PluginError.invalid("\(method) needs the session transport")
    }
}

extension PluginProcessRunner: PluginTransport {}

/// Sends each request over the transport the plugin's manifest asks for.
public struct PluginRouter: PluginTransport {
    public let oneShot: PluginProcessRunner
    public let session: PluginSessionTransport

    public init(oneShot: PluginProcessRunner = PluginProcessRunner(), session: PluginSessionTransport = .shared) {
        self.oneShot = oneShot
        self.session = session
    }

    public func call(
        plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue
    ) async throws -> JSONValue {
        try await call(plugin: plugin, method: method, provider: provider, params: params, progress: nil)
    }

    public func call(
        plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue,
        progress: PluginProgressHandler?
    ) async throws -> JSONValue {
        switch plugin.manifest.transportKind {
        case .oneshot: try await oneShot.call(plugin: plugin, method: method, provider: provider, params: params)
        case .session:
            try await session.call(
                plugin: plugin, method: method, provider: provider, params: params, progress: progress)
        }
    }

    // swiftlint:disable:next function_parameter_count
    public func call(
        plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue,
        progress: PluginProgressHandler?, host: PluginHostChannel
    ) async throws -> JSONValue {
        guard plugin.manifest.transportKind == .session else {
            throw PluginError.invalid("\(method) needs the session transport")
        }
        return try await session.call(
            plugin: plugin, method: method, provider: provider, params: params, progress: progress, host: host)
    }

    public func health(plugin: InstalledPlugin) async -> PluginHealth { await oneShot.health(plugin: plugin) }
}
