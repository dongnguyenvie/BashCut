import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// Plugin panels, their views and capability calls between plugins (plugin API 8, #393–#396, #399).
extension ProjectDocument {
    /// Shows a plugin's panel in the library column, on `view` when given.
    func showPluginPanel(_ pluginID: String, view: String? = nil) {
        DebugLog.write("ui", "plugin panel \(pluginID)\(view.map { " view \($0)" } ?? "")")
        if let view { ui.pluginPanelViews[pluginID] = view }
        ui.pluginPanel = pluginID
        ui.showLibraryPanel = true
    }

    /// Shows the Tools panel on `id` (a `ToolID`, `<plugin>/<view>` or a tool action's id), revealing the panel column.
    func showTool(_ id: String) {
        DebugLog.write("ui", "tool \(id)")
        ui.selectedTool = id
        showLibraryTab(.tools)
    }

    /// Shows a built-in library panel, revealing the panel column if it was hidden.
    func showLibraryTab(_ tab: LibraryTab) {
        DebugLog.write("ui", "library panel \(ui.libraryTab.rawValue) → \(tab.rawValue)")
        ui.libraryTab = tab
        ui.pluginPanel = nil
        ui.showLibraryPanel = true
    }

    /// The view a plugin's panel shows: the chosen one while the plugin still has it, else its first view.
    func pluginPanelView(_ plugin: InstalledPlugin) -> PluginViewContribution? {
        let views = plugin.manifest.views.filter { $0.place == .panel && !$0.isTool }
        return views.first { $0.id == ui.pluginPanelViews[plugin.id] } ?? views.first
    }

    /// Grid tiles with `drag: "download"` dropped on the timeline (API 11): each view gets a `drag` event for its tile,
    /// downloads it and answers with the library item (`libraryItem`), which is placed where the tile was dropped.
    func placeDroppedPluginDownloads(_ downloads: [PluginViewDrag.Download], at frame: Int, overTrack trackID: String?) {
        Task {
            var references: [String] = []
            for download in downloads {
                guard let model = pluginViews.model(key: download.key) else { continue }
                DebugLog.write("plugin", "drag download \(download.key) \(download.item)")
                message = String(localized: "Downloading…")
                do {
                    let answer = try await model.perform(PluginViewEvent(
                        node: download.node, kind: .drag, value: .object(["item": .string(download.item)])))
                    guard let reference = answer.libraryItem else {
                        message = String(format: String(localized: "%@ did not add the item to the library"),
                                         model.plugin?.manifest.displayName ?? download.plugin)
                        continue
                    }
                    references.append(reference)
                } catch {
                    message = error.localizedDescription
                }
            }
            if !references.isEmpty {
                if message == String(localized: "Downloading…") { message = "" }
                placeDroppedLibraryItems(references, at: frame, overTrack: trackID)
            }
        }
    }

    /// Capabilities the plugin lists in `uses` that no ready plugin provides.
    func unprovidedCapabilities(_ plugin: InstalledPlugin) -> [String] {
        let provided = Set(plugins.plugins.filter { plugins.isReady($0) }.flatMap { ($0.manifest.providers ?? []).map(\.capability) })
        return plugin.manifest.usedCapabilities.filter { !provided.contains($0) }
    }

    /// Runs a capability with raw parameters (`plugins.invoke`). Output files go to a fresh folder under the
    /// project's `generated/plugins/<caller>/invoke`, or the caller's cache folder without a saved project.
    func invokeCapability(
        _ capability: String, provider: String?, params: [String: JSONValue], caller: String,
        progress: PluginProgressHandler? = nil
    ) async throws -> JSONValue {
        let root = fileURL?.deletingLastPathComponent()
        let outputRoot = root.map { $0.appendingPathComponent("generated/plugins/\(caller)/invoke", isDirectory: true) }
            ?? PluginFolders.cache(caller).appendingPathComponent("invoke", isDirectory: true)
        DebugLog.write("plugin", "invoke \(capability) by \(caller)")
        let service = plugins.service
        return try await plugins.running(capability) {
            try await service.invoke(
                capability, provider: provider, params: params, projectRoot: root, outputRoot: outputRoot,
                progress: progress)
        }
    }

