import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// Delivers editor events to plugin hooks. Hooks are notify-only and never block the editor:
///
/// - each (plugin, event) pair is debounced and coalesced, so only the latest payload is delivered;
/// - one hook runs per plugin at a time, later events wait in a small per-plugin queue;
/// - at most `PluginHookScheduler.defaultLimit` hooks run at once across plugins, which take turns (#99);
/// - a plugin gets at most `rateLimit` deliveries a minute, extra events are dropped and logged;
/// - an edit a hook caused never re-triggers that plugin's own hooks;
/// - failures go to the hook log and debug log, never to the editor's status bar.
@MainActor final class PluginHookDispatcher {
    struct Key: Hashable {
        let plugin: String
        let event: PluginEvent
    }

    private struct Delivery {
        let plugin: InstalledPlugin
        let hook: PluginHookContribution
        var payload: JSONValue
    }

    static let rateLimit = 60
    weak var document: ProjectDocument?
    private var waiting: [Key: Delivery] = [:]
    private var debounces: [Key: Task<Void, Never>] = [:]
    private var scheduler = PluginHookScheduler<Key>()
    private var recent: [String: [Date]] = [:]

    init(document: ProjectDocument) { self.document = document }

    func emit(_ event: PluginEvent, payload: JSONValue, source: String?) {
        guard let document else { return }
        for (plugin, hook) in document.plugins.subscribers(for: event) where plugin.id != source {
            let key = Key(plugin: plugin.id, event: event)
            waiting[key] = Delivery(plugin: plugin, hook: hook, payload: payload)
            let delay = hook.debounceMs ?? event.defaultDebounceMs
            debounces[key]?.cancel()
            if delay == 0 {
                enqueue(key)
            } else {
                debounces[key] = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                    guard !Task.isCancelled else { return }
                    self?.debounces[key] = nil
                    self?.enqueue(key)
                }
            }
        }
    }

    /// Drops everything waiting (project switch, hooks turned off).
    func reset() {
        for task in debounces.values { task.cancel() }
        debounces.removeAll()
        waiting.removeAll()
        scheduler.removeQueued()
    }

    /// The backlog for `plugins hooks`.
    var queueJSON: JSONValue {
        .object([
            "limit": .integer(scheduler.limit), "running": .array(scheduler.running.sorted().map(JSONValue.string)),
            "queued": .integer(scheduler.queued), "debouncing": .integer(debounces.count),
        ])
    }

    private func enqueue(_ key: Key) {
        scheduler.enqueue(key, plugin: key.plugin)
        startReady()
    }

    /// Starts deliveries until the global limit is reached or nothing waits.
    private func startReady() {
        while let (pluginID, key) = scheduler.next() {
            guard let delivery = waiting.removeValue(forKey: key), let document else {
                scheduler.finish(pluginID)
                continue
            }
            let now = Date()
            let window = (recent[pluginID] ?? []).filter { now.timeIntervalSince($0) < 60 }
            guard window.count < Self.rateLimit else {
                recent[pluginID] = window
                document.plugins.log(pluginID, key.event.rawValue, .dropped, "rate limit \(Self.rateLimit)/min")
                scheduler.finish(pluginID)
                continue
            }
            recent[pluginID] = window + [now]
            Task { [weak self] in
                await document.deliverHook(delivery.plugin, hook: delivery.hook, payload: delivery.payload)
                self?.scheduler.finish(pluginID)
                self?.startReady()
            }
        }
    }
}

extension ProjectDocument {
    /// Sends an editor event to every subscribed plugin. `source` is the plugin that caused it, which does
    /// not hear about its own edits.
    func emitPluginEvent(
        _ event: PluginEvent, _ payload: @autoclosure () -> [String: JSONValue] = [:], source: String? = nil
    ) {
        guard settings.runPluginHooks, !plugins.subscribers(for: event).isEmpty else { return }
        var fields = payload()
        fields["event"] = .string(event.rawValue)
        fields["at"] = .string(ISO8601DateFormatter().string(from: Date()))
        pluginHooks.emit(event, payload: .object(fields), source: source ?? pluginEditSource)
    }

