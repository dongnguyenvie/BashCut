import BashCutAgent
import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

enum ChatEntryKind: String, Codable { case user, assistant, tool, notice, error }

/// A chat agent in the dock: a plugin with the `agent.chat` capability (docs/specs/11-chat-agents.md), such as
/// AI Editor. Any plugin can provide one; each gets its own tab. This model owns one plugin's conversation for the
/// open project: the transcript shown in the dock, the running turn, and the session token its command calls run
/// with.
@MainActor @Observable final class ChatAgentModel {
    struct Entry: Identifiable, Codable, Equatable {
        var id = UUID()
        var kind: ChatEntryKind
        var text: String
        /// Tool rows: the call ID, the tool, and whether it finished and succeeded.
        var callID: String?
        var name: String?
        var ok: Bool?
        /// User messages: the timeline items attached when it was sent.
        var scope: [AgentScopeItem]?
    }

    private struct Saved: Codable {
        var conversation: String
        var entries: [Entry]
    }

    unowned let document: ProjectDocument
    /// The plugin this agent comes from.
    let pluginID: String
    private(set) var entries: [Entry] = []
    private(set) var running = false
    /// What the provider reported: whether a key is set and which model it uses.
    private(set) var status: JSONValue?
    /// Slash commands the plugin declares (op `commands`); the app's own come first (see `commands`).
    var pluginCommands: [ChatCommand] = []
    /// The plugin command running now, such as `/compact`.
    var runningCommand: String?
    var error = ""
    /// The message being written in the agent's tab, and a frame to attach (the dock's quick prompts fill these).
    var draft = ""
    var draftImage: URL?
    /// Timeline items attached with Send to Agent, shown as chips over the input. Every message carries them until
    /// the user removes them.
    var scope: [AgentScopeItem] = []
    private(set) var conversation = UUID().uuidString
    private var turn: Task<Void, Never>?
    private let commandSession = ChatCommandSession()
    /// The assistant entry text deltas are added to.
    private var streaming: UUID?
    static let maximumEntries = 400

    init(document: ProjectDocument, pluginID: String) {
        self.document = document
        self.pluginID = pluginID
    }

    /// The plugin, while it is installed and ready.
    var plugin: InstalledPlugin? { ChatAgents.ready(in: document).first { $0.id == pluginID } }
    var isAvailable: Bool { plugin != nil }
    /// The tab title: the plugin's name.
    var title: String { plugin?.manifest.displayName ?? pluginID }

    // MARK: Conversation

