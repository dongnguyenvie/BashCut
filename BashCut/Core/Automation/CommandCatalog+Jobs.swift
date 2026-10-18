import BashCutProject

/// Jobs and plugin capabilities (P2-G4, P2-G5).
extension CommandCatalog {
    static let jobSpecs: [CommandSpec] = [
        CommandSpec(
            "jobs.status", .read,
            "Read one job (plugin call or export), or all recent jobs when job is omitted. Each job has state, "
                + "progress, step and usage {provider, wallSec, units, costUSD, costSource}: units and cost only as "
                + "a provider reported them, never estimated.",
            parameters: [CommandParameter("job", .string, "Job ID", cli: .positional)]),
        CommandSpec(
            "jobs.wait", .read,
            "Wait until a job's state or step changes, or it finishes, up to timeout seconds; returns the job, "
                + "changed and timedOut. With done, only when it finishes. A finished job returns at once. Use it "
                + "instead of polling jobs status. Several job IDs (comma-separated) wait until all have finished: "
                + "{jobs, finished, timedOut}.",
            parameters: [
                CommandParameter("job", .string, "Job ID, or several comma-separated", required: true, cli: .positional),
                CommandParameter("timeout", .integer, "Seconds to wait at most; more than "
                                 + "\(JobWaitDefaults.maximum) waits \(JobWaitDefaults.maximum) (waitedAtMost says so): call again",
                                 default: .integer(JobWaitDefaults.seconds), minimum: 1,
                                 maximum: 86_400, cli: .option("timeout")),
                CommandParameter("done", .boolean, "Return only when the job has finished (or timeout passed), "
                                 + "not on a step change", default: .bool(false), cli: .flag("done")),
            ]),
        CommandSpec(
            "capabilities.get", .read,
            "Whether each plugin capability (or one) can serve now: available, else reason missing (no plugin "
                + "provides it), not_configured (turned off, not approved, changed, outdated or missing a required "
                + "plugin) or unhealthy (a dependency fails its health check). Lists each provider with plugin, "
                + "priority, paid, state and detail, and the commands that call the capability. A command whose "
                + "capability cannot serve fails with category capability_missing and the same reason. With voices, "
                + "voices: the voices of every voice.synthesize provider (per provider plugin, name, availability, "
                + "clones and cloneRange {minSeconds, maxSeconds}, and the voice its plugin is set to; per voice id, kind "
                + "(preset, or clone: a saved voice from My voices, listed first under the providers that can speak "
                + "with it), source (the provider ID, or my-voices), "
                + "language, region, style, gender, supportsRate, speaksContentLanguage (when the project has a content "
                + "language) and measuredRate (rates measured on its takes, per "
                + "language: samples, p10, p50, p90)), and projectVoice (the saved clone the project speaks with, set "
                + "by voice use); without a capability the result is then {capabilities, voices}.",
            parameters: [
                CommandParameter("capability", .string, "Capability ID, such as captions.transcribe; all by default",
                                 cli: .positional),
                CommandParameter("kind", .string, "Only providers serving this library item kind",
                                 choices: libraryKinds, cli: .option("kind")),
                CommandParameter("voices", .boolean, "Add the voices of the voice providers", cli: .flag("voices")),
            ]),
        CommandSpec(
            "jobs.cancel", .edit, "Cancel a queued or running job (plugin call or export).",
            parameters: [CommandParameter("job", .string, "Job ID", required: true, cli: .positional)]),
    ]

    /// For commands that may call a paid provider (P2-G4): a stable request ID and a dry run.
    static let paidRequestParameters = [
        CommandParameter("requestId", .string, "Your stable ID for this request: sending it again returns the same "
                         + "job instead of starting (and paying for) another; the provider receives it too",
                         cli: .option("request-id")),
        CommandParameter("dryRun", .boolean, "Return the request as it would go to the provider (without option "
                         + "values), whether the provider is paid and its estimate if it gives one; nothing runs",
                         default: .bool(false), cli: .flag("dry-run")),
    ]
}

