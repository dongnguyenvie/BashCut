import BashCutProject

extension CommandCatalog {
    /// Saved cloned voices ("My voices", #532) and the project's voice: the Voice panel's picker and its Clone a voice
    /// sheet.
    static let voiceCloneSpecs: [CommandSpec] = [
        CommandSpec(
            "voice.clone-add", .privileged,
            "Save a cloned voice to My voices. From a media ID or a sound/video file (for every project), BashCut "
                + "picks the best clean window within the cloning provider's reference range (most speech by Apple's "
                + "on-device sound classifier, levels as the fallback; fewest pauses, no clipping or music), checks it "
                + "and refuses with a reason (tooShort, tooQuiet, mostlySilence, notEnoughSpeech, clipped, musicUnder; "
                + "data.checks says what was measured). A second speaker is not detected (notChecked). Saving asks "
                + "the user first: the consent is theirs. Returns window {start, end, seconds} in source seconds, "
                + "range, checks [{id, passed, value, detail}], providers (that can speak with it), approval and, once "
                + "saved, clone (as voice clone-list shows it).",
            parameters: [
                CommandParameter("name", .string, "Name of the voice, such as Giọng Nolan", required: true, cli: .option("name")),
                CommandParameter("from", .string, "Project media ID or file path (relative to the project folder)",
                                 required: true, cli: .option("from")),
                CommandParameter("at", .number, "Start of the part to use, in source seconds", range: 0...86_400,
                                 cli: .option("at")),
                CommandParameter("to", .number, "End of the part to use, in source seconds", range: 0...86_400,
                                 cli: .option("to")),
                CommandParameter("consent", .string, "The user's consent: own (their own voice) or permission (they have "
                                 + "the speaker's permission)", required: true, choices: ["own", "permission"],
                                 cli: .option("consent")),
                CommandParameter("language", .string, "BCP 47 language the voice speaks; the content language by default",
                                 cli: .option("language")),
                CommandParameter("provider", .string, "Cloning provider whose reference range to trim to",
                                 cli: .option("provider")),
            ],
            execution: .approval),
        CommandSpec(
            "voice.clone-list", .read,
            "List My voices: per saved clone id, name, kind clone, source my-voices, language, providers (installed ones "
                + "that can speak with it), savedFor, durationSeconds, sourceDescription, createdAt, consent {by, at, "
                + "statement}, reference (the clip's path) and current (this project speaks with it)."),
        CommandSpec(
            "voice.clone-remove", .privileged,
            "Remove a saved clone from My voices (every project) after the user approves; a project using it goes back "
                + "to its plugin's voice.",
            parameters: [CommandParameter("voice", .string, "Clone ID (clone-…)", required: true, cli: .positional)],
            execution: .approval),
        CommandSpec(
            "voice.use", .edit,
            "Choose the project's voice. Like the Voice panel picker, a saved clone ID sets the project's voiceClone; a "
                + "preset (voice or provider/voice) sets its plugin's voice option and the voice provider and clears "
                + "voiceClone; default clears voiceClone (the plugin's own voice). voice speak and voice lines then "
                + "speak with it.",
            parameters: [
                CommandParameter("voice", .string, "Clone ID, preset voice (provider/voice) or default", required: true,
                                 cli: .positional),
            ]),
    ]
}
