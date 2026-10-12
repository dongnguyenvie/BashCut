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
    private static let skillScopes = ["project", "user", "plugin", "kit"]
    private static let skillSession = CommandParameter(
        "session", .string, "Your agent session ID, recorded as the source", cli: .option("session"))

    /// Skills (#71): the agent kit's and the plugins' (#377), read-only, and the ones the user and agents write for
    /// one project (`.bashcut/skills`, linked for Claude and Codex) or for every project
    /// (`Application Support/BashCut/Knowledge/skills`). Changes are recorded in knowledge history.
    static let skillSpecs: [CommandSpec] = [
        CommandSpec(
            "skills.list", .read,
            "List the skills agents can read. Scopes: this project's, the ones for every project (user), the ones trusted and enabled plugins ship "
                + "(plugin, read-only, named <plugin-id>:<name>) and the agent kit's (read-only), with whether agents "
                + "get them (enabled), their description and path.",
            parameters: [CommandParameter("scope", .string, "Only this scope", choices: skillScopes, cli: .option("scope"))]),
        CommandSpec(
            "skills.get", .read,
            "Read a skill's SKILL.md. Without scope, the project's skill wins over the one for every project, then a "
                + "plugin's (<plugin-id>:<name>, its agent name such as vlog-product-ad, or a bare name one plugin has), then the "
                + "kit's. To change a plugin's skill, save a copy with skills save. sections lists its ## headings; "
                + "section returns only the sections whose heading contains one of the given words (comma-separated), "
                + "and still counts as reading the skill.",
            parameters: [
                CommandParameter("name", .string, "Skill name; a plugin's is <plugin-id>:<name>", required: true,
                                 cli: .positional),
                CommandParameter("scope", .string, "Where to look", choices: skillScopes, cli: .option("scope")),
                CommandParameter("section", .string, "Only these sections: words of their headings, comma-separated",
                                 cli: .option("section")),
            ]),
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
            "skills.export", .edit,
            "Copy saved skills (for every project by default, or this project's) into a new or empty folder. With "
                + "asPlugin, the folder is a skill pack plugin (plugin.json with contributes.skills and no entrypoint) "
                + "that installs in another BashCut with plugins install --path, where its skills show in skills list.",
            parameters: [
                CommandParameter("output", .string, "New or empty folder to write", required: true, isPath: true,
                                 cli: .option("output")),
                CommandParameter("skills", .array, "Skill names; every skill of the scope by default",
                                 cli: .option("skills")),
                CommandParameter("scope", .string, "user (default: skills for every project) or project",
                                 default: .string("user"), choices: ["project", "user"], cli: .option("scope")),
                CommandParameter("asPlugin", .boolean, "Write a skill pack plugin around the skills", default: .bool(false),
                                 cli: .flag("as-plugin")),
                CommandParameter("id", .string, "With asPlugin: the plugin id, reverse-domain (me.my-skills)",
                                 cli: .option("id")),
                CommandParameter("name", .string, "With asPlugin: the plugin name; the id by default", cli: .option("name")),
                CommandParameter("version", .string, "With asPlugin: semantic version", default: .string("0.1.0"),
                                 cli: .option("version")),
                CommandParameter("author", .string, "With asPlugin: who wrote the skills (manifest author.name)",
                                 cli: .option("author")),
            ]),
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
