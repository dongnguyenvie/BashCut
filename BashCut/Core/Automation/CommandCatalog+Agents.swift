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
}
