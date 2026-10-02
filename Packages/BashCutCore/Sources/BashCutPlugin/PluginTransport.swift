import BashCutProject
import Foundation

/// Progress a plugin reports while it works: a fraction from 0 through 1 when known, and a status line.
public typealias PluginProgressHandler = @Sendable (_ fraction: Double?, _ message: String?) -> Void

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

    public func health(plugin: InstalledPlugin) async -> PluginHealth { await oneShot.health(plugin: plugin) }
}