    /// Sends a message and runs the turn: the plugin streams events and calls commands until the model stops.
    func send(_ text: String, imageURL: URL? = nil) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !running else { return }
        let scope = scope
        append(Entry(
            kind: .user, text: message + (imageURL.map { "\n[\($0.lastPathComponent)]" } ?? ""),
            scope: scope.isEmpty ? nil : scope))
        running = true
        error = ""
        streaming = nil
        turn = Task { [weak self] in
            await self?.run(message, imageURL: imageURL, scope: scope)
            self?.running = false
            self?.streaming = nil
            self?.save()
        }
    }

    func stop() {
        turn?.cancel()
    }

    /// Forgets the conversation here and in the plugin, and the token its commands ran with.
    func reset() async {
        stop()
        await turn?.value
        if let resolved = try? await resolve() {
            _ = try? await document.plugins.service.chat(
                ["op": .string("reset"), "conversation": .string(conversation)], using: resolved, host: nil)
        }
        revokeToken()
        conversation = UUID().uuidString
        entries = []
        scope = []
        error = ""
        save()
    }

    /// Asks the provider whether it is ready (key set, model known), and with `commands` also for its slash commands;
    /// the two requests run together. `chat status` skips the commands.
    func refreshStatus(commands: Bool = true) async {
        guard isAvailable, let resolved = try? await resolve() else {
            status = nil
            return
        }
        async let loaded: Void = commands ? loadPluginCommands(resolved) : ()
        status = try? await document.plugins.service.chat(
            ["op": .string("status"), "conversation": .string(conversation)], using: resolved, host: nil)
        await loaded
    }

    /// The open project changed: stop, and show that project's conversation.
    func projectChanged() {
        stop()
        revokeToken()
        entries = []
        scope = []
        conversation = UUID().uuidString
        error = ""
        guard let url = stateURL, let data = try? Data(contentsOf: url),
            let saved = try? JSONDecoder().decode(Saved.self, from: data)
        else { return }
        conversation = saved.conversation
        entries = saved.entries
    }

    var transcriptJSON: JSONValue {
        .object([
            "conversation": .string(conversation), "running": .bool(running),
            "entries": .array(entries.map(Self.json)), "scope": .array(scope.map(\.json)),
        ])
    }

    // MARK: Turn

    private func run(_ text: String, imageURL: URL?, scope: [AgentScopeItem]) async {
        do {
            let resolved = try await resolve()
            let (events, sink) = AsyncStream.makeStream(of: JSONValue.self)
            let pump = Task { [weak self] in
                for await event in events { self?.apply(event) }
            }
            let host = PluginHostChannel(event: { sink.yield($0) }, call: { [weak self] method, params in
                guard let self else { return .failure(PluginCallFailure(code: -32603, message: "The agent closed")) }
                return await self.perform(method, params)
            })
            let result = try await document.plugins.service.chat(turnParams(text, imageURL: imageURL, scope: scope), using: resolved, host: host)
            sink.finish()
            await pump.value
            switch result.object["stopReason"]?.string {
            case "error": append(Entry(kind: .error, text: result.object["error"]?.string ?? "The agent stopped with an error"))
            case "aborted": append(Entry(kind: .notice, text: String(localized: "Stopped")))
            default: break
            }
        } catch is CancellationError {
            append(Entry(kind: .notice, text: String(localized: "Stopped")))
        } catch {
            let text = Task.isCancelled ? String(localized: "Stopped") : error.localizedDescription
            append(Entry(kind: Task.isCancelled ? .notice : .error, text: text))
        }
    }

    /// The scope rides in the text for any model, and as `scope` for plugins that read it.
    private func turnParams(_ text: String, imageURL: URL?, scope: [AgentScopeItem]) -> [String: JSONValue] {
        let scopeText = AgentScope.text(scope, fps: document.project.fps)
        return [
            "op": .string("turn"), "conversation": .string(conversation),
            "text": .string(scopeText.isEmpty ? text : scopeText + "\n\n" + text),
            "scope": .array(scope.map(\.json)),
            "images": .array(imageURL.map { [.string($0.path)] } ?? []),
            "context": .string(document.contextText() + "\n" + TimelineSummary.text(document.project) + "\n"
                + document.agents.knowledgeStore.summary().text),
            "instructions": .string(Self.preamble + "\n" + CommandCatalog.instructions),
            "tools": .array(Self.tools), "kit": kitJSON(),
        ]
    }

    /// Runs one command the model called, as an agent with this conversation's token.
    private func perform(_ method: String, _ params: JSONValue) async -> Result<JSONValue, PluginCallFailure> {
        let response = await commandSession.perform(
            method, params: params.object, allowEdits: document.settings.allowAgentEdits, registry: document.registry)
        if let failure = response.error { return .failure(PluginCallFailure(code: failure.code, message: failure.message)) }
        return .success(response.result ?? .null)
    }

    private func apply(_ event: JSONValue) {
        let fields = event.object
        switch fields["kind"]?.string {
        case "text":
            let delta = fields["delta"]?.string ?? ""
            if let streaming, let index = entries.firstIndex(where: { $0.id == streaming }) {
                entries[index].text += delta
            } else {
                let entry = Entry(kind: .assistant, text: delta)
                streaming = entry.id
                append(entry)
            }
        case "message" where fields["role"]?.string == "assistant":
            let text = fields["text"]?.string ?? ""
            if let streaming, let index = entries.firstIndex(where: { $0.id == streaming }) {
                entries[index].text = text
            } else if !text.isEmpty {
                append(Entry(kind: .assistant, text: text))
            }
            streaming = nil
        case "tool", "toolEnd":
            applyTool(fields)
        case "notice":
            append(Entry(kind: .notice, text: fields["text"]?.string ?? ""))
        default:
            break
        }
    }

    /// A tool row starts (`tool`) or finishes (`toolEnd`).
    private func applyTool(_ fields: [String: JSONValue]) {
        streaming = nil
        guard fields["kind"]?.string == "toolEnd" else {
            append(Entry(
                kind: .tool, text: fields["summary"]?.string ?? "", callID: fields["callId"]?.string,
                name: fields["name"]?.string))
            return
        }
        guard let callID = fields["callId"]?.string,
            let index = entries.lastIndex(where: { $0.kind == .tool && $0.callID == callID })
        else { return }
        entries[index].ok = fields["ok"]?.bool ?? true
        if let summary = fields["summary"]?.string, !summary.isEmpty { entries[index].text = summary }
    }

    // MARK: Helpers

    /// This plugin's `agent.chat` provider.
    func resolve() async throws -> ResolvedPluginProvider {
        let provider = plugin?.manifest.providers?.first { $0.capability == PluginAPI.agentChat }
        guard let provider else { throw ProjectError.invalid("\(title) is not installed or not ready") }
        return try await document.plugins.service.resolve(
            PluginAPI.agentChat, preferredProvider: provider.id,
            projectRoot: document.fileURL?.deletingLastPathComponent())
    }

    func append(_ entry: Entry) {
        entries.append(entry)
        if entries.count > Self.maximumEntries { entries.removeFirst(entries.count - Self.maximumEntries) }
    }

    func revokeToken() {
        commandSession.revoke(in: document.registry)
    }

    private var stateURL: URL? {
        document.fileURL?.deletingLastPathComponent().appendingPathComponent(".bashcut/chat/\(pluginID).json")
    }

    private func save() {
        guard let url = stateURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(conversation: conversation, entries: entries)).write(to: url, options: .atomic)
        } catch {
            DebugLog.write("chat", "cannot save the \(pluginID) transcript: \(error.localizedDescription)")
        }
    }

    private func kitJSON() -> JSONValue {
        document.agentKitLaunch().map { PluginTerminals.kitJSON($0.kit) } ?? .null
    }

    private static func json(_ entry: Entry) -> JSONValue {
        var fields: [String: JSONValue] = ["kind": .string(entry.kind.rawValue), "text": .string(entry.text)]
        if let name = entry.name { fields["name"] = .string(name) }
        if let ok = entry.ok { fields["ok"] = .bool(ok) }
        if let scope = entry.scope { fields["scope"] = .array(scope.map(\.json)) }
        return .object(fields)
    }

    /// Reviewed commands exposed to the chat agent. The same allow-list guards execution.
    static let tools: [JSONValue] = CommandCatalog.specs
        .filter { ChatCommandSession.allowedMethods.contains($0.name) }
        .map { spec in
            .object([
                "name": .string(spec.mcpToolName), "method": .string(spec.name),
                "description": .string(spec.summary), "inputSchema": spec.inputSchema,
            ])
        }

    static let preamble = """
        You are an editing agent inside BashCut, a video editor. You edit the open project only through \
        the tools, which are BashCut's own commands. Work in small steps: read the project (context and timeline) \
        first, make one change at a time, pass the current revision, and look at the result with the ui frame tool \
        before you say it is done. Every edit is undoable; keep groups of related changes in one timeline apply. \
        When a skill fits the task, read it with read_skill and follow it. Answer in the user's language, briefly.
        """
}

