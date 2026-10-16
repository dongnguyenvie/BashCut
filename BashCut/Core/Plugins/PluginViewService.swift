import BashCutPlugin
import BashCutProject
import Foundation

/// Plugin views and composition (plugin API 8): `view.render`/`view.event` requests for a plugin's panel, and raw
/// capability calls one plugin makes to another (`plugins.invoke`).
extension CapabilityService {
    /// Sends a `view.render` or `view.event` request to a ready session plugin, with its option values and a host
    /// channel. The protocol is in docs/guides/plugins.md (Views).
    public func view(
        _ method: String, params: [String: JSONValue], plugin: InstalledPlugin, host: PluginHostChannel
    ) async throws -> JSONValue {
        let state = availability(plugin)
        guard state == .ready else { throw PluginError.invalid("\(plugin.manifest.displayName): \(state.detail)") }
        if preparesPluginFolders { PluginFolders.prepare(plugin.id) }
        var fields = params
        if fields["options"] == nil, let optionValues {
            fields["options"] = .object(await optionValues(plugin))
        }
        return try await transport.call(
            plugin: plugin, method: method, provider: nil, params: .object(fields), progress: nil, host: host)
    }

    /// Runs `capability` on its resolved provider with `params` as given and returns the plugin's result unchanged.
    /// The request gets the provider's option values and a fresh `outputDirectory` under `outputRoot` for files; the
    /// callee gets no host channel, so invocations cannot loop.
    public func invoke(
        _ capability: String, provider: String?, params: [String: JSONValue], projectRoot: URL?, outputRoot: URL,
        progress: PluginProgressHandler? = nil
    ) async throws -> JSONValue {
        guard ![PluginAPI.agentChat, PluginAPI.agentTerminal].contains(capability) else {
            throw PluginError.invalid("\(capability) cannot be invoked")
        }
        let resolved = try await resolve(capability, preferredProvider: provider, projectRoot: projectRoot)
        if preparesPluginFolders { PluginFolders.prepare(resolved.plugin.id) }
        let directory = try Self.makeRequestDirectory(in: outputRoot)
        var fields = params
        fields["outputDirectory"] = .string(directory.path)
        if fields["options"] == nil, let optionValues {
            fields["options"] = .object(await optionValues(resolved.plugin))
        }
        let result: JSONValue
        do {
            result = try await transport.call(
                plugin: resolved.plugin, method: capability, provider: resolved.provider.id, params: .object(fields),
                progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        // A provider that wrote no files leaves no folder behind.
        let empty = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty == true
        if empty { try? FileManager.default.removeItem(at: directory) }
        return .object([
            "plugin": .string(resolved.plugin.id), "provider": .string(resolved.provider.id),
            "outputDirectory": empty ? .null : .string(directory.path), "result": result,
        ])
    }
}
