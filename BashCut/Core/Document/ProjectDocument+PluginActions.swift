import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// An action waiting in its parameter sheet.
struct PendingPluginAction: Identifiable {
    let id = UUID()
    let action: ContributedAction
    var values: [String: JSONValue]
    let mediaID: String?
    let author: Author
}

/// Plugin actions: the menus, buttons and context-menu entries plugins declare. The UI, `ui.action` and
/// `plugins.run` all end in `runPluginAction`, and every result goes through `applyPluginProposal`, so a
/// plugin edit is validated, undoable and attributed like an agent edit.
extension ProjectDocument {
    // MARK: Conditions and context

    /// Facts `when` expressions test: project, selection, track, media, timeline, playing, source.
    func pluginFacts(mediaID: String? = nil) -> [String: String] {
        var facts: [String: String] = [:]
        if fileURL != nil { facts["project"] = "true" }
        if project.duration > 0 { facts["timeline"] = "true" }
        if preview.isPlaying { facts["playing"] = "true" }
        if sourceViewer.visible, sourceViewer.media != nil { facts["source"] = "true" }
        if let item = selected, let track = selectedItemTrack {
            facts["selection"] = "true"
            facts["selection.kind"] = track.kind
            facts["selection.role"] = track.role
            if let media = item.mediaID.flatMap({ id in project.media.first { $0.id == id } }) {
                facts["media"] = "true"
                facts["media.kind"] = media.kind
            }
        }
        if let track = selectedTrackID.flatMap({ id in project.tracks.first { $0.id == id } }) {
            facts["track"] = "true"
            facts["track.kind"] = track.kind
            facts["track.role"] = track.role
        }
        if let media = mediaID.flatMap({ id in project.media.first { $0.id == id } }) {
            facts["media"] = "true"
            facts["media.kind"] = media.kind
        }
        return facts
    }

    func canRunPluginAction(_ action: ContributedAction, mediaID: String? = nil) -> Bool {
        guard !busy, fileURL != nil, !conflict, !plugins.calling.contains(action.id) else { return false }
        return action.when?.evaluate(pluginFacts(mediaID: mediaID)) ?? true
    }

    /// The read-only editor snapshot sent with an action or hook. `parts` adds the whole timeline, all media
    /// or the project document.
    func pluginContext(
        plugin: InstalledPlugin, parts: [PluginActionContribution.ContextPart], mediaID: String? = nil,
        author: Author
    ) -> JSONValue {
        let root = fileURL?.deletingLastPathComponent()
        func mediaJSON(_ media: Media) -> JSONValue {
            var fields = media.fields
            if let root, let url = try? MediaPathResolver.resolve(media.path, projectRoot: root, workspaceRoot: settings.workspace) {
                fields["absolutePath"] = .string(url.path)
            }
            return .object(fields)
        }
        var context: [String: JSONValue] = [
            "app": .object([
                "apiVersion": .integer(PluginAPI.current), "language": .string(PluginText.language),
                "version": .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"),
            ]),
            "author": .string(author.rawValue),
            "project": .object([
                "path": fileURL.map { .string($0.path) } ?? .null, "root": root.map { .string($0.path) } ?? .null,
                "name": .string(project.name), "rev": .integer(project.revision), "fps": project.fps.json,
                "width": .integer(project.width), "height": .integer(project.height),
                "duration": .integer(project.duration), "contentLanguage": .string(contentLanguage),
            ]),
            "playhead": .integer(playhead),
            "pluginData": project["pluginData"]?.object[plugin.id] ?? .null,
        ]
        if let item = selected {
            var fields = item.fields
            fields["track"] = selectedItemTrack.map { .string($0.id) } ?? .null
            context["selection"] = .object(fields)
        }
        if let track = selectedTrackID.flatMap({ id in project.tracks.first { $0.id == id } }) {
            context["selectedTrack"] = .object([
                "id": .string(track.id), "kind": .string(track.kind), "role": .string(track.role),
                "name": .string(track.name),
            ])
        }
        let mediaTarget = mediaID ?? selected?.mediaID
        if let media = mediaTarget.flatMap({ id in project.media.first { $0.id == id } }) {
            context["media"] = mediaJSON(media)
        }
        if parts.contains(.timeline) { context["tracks"] = project["tracks"] ?? .array([]) }
        if parts.contains(.media) { context["allMedia"] = .array(project.media.map(mediaJSON)) }
        if parts.contains(.project) { context["document"] = .object(project.fields) }
        return .object(context)
    }

