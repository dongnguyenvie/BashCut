import BashCutProject

extension CommandCatalog {
    /// Settings › Agents: the agent kit for BashCut's tabs and for Claude Code and Codex outside BashCut.
    static let agentSpecs: [CommandSpec] = [
        CommandSpec(
            "agent.status", .read,
            "The agent kit (editing skills) BashCut uses: its folder, version and skills, whether BashCut's Claude and "
                + "Codex tabs load it, and for Claude Code and Codex outside BashCut: the CLI, whether the kit is set "
                + "up, and the configuration folder (CLAUDE_CONFIG_DIR, CODEX_HOME) with where it came from."),
        CommandSpec(
            "agent.setup", .privileged,
            "Set up the agent kit like Settings › Agents: in-app (load it in BashCut's tabs), claude (install the "
                + "bashcut plugin in Claude Code) or codex (link the skills and register the MCP server); remove "
                + "undoes it. Can also choose the kit folder and the agents' configuration folders.",
            parameters: [
                CommandParameter("target", .string, "What to set up", required: true,
                                 choices: ["in-app", "claude", "codex"], cli: .positional),
                CommandParameter("remove", .boolean, "Undo the setup instead", default: .bool(false),
                                 cli: .flag("remove")),
                CommandParameter("kit", .string, "Kit folder to use, or built-in", cli: .option("kit")),
                CommandParameter("claudeConfigDir", .string,
                                 "Claude Code's configuration folder (CLAUDE_CONFIG_DIR), or default to detect it",
                                 cli: .option("claude-config-dir")),
                CommandParameter("codexHome", .string, "Codex's home folder (CODEX_HOME), or default to detect it",
                                 cli: .option("codex-home")),
            ],
            execution: .approval),
    ]

    /// Chat-agent tabs: plugins with the `agent.chat` capability (docs/specs/11-chat-agents.md), such as Director.
    static let chatSpecs: [CommandSpec] = [
        CommandSpec(
            "chat.status", .read,
            "The chat agents in the agent dock (plugins with the agent.chat capability): each one's plugin ID, name, "
                + "provider and model, whether it is ready (an API key is set) and whether a turn is running."),
        CommandSpec(
            "chat.send", .ui,
            "Send a message to a chat agent like typing it in its tab. Returns at once; poll chat transcript until "
                + "running is false to read the reply and the commands it ran.",
            parameters: [
                CommandParameter("text", .string, "Message", required: true, cli: .positional),
                plugin,
                CommandParameter("image", .string, "PNG or JPEG to attach, such as a ui frame", cli: .option("image")),
            ]),
        CommandSpec("chat.stop", .ui, "Stop a chat agent's running turn.", parameters: [plugin]),
        CommandSpec(
            "chat.reset", .ui, "Start a new conversation with a chat agent for this project; the old one is forgotten.",
            parameters: [plugin]),
        CommandSpec(
            "chat.transcript", .read,
            "A chat agent's conversation for this project: messages, tool rows (command, ok) and whether a turn is "
                + "running.",
            parameters: [plugin]),
    ]

    private static let plugin = CommandParameter(
        "plugin", .string, "Chat agent plugin ID; by default the one shown in the dock, else the first",
        cli: .option("plugin"))
}
