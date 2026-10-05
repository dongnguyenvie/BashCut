import BashCutProject

extension CommandCatalog {
    private static let skillName = CommandParameter(
        "name", .string, "Skill name (lowercase, hyphenated)", required: true, cli: .positional)
    private static let skillText = CommandParameter(
        "text", .string, "SKILL.md text (CLI: path to a text file)", required: true, sensitive: true,
        cli: .positionalTextFile(maximumBytes: 256 * 1024))
    private static let writableScope = CommandParameter(
        "scope", .string, "project (default) or user (every project)", default: .string("project"),
        choices: ["project", "user"], cli: .option("scope"))
    private static let skillSession = CommandParameter(
        "session", .string, "Your agent session ID, recorded as the source", cli: .option("session"))

    /// Skills (#71): the agent kit's, read-only, and the ones the user and agents write for one project
    /// (`.bashcut/skills`, linked for Claude and Codex) or for every project (`Application Support/BashCut/Knowledge/
    /// skills`). Changes are recorded in knowledge history.
    static let skillSpecs: [CommandSpec] = [
        CommandSpec(
            "skills.list", .read,
            "List skills: the agent kit's (read-only), the ones for every project (user) and this project's, with "
                + "whether agents get them (enabled) and their description.",
            parameters: [CommandParameter("scope", .string, "Only this scope", choices: ["kit", "user", "project"],
                                          cli: .option("scope"))]),
        CommandSpec(
            "skills.get", .read,
            "Read a skill's SKILL.md. Without scope, the project's skill wins over the one for every project, which wins "
                + "over the kit's.",
            parameters: [skillName, CommandParameter("scope", .string, "Where to look", choices: ["kit", "user", "project"],
                                                     cli: .option("scope"))]),
        CommandSpec(
            "skills.save", .edit,
            "Write a skill's SKILL.md, creating the skill if needed: in the project (linked for Claude and Codex; needs "
                + "a saved project) or, with scope user, for every project (agents need approval). Kit skills are "
                + "read-only: use skills propose.",
            parameters: [skillName, skillText, writableScope, skillSession]),
        CommandSpec(
            "skills.enable", .edit,
            "Turn a skill on for agents: a project skill is linked into the project's .claude/skills and "
                + ".agents/skills; a skill for every project is listed in the agents' knowledge again. Agents need "
                + "approval for scope user.",
            parameters: [skillName, writableScope]),
        CommandSpec(
            "skills.disable", .edit,
            "Turn a skill off without deleting it: a project skill is unlinked from the project's agent folders; a "
                + "skill for every project is left out of the agents' knowledge. Agents need approval for scope user.",
            parameters: [skillName, writableScope]),
        CommandSpec(
            "skills.remove", .edit,
            "Delete a project skill or a skill for every project (history keeps its text; knowledge revert brings it "
                + "back). Agents need approval for scope user.",
            parameters: [skillName, writableScope, skillSession]),
        CommandSpec(
            "skills.propose", .edit,
            "Propose a change to an agent kit skill: the line diff against the kit's SKILL.md waits in the Knowledge "
                + "inbox as a lesson for every project tagged kit. The kit itself is not changed.",
            parameters: [
                skillName, skillText,
                CommandParameter("summary", .string, "What the change does, in a few words", required: true,
                                 cli: .option("summary")),
                CommandParameter("reason", .string, "What happened that shows the kit is wrong or missing a step",
                                 cli: .option("reason")),
                skillSession,
            ]),
    ]
}
