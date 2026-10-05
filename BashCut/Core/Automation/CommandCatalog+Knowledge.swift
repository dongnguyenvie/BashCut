import BashCutProject

extension CommandCatalog {
    private static let knowledgeScopes = ["project", "user"]
    private static let lessonStatuses = ["proposed", "active", "disabled"]
    private static let readScope = CommandParameter(
        "scope", .string, "Only this scope; both by default", choices: knowledgeScopes, cli: .option("scope"))
    private static let lessonID = CommandParameter(
        "id", .string, "Lesson ID (l-…) from knowledge lessons", required: true, cli: .positional)
    private static let session = CommandParameter(
        "session", .string, "Your agent session ID, recorded as the source", cli: .option("session"))
    private static let lessonFields: [CommandParameter] = [
        CommandParameter("symptom", .string, "What went wrong or what was noticed", cli: .option("symptom")),
        CommandParameter("cause", .string, "Why it happened", cli: .option("cause")),
        CommandParameter("fix", .string, "What to do next time", cli: .option("fix")),
        CommandParameter("evidence", .string, "What shows it (frames, files, the user's words)", cli: .option("evidence")),
        CommandParameter("tags", .string, "Comma-separated tags (captions, audio, pacing…)", cli: .option("tags")),
    ]
    private static let valueKey = CommandParameter("key", .string, "Key", required: true, cli: .positional)
    private static let valueText = CommandParameter(
        "value", .string, "Value; required unless remove is set", cli: .positional)
    private static let removeValue = CommandParameter(
        "remove", .boolean, "Remove the key instead of setting it", cli: .flag("remove"))

    /// Agent knowledge (Agent Knowledge sheet): memos and project skills, and the structured lessons, preferences,
    /// project facts, proposals and history (#67) stored as JSON in `.bashcut/knowledge/` and
    /// `Application Support/BashCut/Knowledge/`.
    static let knowledgeSpecs: [CommandSpec] = memoSpecs + lessonSpecs + valueSpecs + reviewSpecs

    private static let memoSpecs: [CommandSpec] = [
        CommandSpec(
            "knowledge.get", .read,
            "Read the project memo and skills (stored in the project folder), the notes for every project, and any "
                + "older memo left in the agent workspace or home folder (legacy)."),
        CommandSpec(
            "knowledge.memo", .edit,
            "Replace a memo: the project memo (.bashcut/agent-memory.md in the project) or, with scope user, the notes "
                + "every project reads (Application Support/BashCut/Knowledge). Agents need approval for scope user.",
            parameters: [
                CommandParameter("text", .string, "Memo text (CLI: path to a text file)", required: true,
                                 sensitive: true, cli: .positionalTextFile(maximumBytes: 256 * 1024)),
                CommandParameter("scope", .string, "project (default) or user", choices: knowledgeScopes,
                                 cli: .option("scope")),
            ]),
        CommandSpec(
            "knowledge.migrate", .edit,
            "Move the older memo that earlier versions kept in the agent workspace or home folder into the notes for "
                + "every project (default) or this project's memo; the old file is renamed agent-memory.migrated.md.",
            parameters: [CommandParameter("to", .string, "user (default) or project", choices: ["user", "project"],
                                          cli: .option("to"))]),
        CommandSpec(
            "knowledge.skill", .edit,
            "Write a project skill's SKILL.md in the project folder, creating the skill and linking it into the project's "
                + ".claude/skills and .agents/skills if needed. Needs a saved project.",
            parameters: [
                CommandParameter("name", .string, "Lowercase hyphenated skill name", required: true, cli: .positional),
                CommandParameter("text", .string, "SKILL.md text (CLI: path to a text file)", required: true,
                                 sensitive: true, cli: .positionalTextFile(maximumBytes: 256 * 1024)),
            ]),
    ]

