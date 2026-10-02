import BashCutPlugin
import BashCutProject
import Foundation

/// One plugin capability (`captions.transcribe`, `audio.beats`, …): the request parameters it sends and
/// how it validates and turns the plugin's result into a typed output. `CapabilityService.run` does the
/// rest — provider resolution, the per-request output folder, the transport call and provenance — so a
/// new capability is one file conforming to this protocol plus a test.
public protocol CapabilityAdapter: Sendable {
    associatedtype Output: Sendable
    /// Capability ID in plugin manifests; also the RPC method name.
    static var capability: String { get }
    /// Folder that receives a fresh 0700 request folder for plugin output files, or nil when the
    /// plugin writes no files. The request folder is removed when the call fails.
    var outputRoot: URL? { get }
    /// Rejects a bad request before any plugin is resolved or started.
    func validate() throws
    func params(outputDirectory: URL?) -> JSONValue
    func output(from result: JSONValue, context: CapabilityContext) async throws -> Output
}

extension CapabilityAdapter {
    public var outputRoot: URL? { nil }
    public func validate() throws {}
}

/// What an adapter knows while it reads a result.
public struct CapabilityContext: Sendable {
    public let provenance: PluginProvenance
    /// The request folder, when the adapter has an `outputRoot`.
    public let outputDirectory: URL?

    /// A file the plugin reported, only if it resolves inside the request folder.
    public func confinedOutput(_ path: String, label: String) throws -> URL {
        guard let outputDirectory else { throw PluginError.invalid("\(label) has no request directory") }
        let candidate = path.hasPrefix("/") ? URL(fileURLWithPath: path) : outputDirectory.appendingPathComponent(path)
        let resolvedDirectory = outputDirectory.resolvingSymlinksInPath().standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(resolvedDirectory.path + "/"),
            FileManager.default.fileExists(atPath: resolved.path)
        else { throw PluginError.invalid("\(label) returned output outside its request directory") }
        return resolved
    }
}

extension CapabilityService {
    /// Resolves a provider for the adapter's capability and runs it.
    public func run<Adapter: CapabilityAdapter>(
        _ adapter: Adapter, preferredProvider: String?, projectRoot: URL?
    ) async throws -> Adapter.Output {
        try adapter.validate()
        let resolved = try await resolve(Adapter.capability, preferredProvider: preferredProvider, projectRoot: projectRoot)
        return try await run(adapter, using: resolved)
    }

    /// Runs the adapter on an already resolved provider (for repeated requests such as extra voice takes).
    public func run<Adapter: CapabilityAdapter>(
        _ adapter: Adapter, using resolved: ResolvedPluginProvider
    ) async throws -> Adapter.Output {
        try adapter.validate()
        if preparesPluginFolders { PluginFolders.prepare(resolved.plugin.id) }
        let directory = try adapter.outputRoot.map(Self.makeRequestDirectory)
        var succeeded = false
        defer { if !succeeded, let directory { try? FileManager.default.removeItem(at: directory) } }
        var params = adapter.params(outputDirectory: directory)
        if case .object(var fields) = params, fields["options"] == nil, let optionValues {
            let values = await optionValues(resolved.plugin)
            if !values.isEmpty {
                fields["options"] = .object(values)
                params = .object(fields)
            }
        }
        let result = try await transport.call(
            plugin: resolved.plugin, method: Adapter.capability, provider: resolved.provider.id, params: params)
        let output = try await adapter.output(
            from: result, context: CapabilityContext(provenance: PluginProvenance(resolved), outputDirectory: directory))
        succeeded = true
        return output
    }

    static func makeRequestDirectory(in outputRoot: URL) throws -> URL {
        let directory = outputRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }
}
