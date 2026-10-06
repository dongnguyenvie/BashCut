import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// The plugin panels of the open project (plugin API 8, #393/#394/#399): one `PluginViewModel` per plugin view, and
/// the host channel plugin views and actions use to call app commands and other plugins' capabilities.
@MainActor final class PluginViews {
    unowned let document: ProjectDocument
    private var models: [String: PluginViewModel] = [:]
    private var sessions: [String: PluginCommandSession] = [:]
    /// Most nested `plugins.invoke` calls a request may have running at once.
    static let maximumInvokes = 4
    private var invoking: [String: Int] = [:]

    init(document: ProjectDocument) { self.document = document }

    /// Ready plugins with a rail container, in catalog order.
    var containers: [InstalledPlugin] {
        document.plugins.plugins.filter { $0.manifest.container != nil && document.plugins.isReady($0) }
    }

    func model(plugin: String, view: String) -> PluginViewModel {
        let key = plugin + "/" + view
        if let model = models[key] { return model }
        let model = PluginViewModel(document: document, pluginID: plugin, viewID: view)
        models[key] = model
        return model
    }

    /// Ends every plugin's command token and forgets views of plugins that are gone (project closed or switched).
    func reset() {
        for session in sessions.values { session.revoke(in: document.registry) }
        sessions = [:]
        models = models.filter { key, _ in containers.contains { key.hasPrefix($0.id + "/") } }
        for model in models.values { model.forget() }
    }

    // MARK: Host channel

    /// What a plugin's view or action request may ask of the app: `call` lines run an allowed app command (or
    /// `plugins.invoke`) as the plugin; `event` lines go to `onEvent` (views use `render` and `notify`).
    func hostChannel(
        for plugin: InstalledPlugin, onEvent: (@MainActor (JSONValue) -> Void)? = nil
    ) -> PluginHostChannel {
        PluginHostChannel(event: { [weak self] event in
            Task { @MainActor in
                if let onEvent { onEvent(event) } else { self?.notify(event) }
            }
        }, call: { [weak self] method, params in
            guard let self else { return .failure(PluginCallFailure(code: -32603, message: "The project closed")) }
            return await self.perform(method, params, plugin: plugin)
        })
    }

    private func notify(_ event: JSONValue) {
        if event.object["kind"]?.string == "notify", let text = event.object["text"]?.string {
            document.message = String(text.prefix(300))
        }
    }

    private func perform(
        _ method: String, _ params: JSONValue, plugin: InstalledPlugin
    ) async -> Result<JSONValue, PluginCallFailure> {
        if method == "plugins.invoke" { return await invoke(params.object, plugin: plugin) }
        let session = sessions[plugin.id] ?? PluginCommandSession()
        sessions[plugin.id] = session
        let response = await session.perform(method, params: params.object, registry: document.registry)
        if let failure = response.error { return .failure(PluginCallFailure(code: failure.code, message: failure.message)) }
        return .success(response.result ?? .null)
    }

    /// `plugins.invoke` from a plugin: only capabilities its manifest lists in `uses`.
    private func invoke(_ params: [String: JSONValue], plugin: InstalledPlugin) async -> Result<JSONValue, PluginCallFailure> {
        guard let capability = params["capability"]?.string else {
            return .failure(PluginCallFailure(code: -32602, message: "plugins.invoke needs a capability"))
        }
        guard plugin.manifest.usedCapabilities.contains(capability) else {
            return .failure(PluginCallFailure(
                code: -32601, message: "\(plugin.id) does not list \(capability) in uses"))
        }
        guard (invoking[plugin.id] ?? 0) < Self.maximumInvokes else {
            return .failure(PluginCallFailure(code: -32603, message: "Too many plugins.invoke calls at once"))
        }
        invoking[plugin.id, default: 0] += 1
        defer { invoking[plugin.id, default: 1] -= 1 }
        do {
            let result = try await document.invokeCapability(
                capability, provider: params["provider"]?.string, params: params["params"]?.object ?? [:],
                caller: plugin.id)
            return .success(result)
        } catch {
            return .failure(PluginCallFailure(code: -32603, message: error.localizedDescription))
        }
    }
}

/// One plugin view in the plugin panel: the last component tree the plugin sent, the current input values, and the
/// request queue. Requests run one at a time; a change to an input replaces a still-waiting change to the same input,
/// so typing or dragging sends only the latest value. The view renders only while it is on screen.
@MainActor @Observable final class PluginViewModel {
    unowned let document: ProjectDocument
    let pluginID: String
    let viewID: String
    private(set) var tree: PluginViewTree?
    /// Input id → value, as the user left it.
    var values: [String: JSONValue] = [:]
    private(set) var busy = false
    private(set) var error: String?
    /// Last event-time render the plugin streamed while working (`event` `{kind: "render"}`).
    private var state: JSONValue?
    @ObservationIgnored private var queue: [PluginViewEvent] = []
    @ObservationIgnored private var refresh: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    static let maximumQueue = 16