    private static let lessonSpecs: [CommandSpec] = [
        CommandSpec(
            "knowledge.lessons", .read,
            "List lessons the agent learned (symptom, cause, fix), from this project and for every project, newest "
                + "first. Read the active ones before editing; proposed ones wait for the user's review.",
            parameters: [
                readScope,
                CommandParameter("status", .string, "Only this status", choices: lessonStatuses,
                                 cli: .option("status")),
                CommandParameter("tag", .string, "Only lessons with this tag", cli: .option("tag")),
                CommandParameter("query", .string, "Text to find in the title, symptom, cause, fix, evidence or tags",
                                 cli: .option("query")),
                CommandParameter("sort", .string, "Order by last change; newest first by default",
                                 default: .string("newest"), choices: ["newest", "oldest"], cli: .option("sort")),
            ]),
        CommandSpec(
            "knowledge.add-lesson", .edit,
            "Record a lesson: in this project (default) or, with scope user, for every project. Use status proposed "
                + "when unsure. Agents' lessons for every project are always proposed until the user approves them.",
            parameters: [CommandParameter("title", .string, "Short title", required: true, cli: .positional)]
                + lessonFields + [
                    CommandParameter("scope", .string, "project (default) or user", default: .string("project"),
                                     choices: knowledgeScopes, cli: .option("scope")),
                    CommandParameter("status", .string, "active (default) or proposed", default: .string("active"),
                                     choices: ["active", "proposed"], cli: .option("status")),
                    session,
                ]),
        CommandSpec(
            "knowledge.update-lesson", .edit,
            "Change a lesson's fields or status (proposed, active, disabled). Agents changing a lesson for every "
                + "project need approval.",
            parameters: [lessonID, CommandParameter("title", .string, "Short title", cli: .option("title"))]
                + lessonFields + [
                    CommandParameter("status", .string, "New status", choices: lessonStatuses,
                                     cli: .option("status")),
                    session,
                ]),
        CommandSpec(
            "knowledge.remove-lesson", .edit,
            "Remove a lesson (history keeps it). Agents removing a lesson for every project need approval.",
            parameters: [lessonID, session]),
    ]

    private static let valueSpecs: [CommandSpec] = [
        CommandSpec(
            "knowledge.prefs", .read,
            "Read the user's preferences (taste: length, pace, voice, caption style, music…). A project value wins "
                + "over the one for every project.",
            parameters: [CommandParameter("key", .string, "Only this key", cli: .positional), readScope]),
        CommandSpec(
            "knowledge.set-pref", .edit,
            "Set or remove a preference: for every project (default; agents need approval) or only this project.",
            parameters: [
                valueKey, valueText, removeValue,
                CommandParameter("scope", .string, "user (default) or project", default: .string("user"),
                                 choices: knowledgeScopes, cli: .option("scope")),
                session,
            ]),
        CommandSpec(
            "knowledge.facts", .read,
            "Read this project's facts (people, places, footage notes, what was approved).",
            parameters: [CommandParameter("key", .string, "Only this key", cli: .positional)]),
        CommandSpec(
            "knowledge.set-fact", .edit, "Set or remove a fact about this project. Needs a saved project.",
            parameters: [valueKey, valueText, removeValue, session]),
    ]

    private static let reviewSpecs: [CommandSpec] = [
        CommandSpec(
            "knowledge.proposals", .read, "List proposed lessons waiting for the user's review.",
            parameters: [readScope]),
        CommandSpec(
            "knowledge.approve", .edit,
            "Approve a proposed lesson so agents follow it. The user decides: an agent's request asks for approval.",
            parameters: [lessonID]),
        CommandSpec(
            "knowledge.reject", .edit,
            "Reject a proposed lesson; it is removed and history keeps it. An agent's request asks for approval.",
            parameters: [lessonID]),
        CommandSpec(
            "knowledge.history", .read,
            "List changes to lessons, preferences and facts, newest first, with who made them and the entry before "
                + "and after.",
            parameters: [
                readScope,
                CommandParameter("limit", .integer, "Number of changes", default: .integer(50), minimum: 1,
                                 maximum: 500, cli: .option("limit")),
            ]),
    ]
}