/// The chat agents of the open project: one `ChatAgentModel` per ready plugin with the `agent.chat` capability.
@MainActor final class ChatAgents {
    unowned let document: ProjectDocument
    private var models: [String: ChatAgentModel] = [:]

    init(document: ProjectDocument) { self.document = document }

    /// Ready plugins that provide `agent.chat`, in catalog order.
    static func ready(in document: ProjectDocument) -> [InstalledPlugin] {
        document.plugins.plugins.filter { plugin in
            document.plugins.availability[plugin.id] == .ready
                && (plugin.manifest.providers ?? []).contains { $0.capability == PluginAPI.agentChat }
        }
    }

    var available: [ChatAgentModel] { Self.ready(in: document).map { model(for: $0.id) } }

    func model(for pluginID: String) -> ChatAgentModel {
        if let model = models[pluginID] { return model }
        let model = ChatAgentModel(document: document, pluginID: pluginID)
        model.projectChanged()
        models[pluginID] = model
        return model
    }

    /// The agent a command means: the named plugin, else the one whose tab is shown, else the first ready one.
    func target(_ pluginID: String?) throws -> ChatAgentModel {
        if let pluginID {
            guard Self.ready(in: document).contains(where: { $0.id == pluginID }) else {
                throw ProjectError.invalid("\(pluginID) is not a ready chat agent")
            }
            return model(for: pluginID)
        }
        if let shown = document.agents.chatPluginID, models[shown]?.isAvailable == true { return model(for: shown) }
        guard let first = available.first else {
            throw ProjectError.invalid("No chat agent is installed (plugins search --capability agent.chat)")
        }
        return first
    }

    func revokeTokens() {
        for model in models.values { model.revokeToken() }
    }

    func projectChanged() {
        for model in models.values { model.projectChanged() }
    }
}