    init(document: ProjectDocument, pluginID: String, viewID: String) {
        self.document = document
        self.pluginID = pluginID
        self.viewID = viewID
    }

    var plugin: InstalledPlugin? { document.plugins.plugin(pluginID) }

    /// Whether the panel shows the view now; rendering and refresh happen only then.
    var visible = false {
        didSet {
            guard visible != oldValue else { return }
            if visible, tree == nil || error != nil { load() } else { scheduleRefresh() }
        }
    }

    func load() { Task { _ = try? await run(nil) } }

    /// Sends what the user did; returns at once (the answer redraws the view).
    func send(_ event: PluginViewEvent) {
        if event.kind == .change, let node = Optional(event.node) { values[node] = event.value }
        if busy {
            queue.removeAll { event.supersedes($0) }
            if queue.count < Self.maximumQueue { queue.append(event) }
            return
        }
        Task { _ = try? await run(event) }
    }

    /// Drops the tree and state, so the next time it shows the plugin renders it from scratch.
    func forget() {
        generation += 1
        refresh?.cancel()
        tree = nil
        state = nil
        values = [:]
        queue = []
        error = nil
    }

    /// Renders (no event) or sends `event` and waits for the new tree; for commands, which wait their turn.
    func perform(_ event: PluginViewEvent?) async throws -> PluginViewTree {
        while busy { try await Task.sleep(for: .milliseconds(30)) }
        if let event, event.kind == .change { values[event.node] = event.value }
        return try await run(event)
    }

    @discardableResult
    private func run(_ event: PluginViewEvent?) async throws -> PluginViewTree {
        guard let plugin, document.plugins.isReady(plugin) else {
            let reason = plugin.map { document.plugins.currentAvailability($0).detail } ?? "\(pluginID) is not installed"
            error = reason
            throw ProjectError.invalid(reason)
        }
        busy = true
        refresh?.cancel()
        let generation = self.generation
        defer {
            busy = false
            if let next = queue.first {
                queue.removeFirst()
                Task { _ = try? await run(next) }
            } else {
                scheduleRefresh()
            }
        }
        var params: [String: JSONValue] = [
            "view": .string(viewID), "state": state ?? .null, "values": .object(values),
            "locale": .string(LocalizedText.preferredLanguage),
            "context": document.pluginContext(plugin: plugin, parts: [], mediaID: nil, author: .user),
        ]
        if let event { params["event"] = event.json }
        let host = document.pluginViews.hostChannel(for: plugin) { [weak self] value in
            guard let self, self.generation == generation else { return }
            self.streamed(value)
        }
        do {
            let result = try await document.plugins.service.view(
                event == nil ? "view.render" : "view.event", params: params, plugin: plugin, host: host)
            let next = try PluginViewTree(parsing: result)
            guard self.generation == generation else { return next }
            apply(next, typing: event)
            return next
        } catch {
            guard self.generation == generation else { throw error }
            self.error = error.localizedDescription
            throw error
        }
    }

    private func apply(_ next: PluginViewTree, typing event: PluginViewEvent?) {
        // The plugin's values win, except an input the user is still changing (its change is waiting or just sent)
        // and inputs the plugin sent without a value.
        var merged = values
        let busyInputs = Set(queue.filter { $0.kind == .change }.map(\.node) + [event?.kind == .change ? event?.node : nil].compactMap { $0 })
        for node in next.nodes where node.kind?.isInput == true {
            if busyInputs.contains(node.id) { continue }
            if let value = node.props["value"] { merged[node.id] = value } else if merged[node.id] == nil {
                merged[node.id] = node.initialValue
            }
        }
        let ids = Set(next.inputValues.keys)
        values = merged.filter { ids.contains($0.key) }
        if let nextState = next.state { state = nextState }
        tree = next
        error = nil
        if let notify = next.notify { document.message = notify }
    }

    /// `{"kind": "render", "body": […], "title"?}` redraws while the request runs; `{"kind": "notify", "text"}` shows a
    /// status message.
    private func streamed(_ event: JSONValue) {
        switch event.object["kind"]?.string {
        case "render":
            guard let next = try? PluginViewTree(parsing: event) else { return }
            tree = PluginViewTree(title: next.title ?? tree?.title, body: next.body, state: tree?.state)
        case "notify":
            if let text = event.object["text"]?.string { document.message = String(text.prefix(300)) }
        default:
            break
        }
    }

    private func scheduleRefresh() {
        refresh?.cancel()
        guard visible, let seconds = tree?.refreshSeconds else { return }
        refresh = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.visible, !self.busy else { return }
            _ = try? await self.run(nil)
        }
    }
}
