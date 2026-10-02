import BashCutPlugin
import BashCutProject
import Foundation

/// UI changes a plugin may ask for after its edit: select an item, move the playhead, open a panel.
public struct PluginUIRequest: Sendable, Equatable {
    public var select: String?
    public var selectTrack: String?
    public var seek: Int?
    public var reveal: Int?
    public var panel: String?
    public var inspector: String?

    public init(json: JSONValue?) {
        let fields = json?.object ?? [:]
        select = fields["select"]?.string
        selectTrack = fields["selectTrack"]?.string
        seek = fields["seek"]?.int.flatMap { $0 >= 0 ? $0 : nil }
        reveal = fields["reveal"]?.int.flatMap { $0 >= 0 ? $0 : nil }
        panel = fields["panel"]?.string
        inspector = fields["inspector"]?.string
    }

    public var isEmpty: Bool { self == PluginUIRequest(json: nil) }
}

/// What a plugin action or hook returns: an optional status message, files it wrote, UI requests and
/// **proposed** operations in the agent `"op"` codec. Nothing is applied here; the document validates the
/// operations like any agent edit and commits them as one undoable edit attributed to the plugin.
public struct PluginEditProposal: Sendable {
    public let message: String?
    public let label: String?
    public let operations: [EditOperation]
    public let baseRevision: Int?
    public let files: [URL]
    public let ui: PluginUIRequest
    public let result: JSONValue
    public let provenance: PluginProvenance
    /// New value for this plugin's own `pluginData` entry in the project (`.null` removes it), applied in the
    /// same undoable edit as `operations`. Other plugins' entries are never touched.
    public let pluginData: JSONValue?

    public var hasEdits: Bool { !operations.isEmpty || pluginData != nil }

    /// Parses and checks a result. `projectRoot` turns absolute media paths inside the project into
    /// project-relative ones, so plugin output in the request folder can be added with `addMedia`.
    static func parse(_ result: JSONValue, context: CapabilityContext, projectRoot: URL?) throws -> Self {
        let fields = result.object
        let message = fields["message"]?.string.map { String($0.prefix(2_000)) }
        let label = fields["label"]?.string.map { String($0.prefix(120)) }
        var operations: [EditOperation] = []
        if let value = fields["operations"] {
            guard case .array(let array) = value, array.count <= 1_000 else {
                throw PluginError.invalid("operations must be an array of at most 1000 operations")
            }
            operations = try array.map { json in
                do {
                    return try Self.relativized(EditOperation(json: json), projectRoot: projectRoot)
                } catch {
                    throw PluginError.invalid("Invalid operation: \(error.localizedDescription)")
                }
            }
        }
        var files: [URL] = []
        if let value = fields["files"] {
            guard case .array(let array) = value, array.count <= 100 else {
                throw PluginError.invalid("files must be an array of at most 100 paths")
            }
            files = try array.map { entry in
                guard let path = entry.string else { throw PluginError.invalid("files must be paths") }
                return try context.confinedOutput(path, label: "Plugin")
            }
        }
        let base = fields["baseRev"]?.int
        if let base, base < 0 { throw PluginError.invalid("baseRev must not be negative") }
        let pluginData = fields["pluginData"]
        if let pluginData, let data = try? JSONEncoder().encode(pluginData), data.count > 256 * 1024 {
            throw PluginError.invalid("pluginData must be at most 256 KiB")
        }
        return Self(
            message: message, label: label, operations: operations, baseRevision: base, files: files,
            ui: PluginUIRequest(json: fields["ui"]), result: fields["data"] ?? .null,
            provenance: context.provenance, pluginData: pluginData)
    }

    private static func relativized(_ operation: EditOperation, projectRoot: URL?) -> EditOperation {
        guard case .addMedia(var media) = operation, let projectRoot, media.path.hasPrefix("/") else { return operation }
        let root = projectRoot.standardizedFileURL.path + "/"
        let path = URL(fileURLWithPath: media.path).standardizedFileURL.path
        guard path.hasPrefix(root) else { return operation }
        media.fields["path"] = .string(String(path.dropFirst(root.count)))
        return .addMedia(media)
    }
}

/// `plugin.action`: runs one contributed action with its parameters, the plugin's option values and a
/// read-only snapshot of the editor the app chose.
public struct PluginActionCapability: CapabilityAdapter {
    public static let capability = "plugin.action"
    public let action: String
    public let params: [String: JSONValue]
    public let options: [String: JSONValue]
    public let context: JSONValue
    public let projectRoot: URL?
    public let outputRoot: URL?

    public init(
        action: String, params: [String: JSONValue], options: [String: JSONValue], context: JSONValue,
        projectRoot: URL?, outputRoot: URL?
    ) {
        self.action = action
        self.params = params
        self.options = options
        self.context = context
        self.projectRoot = projectRoot
        self.outputRoot = outputRoot
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        .object([
            "action": .string(action), "params": .object(params), "options": .object(options), "context": context,
            "outputDirectory": outputDirectory.map { .string($0.path) } ?? .null,
        ])
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> PluginEditProposal {
        try PluginEditProposal.parse(result, context: context, projectRoot: projectRoot)
    }
}

/// `plugin.hook`: tells a plugin that an editor event happened. The event already happened; the plugin
/// can only answer with a message or a proposed follow-up edit.
public struct PluginHookCapability: CapabilityAdapter {
    public static let capability = "plugin.hook"
    public let event: String
    public let payload: JSONValue
    public let options: [String: JSONValue]
    public let context: JSONValue
    public let projectRoot: URL?
    public let outputRoot: URL?

    public init(
        event: String, payload: JSONValue, options: [String: JSONValue], context: JSONValue, projectRoot: URL?,
        outputRoot: URL?
    ) {
        self.event = event
        self.payload = payload
        self.options = options
        self.context = context
        self.projectRoot = projectRoot
        self.outputRoot = outputRoot
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        .object([
            "event": .string(event), "payload": payload, "options": .object(options), "context": context,
            "outputDirectory": outputDirectory.map { .string($0.path) } ?? .null,
        ])
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> PluginEditProposal {
        try PluginEditProposal.parse(result, context: context, projectRoot: projectRoot)
    }
}

extension CapabilityService {
    /// Runs an action or hook on one named plugin (no provider resolution: contributions belong to their plugin).
    public func runContribution<Adapter: CapabilityAdapter>(
        _ adapter: Adapter, plugin: InstalledPlugin, contributionID: String,
        progress: PluginProgressHandler? = nil
    ) async throws -> Adapter.Output {
        guard availability(plugin) == .ready else {
            throw PluginError.invalid("\(plugin.manifest.displayName): \(availability(plugin).detail)")
        }
        try adapter.validate()
        if preparesPluginFolders { PluginFolders.prepare(plugin.id) }
        let directory = try adapter.outputRoot.map(Self.makeRequestDirectory)
        var succeeded = false
        defer { if !succeeded, let directory { try? FileManager.default.removeItem(at: directory) } }
        let result = try await transport.call(
            plugin: plugin, method: Adapter.capability, provider: nil,
            params: adapter.params(outputDirectory: directory), progress: progress)
        let provenance = PluginProvenance(
            pluginID: plugin.id, pluginVersion: plugin.manifest.version, providerID: contributionID)
        let output = try await adapter.output(
            from: result, context: CapabilityContext(provenance: provenance, outputDirectory: directory))
        succeeded = true
        if let directory, (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: directory)
        }
        return output
    }
}
