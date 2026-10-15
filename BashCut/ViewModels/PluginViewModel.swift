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
    /// View updates plugins send outside a request (#409).
    private var updates: PluginViewUpdates.Subscription?
    /// Views in windows of their own (API 11).
    private(set) lazy var windows = PluginViewWindows(document: document)

    init(document: ProjectDocument) {
        self.document = document
        updates = PluginViewUpdates.shared.subscribe { [weak self] update in
            Task { @MainActor in self?.pushed(update) }
        }
    }

    /// A view update outside a request: drawn only in a view on screen of a ready plugin; others are dropped. An
    /// overlay set (#407) replaces the plugin's overlays; a bad one is dropped (the host call reports why).
    private func pushed(_ update: PluginViewUpdate) {
        guard let view = update.view else {
            guard let plugin = document.plugins.plugin(update.pluginID), document.plugins.isReady(plugin),
                let overlays = try? PluginOverlay.parse(update.answer.object["overlays"] ?? .null)
            else { return }
            document.ui.setPluginOverlays(plugin.id, overlays)
            return
        }
        guard let model = models[update.pluginID + "/" + view], model.visible,
            let plugin = document.plugins.plugin(update.pluginID), document.plugins.isReady(plugin)
        else { return }
        model.pushed(update.answer)
    }

    /// Ready plugins with a rail container, in catalog order.
    var containers: [InstalledPlugin] {
        document.plugins.plugins.filter {
            $0.manifest.container != nil && document.plugins.isReady($0) && !document.plugins.isHidden($0)
        }
    }

    /// Ready plugins with a rail container or any view, for `plugins list --views`.
    var viewPlugins: [InstalledPlugin] {
        document.plugins.plugins.filter {
            ($0.manifest.container != nil || !$0.manifest.views.isEmpty) && document.plugins.isReady($0)
        }
    }

    /// Views of ready plugins that live in the agent dock, as `(key, plugin, view)`.
    var dockViews: [(key: String, plugin: InstalledPlugin, view: PluginViewContribution)] {
        document.plugins.plugins.filter { document.plugins.isReady($0) && !document.plugins.isHidden($0) }.flatMap { plugin in
            plugin.manifest.views.filter { $0.place == .dock }.map { (plugin.id + "/" + $0.id, plugin, $0) }
        }
    }

    /// Tool views (`kind: tool`) of ready plugins that the Tools panel lists, as `(key, plugin, view)`.
    var toolViews: [(key: String, plugin: InstalledPlugin, view: PluginViewContribution)] {
        document.plugins.plugins.filter { document.plugins.isReady($0) && !document.plugins.isHidden($0) }.flatMap { plugin in
            plugin.manifest.views.filter { $0.place == .panel && $0.isTool }.map { (plugin.id + "/" + $0.id, plugin, $0) }
        }
    }

    /// Views of ready plugins that live in the Inspector, as `(key, plugin, view)`.
    var inspectorViews: [(key: String, plugin: InstalledPlugin, view: PluginViewContribution)] {
        document.plugins.plugins.filter { document.plugins.isReady($0) && !document.plugins.isHidden($0) }.flatMap { plugin in
            plugin.manifest.views.filter { $0.place == .inspector }.map { (plugin.id + "/" + $0.id, plugin, $0) }
        }
    }

    /// The model for `<plugin>/<view>` while that plugin is ready and has the view.
    func model(key: String) -> PluginViewModel? {
        guard let (plugin, view) = resolve(key) else { return nil }
        return model(plugin: plugin.id, view: view.id)
    }

    /// The ready plugin and view a `<plugin>/<view>` key names.
    func resolve(_ key: String) -> (InstalledPlugin, PluginViewContribution)? {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let plugin = document.plugins.plugin(parts[0]), document.plugins.isReady(plugin),
            let view = plugin.manifest.views.first(where: { $0.id == parts[1] })
        else { return nil }
        return (plugin, view)
    }

    /// The model for `key` if one was made, without making one.
    func existingModel(key: String) -> PluginViewModel? { models[key] }

    /// Shows a view where it lives: the plugin's rail panel, its dock tab (opening the dock), a sheet or its window.
    func show(_ plugin: InstalledPlugin, view: PluginViewContribution) {
        let key = plugin.id + "/" + view.id
        DebugLog.write("ui", "plugin view \(key) in \(view.place.rawValue)")
        switch view.place {
        case .panel where view.isTool: document.showTool(key)
        case .panel: document.showPluginPanel(plugin.id, view: view.id)
        case .dock:
            document.ui.showAgentDock = true
            document.agents.pluginViewKey = key
        case .sheet: document.ui.pluginSheet = key
        case .window: windows.open(key)
        // The Inspector is always on screen; its plugin views follow the selection, so there is nothing to open.
        case .inspector: break
        }
    }

    /// Closes the sheet or window that shows `model`'s view (a plugin answered `close`).
    func closeSheet(of model: PluginViewModel) {
        let key = model.pluginID + "/" + model.viewID
        if document.ui.pluginSheet == key { document.ui.pluginSheet = nil }
        if document.ui.pluginWindows.contains(key) || document.ui.dockedPluginView == key { windows.close(key) }
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
        windows.closeAll()
        document.ui.clearPluginOverlays()
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
        if method == "cli" {
            // A command from its command-line words, handled exactly like a direct call of it.
            do {
                let command = try PluginCommandSession.commandLine(params.object)
                return await perform(command.method, .object(command.params), plugin: plugin)
            } catch let failure as RPCFailure {
                return .failure(PluginCallFailure(code: failure.code, message: failure.message))
            } catch {
                return .failure(PluginCallFailure(code: -32602, message: error.localizedDescription))
            }
        }
        if let refusal = PluginCommandSession.ownPluginRefusal(method, params: params.object, caller: plugin.id) {
            return .failure(PluginCallFailure(code: -32601, message: refusal))
        }
        if method == "plugins.option" { return setOwnOption(params.object, plugin: plugin) }
        let session = sessions[plugin.id] ?? PluginCommandSession()
        sessions[plugin.id] = session
        let response = await session.perform(method, params: params.object, registry: document.registry)
        if let failure = response.error { return .failure(PluginCallFailure(code: failure.code, message: failure.message)) }
        return .success(response.result ?? .null)
    }

    /// `plugins.option` from a plugin for one of its own options (#411): never a secret; user-scope values are saved
    /// for this Mac, project-scope values are an undoable project edit by author `plugin`. Answers like the command.
    private func setOwnOption(_ params: [String: JSONValue], plugin: InstalledPlugin) -> Result<JSONValue, PluginCallFailure> {
        guard let id = params["option"]?.string,
            let option = (plugin.manifest.options ?? []).first(where: { $0.id == id })
        else {
            return .failure(PluginCallFailure(
                code: -32602, message: "Unknown option \(params["option"]?.string ?? "") for \(plugin.id)"))
        }
        do {
            let value = try PluginOptionPolicy.ownValue(params["value"], for: option)
            try document.setPluginOption(plugin, option: id, value: value, author: .plugin, ownPlugin: true)
            return .success(.object([
                "value": document.pluginOptionValues(plugin)[id] ?? .null, "rev": .integer(document.project.revision),
            ]))
        } catch {
            return .failure(PluginCallFailure(code: -32602, message: error.localizedDescription))
        }
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
    /// The opaque `state` the plugin returned last, sent back with the next request.
    private var state: JSONValue?
    @ObservationIgnored private var queue: [PluginViewEvent] = []
    @ObservationIgnored private var refresh: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// The newest streamed render not drawn yet, and whether a draw is scheduled.
    @ObservationIgnored private var streamedRender: JSONValue?
    @ObservationIgnored private var streamFlush: Task<Void, Never>?
    /// The newest view update sent outside a request (#409) not drawn yet, and whether a draw is scheduled.
    @ObservationIgnored private var pushedAnswer: JSONValue?
    @ObservationIgnored private var pushFlush: Task<Void, Never>?
    static let maximumQueue = 16
    /// Streamed renders are drawn at most this often; the ones in between are skipped.
    static let streamInterval: Duration = .milliseconds(60)

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
            if visible, !following, tree == nil || error != nil { load() } else { scheduleRefresh() }
        }
    }

    /// An Inspector view (#405) follows the selection: the newest selection renders after `selectionDebounce` without
    /// a newer one, and a render still running for an older selection is cancelled.
    @ObservationIgnored private let follow = PluginLatestRequest()
    @ObservationIgnored private var following = false
    static let selectionDebounce: Duration = .milliseconds(120)

    /// The Inspector shows another item (or the same item's media changed): forget the old answer and render for the
    /// new selection, at once when the view just appeared. `matches` false (the view's `when` fails): show nothing
    /// and ask the plugin nothing.
    func followSelection(matches: Bool) {
        let first = !visible
        forget()
        following = true
        visible = true
        guard matches else {
            follow.cancel()
            return
        }
        follow.schedule(after: first ? .zero : Self.selectionDebounce) { [weak self] in
            _ = try? await self?.run(nil)
        }
    }

    /// The Inspector no longer shows the view.
    func stopFollowing() {
        follow.cancel()
        following = false
        visible = false
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
        dropStreamedRender()
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
            let started = DispatchTime.now().uptimeNanoseconds
            let result = try await document.plugins.service.view(
                event == nil ? "view.render" : "view.event", params: params, plugin: plugin, host: host)
            let answered = DispatchTime.now().uptimeNanoseconds
            let next = try await Self.parse(result)
            guard self.generation == generation else { return next }
            dropStreamedRender()
            apply(next, typing: event)
            let applied = DispatchTime.now().uptimeNanoseconds
            DebugLog.write("plugin", "view \(pluginID)/\(viewID) \(event?.kind.rawValue ?? "render"): plugin "
                + "\((answered - started) / 1_000_000) ms, parse+apply \((applied - answered) / 1_000) µs, "
                + "\(next.nodes.count) components")
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
        if next.close { document.pluginViews.closeSheet(of: self) }
    }

    private func dropStreamedRender() {
        streamFlush?.cancel()
        streamFlush = nil
        streamedRender = nil
        pushFlush?.cancel()
        pushFlush = nil
        pushedAnswer = nil
    }

    /// A view answer the plugin sent outside a request (#409), drawn at most every `streamInterval` like streamed
    /// renders (the ones in between are skipped). While a request runs it only redraws, like a streamed render; its
    /// answer then decides the values and state.
    func pushed(_ answer: JSONValue) {
        pushedAnswer = answer
        guard pushFlush == nil else { return }
        let generation = self.generation
        pushFlush = Task { [weak self] in
            try? await Task.sleep(for: Self.streamInterval)
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            self.pushFlush = nil
            guard let answer = self.pushedAnswer else { return }
            self.pushedAnswer = nil
            guard let next = try? await Self.parse(answer), self.generation == generation, self.visible else { return }
            if self.busy {
                self.tree = PluginViewTree(title: next.title ?? self.tree?.title, body: next.body, state: self.tree?.state)
            } else {
                self.apply(next, typing: nil)
            }
        }
    }

    /// Reads an answer off the main actor (a large view takes milliseconds to check).
    private nonisolated static func parse(_ result: JSONValue) async throws -> PluginViewTree {
        try PluginViewTree(parsing: result)
    }

    /// `{"kind": "render", "body": […], "title"?}` redraws while the request runs, at most every `streamInterval`
    /// (a plugin that streams hundreds would otherwise redraw the panel for each); `{"kind": "notify", "text"}` shows
    /// a status message.
    private func streamed(_ event: JSONValue) {
        switch event.object["kind"]?.string {
        case "render":
            streamedRender = event
            guard streamFlush == nil else { return }
            let generation = self.generation
            streamFlush = Task { [weak self] in
                try? await Task.sleep(for: Self.streamInterval)
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                self.streamFlush = nil
                guard let event = self.streamedRender, let next = try? await Self.parse(event) else { return }
                self.streamedRender = nil
                guard !Task.isCancelled, self.generation == generation, self.busy else { return }
                self.tree = PluginViewTree(title: next.title ?? self.tree?.title, body: next.body, state: self.tree?.state)
            }
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
