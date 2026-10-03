import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// A slash command in a chat-agent tab: one of the app's (the same for every agent), an agent-kit skill, or one the
/// plugin declares (docs/specs/11-chat-agents.md §3.4).
struct ChatCommand: Identifiable, Equatable {
    enum Source: Equatable { case app, skill, plugin }
    var name: String
    var args: String?
    var summary: String
    var choices: [String] = []
    var source: Source
    var id: String { name }
}

extension ChatAgentModel {
    static let appCommands: [ChatCommand] = [
        ChatCommand(name: "new", summary: String(localized: "Start a new conversation"), source: .app),
        ChatCommand(name: "clear", summary: String(localized: "Start a new conversation"), source: .app),
        ChatCommand(name: "stop", summary: String(localized: "Stop the running turn"), source: .app),
        ChatCommand(name: "settings", summary: String(localized: "Open the agent's settings"), source: .app),
        ChatCommand(name: "copy", summary: String(localized: "Copy the last reply"), source: .app),
        ChatCommand(
            name: "export", args: "[path]", summary: String(localized: "Save the conversation as Markdown"),
            source: .app),
    ]

    /// Every command the tab offers: the app's, then the kit's skills, then the plugin's (app names win).
    var commands: [ChatCommand] {
        let skills = (document.agentKitLaunch()?.kit.skills ?? []).map {
            ChatCommand(
                name: "skill:" + $0, args: "[task]", summary: String(localized: "Follow this agent-kit skill"),
                source: .skill)
        }
        let taken = Set(Self.appCommands.map(\.name))
        return Self.appCommands + skills + pluginCommands.filter { !taken.contains($0.name) }
    }

    func loadPluginCommands(_ resolved: ResolvedPluginProvider) async {
        guard let result = try? await document.plugins.service.chat(["op": .string("commands")], using: resolved, host: nil)
        else { return }
        pluginCommands = (result.object["commands"]?.array ?? []).compactMap { entry in
            let fields = entry.object
            guard let name = fields["name"]?.string, name.range(of: "^[a-z][a-z0-9:-]{0,40}$", options: .regularExpression) != nil
            else { return nil }
            return ChatCommand(
                name: name, args: fields["args"]?.string, summary: fields["summary"]?.string ?? "",
                choices: (fields["choices"]?.array ?? []).compactMap(\.string).prefix(1000).map { $0 }, source: .plugin)
        }
    }

    /// Whether `line` is a slash command this tab knows (otherwise it goes to the model as text).
    func isCommand(_ line: String) -> Bool {
        guard let (name, _) = Self.parse(line) else { return false }
        return commands.contains { $0.name == name }
    }

    /// Runs a typed command line such as `/compact keep the caption decisions`; returns what it showed.
    @discardableResult
    func runCommand(_ line: String, author: Author = .user) async throws -> String {
        guard let (name, args) = Self.parse(line), let command = commands.first(where: { $0.name == name }) else {
            throw ProjectError.invalid("Unknown command \(line.split(separator: " ").first ?? "")")
        }
        let text: String
        switch (command.source, name) {
        case (.app, "new"), (.app, "clear"):
            await reset()
            text = String(localized: "New conversation")
        case (.app, "stop"):
            stop()
            text = String(localized: "Stopped")
        case (.app, "settings"):
            document.ui.settingsSection = "plugins"
            document.ui.showSettings = true
            return ""
        case (.app, "copy"):
            guard let reply = entries.last(where: { $0.kind == .assistant })?.text else {
                throw ProjectError.invalid("There is no reply to copy yet")
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(reply, forType: .string)
            text = String(localized: "Copied the last reply")
        case (.app, "export"):
            text = try exportTranscript(to: args)
        case (.skill, _):
            let skill = String(name.dropFirst("skill:".count))
            send("Use the agent-kit skill \(skill): read it with read_skill first, then follow it."
                + (args.isEmpty ? "" : "\nTask: \(args)"))
            return ""
        default:
            text = try await runPluginCommand(name, args: args, author: author)
        }
        if !text.isEmpty { append(Entry(kind: .notice, text: text)) }
        return text
    }

    private func runPluginCommand(_ name: String, args: String, author: Author) async throws -> String {
        guard !running, runningCommand == nil else { throw ProjectError.invalid("\(title) is working; stop it first") }
        runningCommand = "/" + name
        defer { runningCommand = nil }
        let resolved = try await resolve()
        let result = try await document.plugins.service.chat(
            ["op": .string("command"), "conversation": .string(conversation), "name": .string(name),
             "args": .string(args)],
            using: resolved, host: nil)
        if let patch = result.object["options"]?.object, !patch.isEmpty {
            let options = resolved.plugin.manifest.options ?? []
            for (key, value) in patch.sorted(by: { $0.key < $1.key }) {
                guard let option = options.first(where: { $0.id == key }), option.type != .secret else {
                    throw ProjectError.invalid("\(title) cannot set \(key)")
                }
                try document.setPluginOption(resolved.plugin, option: key, value: value, author: author)
            }
            await refreshStatus()
        }
        return result.object["text"]?.string ?? ""
    }

    /// Writes the transcript as Markdown to `path`, or to a file the user picks.
    private func exportTranscript(to path: String) throws -> String {
        let url: URL
        if path.isEmpty {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(title) \(Date().formatted(date: .numeric, time: .omitted)).md"
                .replacingOccurrences(of: "/", with: "-")
            guard let chosen = ModalCenter.shared.save(panel, name: "chat-export") else { return "" }
            url = chosen
        } else {
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        try Data(markdown.utf8).write(to: url, options: .atomic)
        return String(format: String(localized: "Saved the conversation to %@"), url.path)
    }

    var markdown: String {
        var lines = ["# \(title)", ""]
        for entry in entries {
            switch entry.kind {
            case .user: lines += ["**You:** " + entry.text, ""]
            case .assistant: lines += [entry.text, ""]
            case .tool: lines += ["- `\(entry.name ?? "")` " + (entry.ok == false ? "✗ " : "✓ ") + entry.text]
            case .notice: lines += ["_\(entry.text)_", ""]
            case .error: lines += ["> ⚠️ " + entry.text, ""]
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `/name args…` → (name, args); nil when the line is not a command.
    static func parse(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), trimmed.count > 1 else { return nil }
        let body = trimmed.dropFirst()
        let name = body.prefix { !$0.isWhitespace }.lowercased()
        let args = body.dropFirst(name.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, args)
    }

    var commandsJSON: JSONValue {
        .array(commands.map { command in
            var fields: [String: JSONValue] = [
                "name": .string(command.name), "summary": .string(command.summary),
                "source": .string("\(command.source)"),
            ]
            if let args = command.args { fields["args"] = .string(args) }
            if !command.choices.isEmpty { fields["choices"] = .array(command.choices.map(JSONValue.string)) }
            return .object(fields)
        })
    }
}