    /// Whether a view is on screen where it lives.
    func isShowing(_ key: String, _ place: PluginViewLocation, plugin: InstalledPlugin) -> Bool {
        switch place {
        case .panel where plugin.manifest.views.contains { $0.isTool && plugin.id + "/" + $0.id == key }:
            ui.showLibraryPanel && ui.pluginPanel == nil && ui.libraryTab == .tools && ui.selectedTool == key
        case .panel: ui.pluginPanel == plugin.id && pluginPanelView(plugin).map { plugin.id + "/" + $0.id } == key
        case .dock: ui.showAgentDock && !agents.isDetached && agents.pluginViewKey == key
        case .sheet: ui.pluginSheet == key
        case .window: ui.pluginWindows.contains(key) || ui.dockedPluginView == key
        case .inspector: selectedItems.count == 1
        }
    }

    func pluginPanelJSON(_ plugin: InstalledPlugin) -> JSONValue {
        let unprovided = Set(unprovidedCapabilities(plugin))
        return .object([
            "plugin": .string(plugin.id), "name": .string(plugin.manifest.displayName),
            "title": .string(plugin.manifest.containerTitle),
            "icon": plugin.manifest.container.map { .string($0.icon) } ?? .null,
            "version": .string(plugin.manifest.version),
            "views": .array(plugin.manifest.views.map { view in
                .object(["id": .string(view.id), "title": .string(view.title.text), "location": .string(view.place.rawValue),
                         "shown": .bool(isShowing(plugin.id + "/" + view.id, view.place, plugin: plugin))])
            }),
            "tools": .array(plugins.actions.filter { $0.plugin.id == plugin.id }.map { action in
                .object(["id": .string(action.id), "title": .string(action.title), "available": .bool(canRunPluginAction(action))])
            }),
            "skills": .array(plugins.skills(of: plugin).map { .string($0.id) }),
            "requires": plugins.requirementsJSON(plugin),
            "uses": .array(plugin.manifest.usedCapabilities.map { capability in
                .object(["capability": .string(capability), "provided": .bool(!unprovided.contains(capability))])
            }),
            "open": .bool(ui.pluginPanel == plugin.id),
            "view": pluginPanelView(plugin).map { .string($0.id) } ?? .null,
        ])
    }

    /// A ready plugin with views or a panel, or a clear error.
    private func panelPlugin(_ id: String) throws -> InstalledPlugin {
        let plugin = try requirePlugin(id)
        guard plugin.manifest.container != nil || !plugin.manifest.views.isEmpty else {
            throw RPCFailure(-32602, "\(id) has no views; see plugins list --views")
        }
        guard plugins.isReady(plugin) else {
            throw RPCFailure(
                -32003, "\(plugin.manifest.displayName): \(plugins.currentAvailability(plugin).detail)", category: .notAvailableNow)
        }
        return plugin
    }

    private func viewModel(_ plugin: InstalledPlugin, _ arguments: CommandArguments) throws -> PluginViewModel {
        let views = plugin.manifest.views
        let id = arguments.optionalString("view") ?? views.first?.id
        guard let id, views.contains(where: { $0.id == id }) else {
            throw RPCFailure(-32602, "\(plugin.id) has no view \(arguments.optionalString("view") ?? "")")
        }
        return pluginViews.model(plugin: plugin.id, view: id)
    }

    private static func viewJSON(_ plugin: InstalledPlugin, _ model: PluginViewModel, _ tree: PluginViewTree) -> JSONValue {
        var fields = tree.json.object
        fields["plugin"] = .string(plugin.id)
        fields["view"] = .string(model.viewID)
        fields["values"] = .object(model.values)
        return .object(fields)
    }