    func deliverHook(_ plugin: InstalledPlugin, hook: PluginHookContribution, payload: JSONValue) async {
        let event = hook.event
        let session = sessionID
        let root = fileURL?.deletingLastPathComponent()
        let adapter = PluginHookCapability(
            event: event, payload: payload, options: pluginOptionValues(plugin, revealSecrets: true),
            context: pluginContext(plugin: plugin, parts: hook.context ?? [], author: .plugin),
            projectRoot: root, outputRoot: root.map { Self.pluginOutputRoot($0, plugin: plugin) })
        let proposal: PluginEditProposal
        do {
            proposal = try await plugins.service.runContribution(
                adapter, plugin: plugin, contributionID: "hook." + event)
        } catch {
            plugins.log(plugin.id, event, .failed, error.localizedDescription)
            registry.record(method: "plugin.hook." + event, author: .plugin, succeeded: false)
            return
        }
        registry.record(method: "plugin.hook." + event, author: .plugin, succeeded: true)
        guard proposal.hasEdits else {
            plugins.log(plugin.id, event, .delivered, proposal.message ?? "")
            if let text = proposal.message, session == sessionID { message = "\(plugin.manifest.displayName): \(text)" }
            return
        }
        guard hook.proposesEdits else {
            plugins.log(plugin.id, event, .ignored, "returned operations without \"edits\": true")
            return
        }
        guard session == sessionID, fileURL != nil else {
            plugins.log(plugin.id, event, .ignored, "the project changed before the hook answered")
            return
        }
        let label = proposal.label ?? "\(plugin.manifest.displayName): \(event)"
        if settings.autoApplyPluginHookEdits {
            do {
                try applyPluginProposal(proposal, plugin: plugin, label: label, applyUI: false)
                plugins.log(plugin.id, event, .applied, "\(proposal.operations.count) operations")
            } catch {
                plugins.log(plugin.id, event, .failed, error.localizedDescription)
            }
        } else {
            plugins.proposals.append(PluginProposal(
                id: UUID().uuidString, plugin: plugin, event: event, proposal: proposal, createdAt: Date()))
            if plugins.proposals.count > 20 { plugins.proposals.removeFirst(plugins.proposals.count - 20) }
            plugins.log(plugin.id, event, .proposed, "\(proposal.operations.count) operations")
            message = String(format: String(localized: "%@ proposes an edit: %@"), plugin.manifest.displayName, label)
        }
    }

    /// Applies or drops a hook's proposed edit (the review sheet, `plugins proposal`).
    func resolvePluginProposal(_ id: String, apply: Bool) throws {
        guard let index = plugins.proposals.firstIndex(where: { $0.id == id }) else { return }
        let entry = plugins.proposals.remove(at: index)
        guard apply else {
            plugins.log(entry.plugin.id, entry.event, .ignored, "discarded")
            return
        }
        do {
            try applyPluginProposal(entry.proposal, plugin: entry.plugin, label: entry.title, applyUI: false)
            plugins.log(entry.plugin.id, entry.event, .applied, "\(entry.proposal.operations.count) operations")
        } catch {
            plugins.log(entry.plugin.id, entry.event, .failed, error.localizedDescription)
            throw error
        }
    }

    func pluginHooksJSON() -> JSONValue {
        .object([
            "enabled": .bool(settings.runPluginHooks), "autoApply": .bool(settings.autoApplyPluginHookEdits),
            "subscriptions": .array(plugins.plugins.flatMap { plugin in
                plugin.manifest.hooks.map { hook in
                    .object([
                        "plugin": .string(plugin.id), "event": .string(hook.event),
                        "edits": .bool(hook.proposesEdits),
                        "debounceMs": .integer(hook.debounceMs ?? hook.kind?.defaultDebounceMs ?? 0),
                        "active": .bool(plugins.availability[plugin.id] == .ready && plugins.trust.hooksEnabled(plugin)),
                    ])
                }
            }),
            "events": .array(PluginEvent.allCases.map { .string($0.rawValue) }),
            "queue": pluginHooks.queueJSON,
            "recent": .array(plugins.hookLog.suffix(50).map(\.json)),
            "proposals": .array(plugins.proposals.map(\.json)),
        ])
    }

    func selectionDidChange() {
        emitPluginEvent(.selectionChanged, [
            "item": selectedID.map(JSONValue.string) ?? .null, "track": selectedTrackID.map(JSONValue.string) ?? .null,
            "items": .array(selectedIDs.map(JSONValue.string)),
        ])
    }

    func emitMediaImported(_ mediaIDs: [String], author: Author) {
        emitPluginEvent(.mediaImported, [
            "author": .string(author.rawValue),
            "media": .array(project.media.filter { mediaIDs.contains($0.id) }.map { .object($0.fields) }),
        ])
    }

    /// Payload fields for an edit event.
    func editEventPayload(label: String, author: Author, before: Project) -> [String: JSONValue] {
        let changes = project.itemChanges(from: before)
        return [
            "label": .string(label), "author": .string(author.rawValue),
            "rev": .integer(project.revision), "previousRev": .integer(before.revision),
            "changedItems": .array(changes.prefix(200).map { .string($0.itemID) }),
            "changedCount": .integer(changes.count),
        ]
    }
}