    /// Option values for a plugin: project values over user values over defaults. Secrets are only included when
    /// `revealSecrets` is set (requests to the plugin); otherwise each shows as `{"set": true|false}`.
    func pluginOptionValues(_ plugin: InstalledPlugin, revealSecrets: Bool = false) -> [String: JSONValue] {
        let options = plugin.manifest.options ?? []
        let user = plugins.trust.userOptions(plugin)
        let projectValues = project["pluginOptions"]?.object[plugin.id]?.object ?? [:]
        var values: [String: JSONValue] = [:]
        let root = fileURL?.deletingLastPathComponent()
        for option in options {
            if option.type == .secret {
                let identity = try? plugins.trust.credentialIdentity(for: plugin)
                let secret = identity.map {
                    plugins.secrets.read(plugin: $0, option: option.id,
                                         binding: PluginOptionPolicy.secretBinding(options: options, userValues: user))
                } ?? ""
                values[option.id] = revealSecrets ? .string(secret) : .object(["set": .bool(!secret.isEmpty)])
                continue
            }
            let stored = PluginOptionPolicy.scope(of: option, in: options) == .project ? projectValues[option.id] : user[option.id]
            var value = stored.flatMap { try? option.check($0) } ?? option.fallback
            // File options in a project are stored relative to it; plugins always get absolute paths.
            if option.type == .file, let path = value.string, !path.isEmpty, !path.hasPrefix("/"), let root {
                value = .string(root.appendingPathComponent(path).standardizedFileURL.path)
            }
            values[option.id] = value
        }
        return values
    }

    func setPluginOption(_ plugin: InstalledPlugin, option id: String, value: JSONValue?, author: Author) throws {
        let options = plugin.manifest.options ?? []
        try PluginOptionPolicy.validateEdit(options: options, author: author)
        guard let option = options.first(where: { $0.id == id }) else {
            throw ProjectError.invalid("Unknown option \(id) for \(plugin.id)")
        }
        if option.type == .secret {
            guard author == .user else { throw ProjectError.invalid("Set secrets in Settings") }
            let text = try value.map(option.check)?.string ?? ""
            let identity = try plugins.trust.credentialIdentity(for: plugin)
            try plugins.secrets.write(
                text, plugin: identity, option: id,
                binding: PluginOptionPolicy.secretBinding(options: options, userValues: plugins.trust.userOptions(plugin)))
            plugins.secrets.removeStale(option: id, prefix: plugin.installationID + "@", keeping: identity)
            return
        }
        var checked = try value.map(option.check)
        if option.type == .file, PluginOptionPolicy.scope(of: option, in: options) == .project, let path = checked?.string, path.hasPrefix("/"),
            let root = fileURL?.deletingLastPathComponent()
        {
            checked = .string(MediaPathResolver.projectPath(for: URL(fileURLWithPath: path), projectRoot: root))
        }
        switch PluginOptionPolicy.scope(of: option, in: options) {
        case .user:
            try plugins.trust.setUserOption(plugin, key: id, value: checked)
        case .project:
            var all = project["pluginOptions"]?.object ?? [:]
            var mine = all[plugin.id]?.object ?? [:]
            mine[id] = checked
            all[plugin.id] = mine.isEmpty ? nil : .object(mine)
            try commit(
                .setProjectProperties(patch: ["pluginOptions": .object(all)]),
                label: "Plugin option \(option.title)", author: author, coalescingKey: "plugin-option.\(plugin.id).\(id)")
        }
    }

    // MARK: Running actions

    /// Starts an action from the UI: collects parameters, then the shared execution path asks for confirmation.
    func triggerPluginAction(_ action: ContributedAction, mediaID: String? = nil, author: Author = .user) {
        guard canRunPluginAction(action, mediaID: mediaID) else {
            message = String(format: String(localized: "%@ is not available now"), action.title)
            return
        }
        if !action.params.isEmpty {
            let defaults = (try? action.params.resolve([:])) ?? [:]
            plugins.pendingAction = PendingPluginAction(action: action, values: defaults, mediaID: mediaID, author: author)
            return
        }
        startPluginActionJob(action.id, params: [:], mediaID: mediaID, author: author)
    }

