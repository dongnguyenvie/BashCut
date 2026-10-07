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
                + "capability cannot serve fails with category capability_missing and the same reason.",
            parameters: [
                CommandParameter("capability", .string, "Capability ID, such as captions.transcribe; all by default",
                                 cli: .positional),
                CommandParameter("kind", .string, "Only providers serving this library item kind",
                                 choices: libraryKinds, cli: .option("kind")),
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

/// `jobs.wait` bounds (P2-G4): the socket client waits this long plus a margin for the answer.
public enum JobWaitDefaults {
    public static let seconds = 25
    public static let maximum = 30
}
