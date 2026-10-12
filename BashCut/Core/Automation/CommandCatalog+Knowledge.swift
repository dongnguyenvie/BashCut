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
        CommandParameter("evidence", .string, "What shows it (frames, files, the user's words quoted)",
                         cli: .option("evidence")),
        CommandParameter("check", .string, "Question to ask before the next draft (empty clears)",
                         cli: .option("check")),
        CommandParameter("tags", .string, "Comma-separated tags (captions, audio, pacing…)", cli: .option("tags")),
    ]
    private static let valueKey = CommandParameter("key", .string, "Key", required: true, cli: .positional)
    private static let valueText = CommandParameter(
        "value", .string, "Value; required unless remove is set", cli: .positional)
    private static let removeValue = CommandParameter(
        "remove", .boolean, "Remove the key instead of setting it", cli: .flag("remove"))

    /// Agent knowledge (Agent Knowledge sheet): memos and project skills, and the structured lessons, preferences,
    /// project facts, proposals and history with revert (#67, #70) stored as JSON in `.bashcut/knowledge/` and
    /// `Application Support/BashCut/Knowledge/`.
    static let knowledgeSpecs: [CommandSpec] = memoSpecs + lessonSpecs + valueSpecs + claimSpecs + reviewSpecs

    private static let memoSpecs: [CommandSpec] = [
        CommandSpec(
            "knowledge.get", .read,
            "Read the project memo and skills (stored in the project folder), the notes for every project, and any "
                + "older memo left in the agent workspace or home folder (legacy)."),
        CommandSpec(
            "knowledge.memo", .edit,
            "Replace a memo: the project memo (.bashcut/agent-memory.md in the project) or, with scope user, the notes "
                + "every project reads (Application Support/BashCut/Knowledge). clear empties it. Agents need approval "
                + "for scope user.",
            parameters: [
                CommandParameter("text", .string, "Memo text (CLI: path to a text file); omit it with clear",
                                 sensitive: true, cli: .positionalTextFile(maximumBytes: 256 * 1024)),
                CommandParameter("clear", .boolean, "Empty the memo instead of replacing its text", cli: .flag("clear")),
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
            "knowledge.split-memo", .edit,
            "Split a memo into structured entries, once (#72): read it with knowledge get, then pass a JSON object "
                + "{\"lessons\": [{\"title\", \"symptom\", \"cause\", \"fix\", \"evidence\", \"tags\"}], \"prefs\": "
                + "[{\"key\", \"value\"}], \"facts\": [{\"key\", \"value\"}]} of what it says. Everything waits in the "
                + "Knowledge inbox for the user's review; entries that already exist are skipped. The memo stays as "
                + "notes. With keep, nothing is split and the split is not offered again.",
            parameters: [
                CommandParameter("entries", .object, "What the memo says (CLI: path to a JSON file); required unless "
                                 + "keep is set", sensitive: true, cli: .positionalJSONFile),
                CommandParameter("scope", .string, "The memo to split: project (default) or user (notes for every "
                                 + "project; no facts)", choices: knowledgeScopes, cli: .option("scope")),
                CommandParameter("keep", .boolean, "Keep the memo as notes only and stop offering the split",
                                 cli: .flag("keep")),
                session,
            ]),
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
                + "first. Each has occurrences (times seen), lastSeen and sources (projects it was seen in) when "
                + "counted. Read the active ones before editing; proposed ones wait for the user's review.",
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
            "Change a lesson's fields or status, or count a sighting (seen). Status is proposed, active or disabled; "
                + "seen adds 1 to occurrences, sets lastSeen and adds this project to sources. Agents changing a lesson for every "
                + "project need approval; seen alone does not.",
            parameters: [lessonID, CommandParameter("title", .string, "Short title", cli: .option("title"))]
                + lessonFields + [
                    CommandParameter("status", .string, "New status", choices: lessonStatuses,
                                     cli: .option("status")),
                    CommandParameter("seen", .boolean, "The problem happened again: count it", cli: .flag("seen")),
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
            "Read the user's preferences (taste: length, pace, voice, caption style, music…). Each has confirmedBy "
                + "(user: said or approved by the user; inferred: an agent's guess). A project value wins over the one "
                + "for every project.",
            parameters: [CommandParameter("key", .string, "Only this key", cli: .positional), readScope]),
        CommandSpec(
            "knowledge.set-pref", .edit,
            "Set or remove a preference: for every project (default) or only this project. An agent's change for every "
                + "project waits in the Knowledge inbox (approval proposed) unless the user lets agents act without "
                + "confirmation. creator.* keys are the creator's profile (name, handle, channel, platforms, language, "
                + "niche, audience, tone, cta, voiceSamples as media IDs, disclosure; lists comma-separated), shown as "
                + "one object in context get; an agent's creator.* change for every project always waits for approval.",
            parameters: [
                valueKey, valueText, removeValue,
                CommandParameter("scope", .string, "user (default) or project", default: .string("user"),
                                 choices: knowledgeScopes, cli: .option("scope")),
                CommandParameter("confirmedBy", .string, "user when the user said it, inferred when you guessed it "
                                 + "(default for agents)", choices: ["user", "inferred"],
                                 cli: .option("confirmed-by")),
                session,
            ]),
        CommandSpec(
            "knowledge.facts", .read,
            "Read this project's facts (people, places, footage notes, what was approved). Each has evidence "
                + "{source, measure, n, status measured|estimated|user} when given.",
            parameters: [CommandParameter("key", .string, "Only this key", cli: .positional)]),
        CommandSpec(
            "knowledge.set-fact", .edit,
            "Set or remove a fact about this project. Give where it comes from: source (URL, file, frame, the user), "
                + "measure (the command or result path that gave it), n (sample size) and status. Plans and skills "
                + "refer to a fact by its key. Needs a saved project.",
            parameters: [
                valueKey, valueText, removeValue,
                CommandParameter("source", .string, "Where it comes from: a URL, a file, a frame, user",
                                 cli: .option("source")),
                CommandParameter("measure", .string, "The measurement that gave it (review.measure pace.median, "
                                 + "media analyze C0042)", cli: .option("measure")),
                CommandParameter("n", .integer, "Sample size behind it", minimum: 0, maximum: 100_000_000,
                                 cli: .option("n")),
                CommandParameter("status", .string, "measured, estimated or user (said by the user)",
                                 choices: ["measured", "estimated", "user"], cli: .option("status")),
                session,
            ]),
    ]

    private static let claimSpecs: [CommandSpec] = [
        CommandSpec(
            "knowledge.claims", .read,
            "Read this project's claims ledger: {key, text, source, author} for each number, price, superlative or "
                + "name the video states. Review lists those in titles and the voiceover that no claim's text covers "
                + "(unsourced-claim, info)."),
        CommandSpec(
            "knowledge.set-claim", .edit,
            "Record a claim the video makes and its source, or remove it: text as the video states it (\"528 ha\", "
                + "\"rẻ nhất\", \"Phở Thìn\"), source a URL, a frame (MEDIA@SECONDS), a file or user. Needs a saved "
                + "project.",
            parameters: [
                valueKey,
                CommandParameter("text", .string, "The claim as stated; required unless remove is set", cli: .option("text")),
                CommandParameter("source", .string, "URL, MEDIA@SECONDS, a file, or user; required unless remove is set",
                                 cli: .option("source")),
                removeValue, session,
            ]),
    ]

    private static let reviewSpecs: [CommandSpec] = [
        CommandSpec(
            "knowledge.proposals", .read,
            "List what waits for the user's review in the Knowledge inbox: proposed lessons (type lesson, id l-…) and "
                + "agents' preference changes for every project (type value, id p-…; value null removes the key).",
            parameters: [readScope]),
        CommandSpec(
            "knowledge.approve", .edit,
            "Approve a proposal: a proposed lesson becomes active, a preference change is applied. The user decides: "
                + "an agent's request asks for approval.",
            parameters: [
                CommandParameter("id", .string, "Proposal ID (l-… or p-…) from knowledge proposals", required: true,
                                 cli: .positional),
                CommandParameter("value", .string, "For a preference proposal: apply this value instead (edit)",
                                 cli: .option("value")),
                session,
            ]),
        CommandSpec(
            "knowledge.reject", .edit,
            "Reject a proposal: a proposed lesson is removed, a preference change is dropped; history keeps both. An "
                + "agent's request asks for approval.",
            parameters: [
                CommandParameter("id", .string, "Proposal ID (l-… or p-…) from knowledge proposals", required: true,
                                 cli: .positional),
                session,
            ]),
        CommandSpec(
            "knowledge.history", .read,
            "List changes to lessons, preferences, facts, memos and project skills, newest first: who made them, the "
                + "entry before and after, and a line diff. Undo one with knowledge revert.",
            parameters: [
                readScope,
                CommandParameter("kind", .string, "Only changes to this kind of entry",
                                 choices: ["lesson", "prefs", "facts", "memo", "skill"], cli: .option("kind")),
                CommandParameter("target", .string, "Only changes to this lesson ID, key or skill name",
                                 cli: .option("target")),
                CommandParameter("limit", .integer, "Number of changes", default: .integer(50), minimum: 1,
                                 maximum: 500, cli: .option("limit")),
            ]),
        CommandSpec(
            "knowledge.verdicts", .read,
            "What the user did with agents' changes in this project, as BashCut saw it: keep (dismissed the change "
                + "notice, or the next edit left the agent's items alone), undo, edit (the next edit changed the same "
                + "items) and reject (the scope guard's Reject). Returns total, counts {subject: {verdict: n}} by the "
                + "command that made the change (timeline.apply, library.apply, library.place, plan.apply…; edit when "
                + "unknown) and the newest rows {verdict, signal, subject, label, agent, rev, items, date}. Facts only: "
                + "no reasons.",
            parameters: [
                CommandParameter("verdict", .string, "Only this verdict", choices: ["keep", "undo", "reject", "edit"],
                                 cli: .option("verdict")),
                CommandParameter("subject", .string, "Only changes made by this command", cli: .option("subject")),
                CommandParameter("limit", .integer, "Rows to return (counts cover all)", default: .integer(20),
                                 minimum: 0, maximum: 500, cli: .option("limit")),
            ]),
        CommandSpec(
            "knowledge.revert", .edit,
            "Put an entry back to how it was before a change from knowledge history: a removed entry comes back, an "
                + "added one goes, an edit is undone (later changes to the same entry too). History records the revert. "
                + "Agents reverting a change for every project need approval.",
            parameters: [
                CommandParameter("id", .string, "Change ID from knowledge history", required: true, cli: .positional),
                session,
            ]),
    ]
}
