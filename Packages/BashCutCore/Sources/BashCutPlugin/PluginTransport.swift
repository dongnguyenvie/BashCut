import BashCutProject
import Foundation

/// How a capability request reaches a plugin. `PluginProcessRunner` is the one-shot transport: one
/// isolated process per request. A session transport (one long-lived process per plugin answering many
/// requests) conforms the same way, so `CapabilityService` and its adapters do not change with it.
public protocol PluginTransport: Sendable {
    /// Sends one JSON-RPC request and returns its `result`; plugin errors and malformed replies throw.
    func call(plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue) async throws -> JSONValue
    /// Probes the plugin's declared dependencies.
    func health(plugin: InstalledPlugin) async -> PluginHealth
}

extension PluginProcessRunner: PluginTransport {}
