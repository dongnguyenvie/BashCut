import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// The plugin and capability reads (D14): `plugins.list` with health checks and plugin views on request, and
/// `capabilities.get` with the voices of the voice providers on request.
extension ProjectDocument {
    func pluginsList(_ arguments: CommandArguments) async throws -> JSONValue {
        await plugins.loadCachedRegistry()
        let category = arguments.optionalString("category").flatMap(PluginCategory.init(rawValue:))
        var result = pluginCatalogJSON(category: category).object
        if arguments.bool("health") { result["health"] = try await pluginHealthJSON(arguments.optionalString("plugin")) }
        if arguments.bool("views") { result["views"] = pluginViewsJSON() }
        return .object(result)
    }

    func capabilitiesJSON(_ arguments: CommandArguments) async throws -> JSONValue {
        let root = fileURL?.deletingLastPathComponent()
        let kind = try arguments.optionalString("kind").map {
            guard let kind = LibraryKind(rawValue: $0) else { throw RPCFailure(-32602, "Unknown kind \($0)") }
            return kind
        }
        let service = plugins.service
        if let capability = arguments.optionalString("capability") {
            let report = await service.checkedCapabilityStatus(capability, projectRoot: root, kind: kind)
            var row = Self.capabilityJSON(report).object
            if arguments.bool("voices") { row["voices"] = voiceList() }
            return .object(row)
        }
        let declared = service.catalog(projectRoot: root).plugins.flatMap { ($0.manifest.providers ?? []).map(\.capability) }
        let names = Set(CommandCatalog.capabilities.values).union(CapabilityService.serviceCapabilities).union(declared).sorted()
        let reports = await service.checkedCapabilityStatuses(names, projectRoot: root, kind: kind)
        guard arguments.bool("voices") else { return .array(reports.map(Self.capabilityJSON)) }
        return .object(["capabilities": .array(reports.map(Self.capabilityJSON)), "voices": voiceList()])
    }
}