    /// Runs the action in the background; `jobs.status` reports it.
    @discardableResult
    func startPluginActionJob(
        _ id: String, params: [String: JSONValue], mediaID: String? = nil, author: Author
    ) -> String {
        let title = plugins.action(id)?.title ?? id
        plugins.lastRun[id] = Date()
        message = String(format: String(localized: "Running %@…"), title)
        return jobs.start("plugins.run", author: author, detail: id, work: { [weak self] reporter in
            guard let self else { throw CancellationError() }
            return try await runPluginAction(id, params: params, mediaID: mediaID, author: author) { fraction, text in
                Task { @MainActor in
                    if let fraction { reporter.progress(fraction, detail: text) } else if let text { reporter.detail(text) }
                }
            }
        }, finished: { [weak self] outcome in
            guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
            self?.message = title + ": " + error.localizedDescription
        })
    }

    /// Runs one action and applies its proposal. Returns the new revision and the plugin's `data`.
    func runPluginAction(
        _ id: String, params: [String: JSONValue], mediaID: String? = nil, author: Author,
        progress: PluginProgressHandler? = nil
    ) async throws -> JSONValue {
        guard let action = plugins.action(id) else {
            throw ProjectError.invalid("Unknown or unavailable plugin action \(id); see plugins actions")
        }
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Open a saved project first")
        }
        guard action.when?.evaluate(pluginFacts(mediaID: mediaID)) ?? true else {
            throw ProjectError.invalid("\(action.title) is not available now (\(action.spec.when ?? ""))")
        }
        let values: [String: JSONValue]
        do { values = try action.params.resolve(params) } catch { throw ProjectError.invalid(error.localizedDescription) }
        let session = sessionID
        if action.spec.confirm != nil, author != .user, settings.dangerouslyAllowAgents {
            registry.recordApproval(method: "plugin.action." + id, author: author, approved: true, automatic: true)
        } else if let confirm = action.spec.confirm {
            let choice = ModalCenter.shared.alert(
                "plugin-confirm", title: action.title, message: confirm.text,
                buttons: [ModalOption("cancel", String(localized: "Cancel")), ModalOption("run", String(localized: "Run"))],
                userOnly: true)
            guard choice == "run", session == sessionID else { throw CancellationError() }
        }
        let plugin = action.plugin
        let adapter = PluginActionCapability(
            action: id, params: values, options: pluginOptionValues(plugin, revealSecrets: true),
            context: pluginContext(plugin: plugin, parts: action.spec.context ?? [], mediaID: mediaID, author: author),
            projectRoot: root, outputRoot: Self.pluginOutputRoot(root, plugin: plugin))
        let service = plugins.service
        DebugLog.write("plugin", "action \(id) by \(author)")
        let proposal: PluginEditProposal
        do {
            proposal = try await plugins.running(id) {
                try await service.runContribution(adapter, plugin: plugin, contributionID: id, progress: progress)
            }
        } catch {
            registry.record(method: "plugin.action." + id, author: author, succeeded: false)
            DebugLog.write("plugin", "action \(id) failed")
            throw error
        }
        guard session == sessionID else { throw CancellationError() }
        let revision = try applyPluginProposal(
            proposal, plugin: plugin, label: proposal.label ?? "\(plugin.manifest.displayName): \(action.title)",
            applyUI: true)
        registry.record(method: "plugin.action." + id, author: author, succeeded: true)
        emitPluginEvent(.pluginActionFinished, [
            "action": .string(id), "plugin": .string(plugin.id), "rev": .integer(project.revision),
        ], source: plugin.id)
        return .object([
            "action": .string(id), "rev": .integer(revision ?? project.revision),
            "applied": .integer(proposal.operations.count),
            "message": proposal.message.map(JSONValue.string) ?? .null, "data": proposal.result,
            "files": .array(proposal.files.map { .string($0.path) }),
        ])
    }

    static func pluginOutputRoot(_ root: URL, plugin: InstalledPlugin) -> URL {
        root.appendingPathComponent("generated/plugins/\(plugin.id)", isDirectory: true)
    }

    /// Commits a plugin's proposed operations as one undoable edit by `.plugin`, then applies its UI requests.
    @discardableResult
    func applyPluginProposal(
        _ proposal: PluginEditProposal, plugin: InstalledPlugin, label: String, applyUI: Bool
    ) throws -> Int? {
        var revision: Int?
        if proposal.hasEdits {
            var operations = proposal.operations
            if let data = proposal.pluginData {
                var all = project["pluginData"]?.object ?? [:]
                all[plugin.id] = data == .null ? nil : data
                operations.append(.setProjectProperties(patch: ["pluginData": .object(all)]))
            }
            pluginEditSource = plugin.id
            defer { pluginEditSource = nil }
            revision = try commit(
                .group(label: label, author: .plugin, ops: operations), label: label, author: .plugin,
                baseRevision: proposal.baseRevision)
        }
        if applyUI { applyPluginUI(proposal.ui) }
        if let text = proposal.message { message = "\(plugin.manifest.displayName): \(text)" }
        return revision
    }

    private func applyPluginUI(_ request: PluginUIRequest) {
        guard !request.isEmpty else { return }
        if let id = request.select, project.tracks.flatMap(\.items).contains(where: { $0.id == id }) {
            selectedID = id
            selectedTrackID = project.tracks.first { $0.items.contains { $0.id == id } }?.id
        }
        if let id = request.selectTrack, project.tracks.contains(where: { $0.id == id }) { selectedTrackID = id }
        if let frame = request.seek { preview.seek(min(frame, project.duration)) }
        if let frame = request.reveal { revealInTimeline(frame) }
        if let tab = request.panel.flatMap(LibraryTab.init(panelName:)) { showLibraryTab(tab) }
        if let tab = request.inspector, UIAction.inspectorTabs.contains(tab) { ui.inspectorTab = tab }
    }

    // MARK: Parameter sheet

    func runPendingPluginAction() {
        guard let pending = plugins.pendingAction else { return }
        plugins.pendingAction = nil
        startPluginActionJob(
            pending.action.id, params: pending.values, mediaID: pending.mediaID, author: pending.author)
    }

    // MARK: Automation

    /// Actions whose id, title or plugin contain `query` (any case), optionally of one plugin.
    func pluginActionsJSON(query: String? = nil, plugin: String? = nil) -> JSONValue {
        let formatter = ISO8601DateFormatter()
        let matching = plugins.actions.filter { action in
            (plugin == nil || action.plugin.id == plugin)
                && PluginActionTools.matches(query, [action.id, action.title, action.plugin.id, action.plugin.manifest.name.text])
        }
        return .array(matching.map { action in
            .object([
                "id": .string(action.id), "title": .string(action.title), "plugin": .string(action.plugin.id),
                "placements": .array(action.spec.placements.map(JSONValue.string)),
                "when": action.spec.when.map(JSONValue.string) ?? .null,
                "shortcut": action.shortcut.map { .string($0.description) } ?? .null,
                "params": .object([
                    "type": .string("object"),
                    "properties": .object(Dictionary(uniqueKeysWithValues: action.params.map { ($0.id, $0.jsonSchema) })),
                    "additionalProperties": .bool(false),
                ]),
                "enabled": .bool(canRunPluginAction(action)),
                "lastRun": plugins.lastRun[action.id].map { .string(formatter.string(from: $0)) } ?? .null,
            ])
        })
    }

    func registerPluginCommands() {
        handle("plugins.actions") { document, arguments, _ in
            document.pluginActionsJSON(query: arguments.optionalString("query"), plugin: arguments.optionalString("plugin"))
        }
        handleAuthored("plugins.run") { document, arguments, author in
            let id = try arguments.string("action")
            guard let action = document.plugins.action(id) else {
                throw RPCFailure(-32602, "Unknown or unavailable plugin action \(id); see plugins actions")
            }
            guard document.fileURL != nil else { throw RPCFailure(-32602, "Open a saved project first") }
            guard !document.plugins.calling.contains(id) else { throw RPCFailure(-32003, "\(id) is already running") }
            guard document.canRunPluginAction(action) else {
                throw RPCFailure(-32003, "\(id) is not available now (\(action.spec.when ?? "busy"))")
            }
            let params = arguments["params"]?.object ?? [:]
            do { _ = try action.params.resolve(params) } catch { throw RPCFailure(-32602, error.localizedDescription) }
            let job = document.startPluginActionJob(id, params: params, author: author)
            return .object(["job": .string(job), "state": .string("running")])
        }
        handle("plugins.hooks") { document, _, _ in document.pluginHooksJSON() }
        handleAuthored("plugins.proposal") { document, arguments, _ in
            let id = try arguments.string("id")
            guard document.plugins.proposals.contains(where: { $0.id == id }) else {
                throw RPCFailure(-32602, "Unknown proposal \(id); see plugins hooks")
            }
            let apply = try arguments.string("decision") == "apply"
            try document.resolvePluginProposal(id, apply: apply)
            return .object(["rev": .integer(document.project.revision)])
        }
        handle("plugins.options") { document, arguments, _ in
            let plugin = try document.requirePlugin(arguments.string("plugin"))
            let values = document.pluginOptionValues(plugin)
            return .array((plugin.manifest.options ?? []).map { option in
                .object([
                    "id": .string(option.id), "title": .string(option.title.text),
                    "scope": .string(option.effectiveScope.rawValue), "schema": option.jsonSchema,
                    "value": values[option.id] ?? .null,
                ])
            })
        }
        handleAuthored("plugins.option") { document, arguments, author in
            let plugin = try document.requirePlugin(arguments.string("plugin"))
            let id = try arguments.string("option")
            let options = plugin.manifest.options ?? []
            try PluginOptionPolicy.validateEdit(options: options, author: author)
            guard let option = options.first(where: { $0.id == id }) else {
                throw RPCFailure(-32602, "Unknown option \(id)")
            }
            let value: JSONValue?
            do { value = try arguments.optionalString("value").map(option.parse) } catch {
                throw RPCFailure(-32602, error.localizedDescription)
            }
            try document.setPluginOption(plugin, option: id, value: value, author: author)
            return .object(["value": document.pluginOptionValues(plugin)[id] ?? .null, "rev": .integer(document.project.revision)])
        }
        registerPluginRegistryCommands()
        handleAuthored("plugins.set") { document, arguments, _ in
            let plugin = try document.requirePlugin(arguments.string("plugin"))
            let enabled = arguments.optionalBool("enabled")
            let hooks = arguments.optionalBool("hooks")
            guard enabled != nil || hooks != nil else { throw RPCFailure(-32602, "Give enabled or hooks") }
            guard enabled != true, hooks != true else {
                throw RPCFailure(-32001, "Only the user can turn a plugin or its hooks on (Plugins sheet)")
            }
            try document.plugins.setEnabled(plugin, enabled: enabled, hooks: hooks)
            return .object([
                "plugin": .string(plugin.id), "availability": .string(document.plugins.currentAvailability(plugin).name),
                "hooks": .bool(document.plugins.trust.hooksEnabled(plugin)),
            ])
        }
    }

    func requirePlugin(_ id: String) throws -> InstalledPlugin {
        if plugins.plugins.isEmpty { plugins.refresh(projectRoot: fileURL?.deletingLastPathComponent()) }
        guard let plugin = plugins.plugin(id) else { throw RPCFailure(-32602, "Unknown plugin \(id); see plugins list") }
        return plugin
    }

    /// Runs a plugin action named by `ui.action`, by ID or shortcut. Nil when no plugin action matches.
    func performPluginActionFromAutomation(_ name: String, author: Author) throws -> JSONValue? {
        let value = name.trimmingCharacters(in: .whitespaces)
        let shortcut = UIShortcut(parsing: value)
        guard let action = plugins.actions.first(where: { $0.id == value || ($0.shortcut != nil && $0.shortcut == shortcut) })
        else { return nil }
        guard canRunPluginAction(action) else { throw RPCFailure(-32003, "\(action.id) is not available now") }
        if !action.params.isEmpty || action.spec.confirm != nil {
            // Opens the parameter sheet like a click; answer it with ui.respond run|cancel, or use plugins.run.
            let defaults = (try? action.params.resolve([:])) ?? [:]
            plugins.pendingAction = PendingPluginAction(action: action, values: defaults, mediaID: nil, author: author)
            return .object(["action": .string(action.id), "started": .bool(true), "dialog": .string("plugin-action")])
        }
        let job = startPluginActionJob(action.id, params: [:], author: author)
        return .object(["action": .string(action.id), "job": .string(job)])
    }
}
