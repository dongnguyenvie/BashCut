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
                + "changed and timedOut. A finished job returns at once. Use it instead of polling jobs status.",
            parameters: [
                CommandParameter("job", .string, "Job ID", required: true, cli: .positional),
                CommandParameter("timeout", .integer, "Seconds to wait at most",
                                 default: .integer(JobWaitDefaults.seconds), minimum: 1,
                                 maximum: JobWaitDefaults.maximum, cli: .option("timeout")),
            ]),
        CommandSpec(
            "capabilities.get", .read,
            "Whether each plugin capability (or one) can serve now: available, else reason missing (no plugin "
                + "provides it), not_configured (turned off, not approved, changed, outdated or missing a required "
                + "plugin) or unhealthy (a dependency fails its health check). Lists each provider with plugin, "
                + "priority, paid, state and detail, and the commands that call the capability. A command whose "
                + "capability cannot serve fails with category capability_missing and the same reason. With voices, "
                + "voices: the voices of every voice.synthesize provider (per provider plugin, name, availability, "
                + "clones (voice speak then needs cloneConsent) and the voice its plugin is set to; per voice id, "
                + "language, region, style, gender, supportsRate and measuredRate (rates measured on its takes, per "
                + "language: samples, p10, p50, p90)); without a capability the result is then {capabilities, voices}.",
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
    /// Where a media file came from and what its licence allows (P2-H8), recorded on `media import`.
    static let mediaRightsParameters = [
        CommandParameter("origin", .string, "Where the file came from", choices: ["stock", "ai", "own", "built-in"],
                         cli: .option("origin")),
        CommandParameter("license", .string, "Its licence: text as written, or a JSON object {id, "
                         + "redistribute, commercial, attribution…}; stored as given", cli: .option("license")),
        CommandParameter("source", .string, "Where it was found (URL)", cli: .option("source")),
        CommandParameter("author", .string, "Who made it, for the credit line", cli: .option("author")),
    ]
}

/// `jobs.wait` bounds (P2-G4): the socket client waits this long plus a margin for the answer.
public enum JobWaitDefaults {
    public static let seconds = 25
    public static let maximum = 30
}