extension CommandCatalog {
    /// `export start --wait --save`: the finished job in the same call, then the project saved.
    /// The written file: its bit rate, and whether an earlier export of the name is replaced (#507-23).
    static let exportFileParameters = [
        CommandParameter("bitrate", .number, "Video bit rate in Mbps instead of the preset's", range: 0.5...200,
                         cli: .option("bitrate")),
        CommandParameter("overwrite", .boolean, "Replace an earlier export of this name instead of suffixing it",
                         default: .bool(false), cli: .flag("overwrite")),
    ]

    /// `export.start`'s summary from the output name on.
    static let exportNameOverwriteAndWithout = " A name already on disk or queued gets the next free suffix (name-2…; "
        + "the result says renamedFrom); overwrite replaces the files on disk (moved to the Trash) instead. "
        + exportWithoutSummary

    /// `export.start`'s stages guard, part of its summary.
    static let exportStagesNote = "Every stage the plan marks required before review must be done or skipped with a "
        + "reason: else stage_pending. "

    /// `export.start`'s graphics guard (#634), part of its summary.
    static let exportGraphicsDraftNote = "It also refuses graphics a plugin rendered as drafts (media "
        + "data.graphics.draft): else graphics_draft, listing them and the plugin's final render (bin/graphic plan "
        + "--final or rerender --all --final). When a ready plugin contributes an export step whose when holds (plugin "
        + "API 12, e.g. HyperFrames finalising draft graphics), a final export runs it first unless no-steps: job is "
        + "then the steps' job (exportSteps lists them; its result names the export jobs), the step applies its own "
        + "change in one undo step, and the guards run again before exporting; a failed or cancelled step exports "
        + "nothing."

    /// Leaves out plugin export steps (#634): the draft-graphics guard then refuses drafts as before.
    static let exportNoSteps = CommandParameter(
        "noSteps", .boolean, "Do not run plugin export steps first (a final export over draft graphics is then refused)",
        default: .bool(false), cli: .flag("no-steps"))

    /// One output (`preset`) or several in one request (`presets`, #593): give exactly one.
    static let exportPresetParameters = [
        CommandParameter("preset", .string, "Export preset (one output; or give presets)", choices: exportPresets,
                         cli: .option("preset")),
        CommandParameter("presets", .string, "Several export presets, comma separated (tiktok,shorts): one job each",
                         cli: .option("presets")),
    ]

    /// `export.start`'s several outputs (#593), part of its summary.
    static let exportPresetsNote = " With presets, one approval queues an export per preset, each named "
        + "name-<preset> (trip-tiktok, trip-shorts); the result lists them in exports (preset, output, job) and wait "
        + "waits for the last."

    static let exportWaitParameters = [
        CommandParameter("wait", .boolean, "When it starts at once, wait up to 100 s for it to finish and return the job",
                         default: .bool(false), cli: .flag("wait")),
        CommandParameter("save", .boolean, "Save the project after a waited export lands", default: .bool(false),
                         cli: .flag("save")),
    ]

    /// Where a media file came from and what its licence allows (P2-H8), recorded on `media import`.
    static let mediaRightsParameters = [
        CommandParameter("origin", .string, "Where the file came from: stock (a stock library), web (downloaded from "
                         + "another page, such as a CC BY clip), ai, own (the user's footage) or built-in",
                         choices: Provenance.origins, cli: .option("origin")),
        CommandParameter("license", .string, "Its licence: text as written, or a JSON object {id, "
                         + "redistribute, commercial, attribution…}; stored as given", cli: .option("license")),
        CommandParameter("source", .string, "Where it was found (URL)", cli: .option("source")),
        CommandParameter("author", .string, "Who made it, for the credit line", cli: .option("author")),
    ]
}

/// `jobs.wait` bounds (P2-G4): the socket client waits this long plus a margin for the answer. The maximum keeps
/// the call inside an agent shell's usual 2-minute command limit; a longer timeout is cut to it, not refused.
public enum JobWaitDefaults {
    public static let seconds = 25
    public static let maximum = 110
}