    /// A value from the command line: JSON when it parses, else the text.
    private static func eventValue(_ text: String?) -> JSONValue {
        guard let text else { return .null }
        if let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) { return value }
        return .string(text)
    }

    /// Plugins with panels or views, the open panel, sheet and windows, and the host's plugin features (`plugins.list --views`).
    func pluginViewsJSON() -> JSONValue {
        .object([
            "panels": .array(pluginViews.viewPlugins.map(pluginPanelJSON)),
            "sheet": ui.pluginSheet.map(JSONValue.string) ?? .null,
            "windows": .array(ui.pluginWindows.sorted().map(JSONValue.string)),
            "docked": ui.dockedPluginView.map(JSONValue.string) ?? .null,
            "open": ui.pluginPanel.map(JSONValue.string) ?? .null,
            "features": .array(PluginFeature.all.map(JSONValue.string)),
            "apiVersion": .integer(PluginAPI.current),
        ])
    }

    func registerPluginViewCommands() {
        handleAuthored("plugins.view") { document, arguments, _ in
            let plugin = try document.panelPlugin(arguments.string("plugin"))
            let model = try document.viewModel(plugin, arguments)
            if arguments.bool("open"), let view = plugin.manifest.views.first(where: { $0.id == model.viewID }) {
                document.pluginViews.show(plugin, view: view)
            }
            do {
                return Self.viewJSON(plugin, model, try await model.perform(nil))
            } catch { throw RPCFailure(-32603, error.localizedDescription) }
        }
        registerPluginOverlayCommands()
        handleAuthored("plugins.show-view") { document, arguments, _ in
            let plugin = try document.panelPlugin(arguments.string("plugin"))
            let id = try arguments.string("view")
            guard let view = plugin.manifest.views.first(where: { $0.id == id }) else {
                throw RPCFailure(-32602, "\(plugin.id) has no view \(id)")
            }
            document.pluginViews.show(plugin, view: view)
            return .object(["plugin": .string(plugin.id), "view": .string(id), "location": .string(view.place.rawValue)])
        }
        handleAuthored("plugins.view-event") { document, arguments, _ in
            let plugin = try document.panelPlugin(arguments.string("plugin"))
            let model = try document.viewModel(plugin, arguments)
            let kind = PluginViewEvent.Kind(rawValue: arguments.optionalString("type") ?? "click") ?? .click
            let node = try arguments.string("node")
            if model.tree == nil { _ = try? await model.perform(nil) }
            guard let component = model.tree?.node(node) else {
                throw RPCFailure(-32602, "The view has no component \(node); see plugins view")
            }
            guard component.kind?.isInteractive == true, !component.bool("disabled") else {
                throw RPCFailure(-32602, "\(node) is not an enabled button, input, list or grid")
            }
            let event = PluginViewEvent(node: node, kind: kind, value: Self.eventValue(arguments["value"]?.string))
            do {
                return Self.viewJSON(plugin, model, try await model.perform(event))
            } catch { throw RPCFailure(-32603, error.localizedDescription) }
        }
        handleAuthored("plugins.invoke") { document, arguments, author in
            let capability = try arguments.string("capability")
            let provider = arguments.optionalString("provider")
            let params = arguments["params"]?.object ?? [:]
            let start: @MainActor () -> String? = { [weak document] in
                document?.jobs.start("plugins.invoke", author: author, detail: capability, work: { [weak document] reporter in
                    guard let document else { throw CancellationError() }
                    return try await document.invokeCapability(
                        capability, provider: provider, params: params, caller: "cli"
                    ) { fraction, text in
                        Task { @MainActor in
                            if let fraction { reporter.progress(fraction, detail: text) } else if let text { reporter.detail(text) }
                        }
                    }
                })
            }
            let job = start() ?? ""
            // A graphic being rendered shows as a placeholder where it lands (#534).
            document.trackGraphicPlaceholder(job, capability: capability, params: params, retry: start)
            return .object(["job": .string(job), "state": .string("running")])
        }
    }
}

extension ProjectDocument {
    /// `plugins.overlays` and `plugins.set-overlays` (#407).
    func registerPluginOverlayCommands() {
        handle("plugins.overlays") { document, arguments, _ in
            let only = arguments.optionalString("plugin")
            let sets = document.ui.pluginOverlaySets.filter { only == nil || $0.key == only }
            return .object(sets.mapValues { .array($0.map(\.json)) })
        }
        handleAuthored("plugins.set-overlays") { document, arguments, _ in
            let plugin = try document.requirePlugin(arguments.string("plugin"))
            let overlays: [PluginOverlay]
            let value = try arguments.value("overlays")
            do { overlays = try PluginOverlay.parse(value) } catch {
                throw RPCFailure(-32602, error.localizedDescription)
            }
            guard overlays.isEmpty || document.plugins.isReady(plugin) else {
                throw RPCFailure(-32003, "\(plugin.manifest.displayName) is not ready", category: .notAvailableNow)
            }
            document.ui.setPluginOverlays(plugin.id, overlays)
            return .object(["plugin": .string(plugin.id), "overlays": .integer(overlays.count)])
        }
    }
}
