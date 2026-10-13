import BashCutProject

extension CommandCatalog {
    private static let exportReference = CommandParameter(
        "export", .string, "The export: its ID (x-…), index or path from export history; the latest by default",
        cli: .option("export"))

    /// The export ledger, post links, history across projects (P3-I2) and outcomes (P3-I3): facts for the creator's
    /// own benchmarks, never verdicts.
    static let ledgerSpecs: [CommandSpec] = [
        CommandSpec(
            "export.history", .read,
            "The project's export ledger, newest first: {index, id, rev, preset, path, seconds, completedAt, links "
                + "[{url, platform, postedAt}], outcomes (imported or not), hook {firstCutSeconds, firstTextSeconds, "
                + "firstText, firstMedia, cutsInHook, words}, sections (count)}. full adds each export's fingerprint "
                + "(look, caption and title presets, music, transitions, clips, average and median cut, sections). "
                + "Exports made before the ledger have no id, rev or fingerprint.",
            parameters: [
                CommandParameter("limit", .integer, "Exports to list", default: .integer(20), minimum: 1, maximum: 100,
                                 cli: .option("limit")),
                CommandParameter("full", .boolean, "Add the fingerprint of each export", cli: .flag("full")),
            ]),
        CommandSpec(
            "export.link", .edit,
            "Record where an export was posted: its URL, the platform and when it went live. The same URL again "
                + "replaces its platform and date. Needs a saved project.",
            parameters: [
                CommandParameter("url", .string, "The post's URL", required: true, cli: .option("url")),
                CommandParameter("platform", .string, "tiktok, youtube, reels… (platforms get lists them)",
                                 cli: .option("platform")),
                CommandParameter("postedAt", .string, "When it went live, ISO 8601 (2026-10-13 or 2026-10-13T18:00)",
                                 cli: .option("posted-at")),
                exportReference,
            ]),
        CommandSpec(
            "export.reveal-output", .ui,
            "Reveal an exported file in Finder, like the result card's per-file icon: the export by ID, index or path "
                + "from export history (the run's files are in run status result.outputs), the latest by default. "
                + "Returns its path.",
            parameters: [exportReference]),
        CommandSpec(
            "project.history", .read,
            "The last projects opened (Welcome screen order, the open one first), each with its exports, posted links "
                + "and the fingerprint of its latest export (the open project's current timeline when it has none), "
                + "then what they share: looks, caption presets, music and transitions with how many projects used each, "
                + "and the hook and cut numbers per project. For variety checks and the creator's own medians; no "
                + "verdicts.",
            parameters: [
                CommandParameter("limit", .integer, "Projects to read", default: .integer(10), minimum: 1, maximum: 50,
                                 cli: .option("limit")),
            ]),
        CommandSpec(
            "outcomes.import", .edit,
            "Import how an export performed: a retention curve and totals from the platform's analytics. JSON "
                + "{curve: [{t (seconds) | position (% of the video), retention}], totals: {views, likes, shares, "
                + "averageViewSeconds…}} or a list of points, or CSV with a header (a time or `Video position (%)` "
                + "column and a retention column; name them when the headers are unclear). Values the file lacks stay "
                + "null. Stored per export in .bashcut/outcomes; importing again replaces it. Needs an export from the "
                + "ledger (made with this version or later).",
            parameters: [
                CommandParameter("data", .string, "The file's text (CLI: path to a .csv or .json file)", required: true,
                                 cli: .positionalTextFile(maximumBytes: 4 * 1024 * 1024)),
                exportReference,
                CommandParameter("platform", .string, "Where the numbers come from (tiktok, youtube…)",
                                 cli: .option("platform")),
                CommandParameter("totals", .object, "Totals to add or override ({\"views\": 1200})", cli: .option("totals")),
                CommandParameter("timeColumn", .string, "CSV: the time column's header", cli: .option("time-column")),
                CommandParameter("retentionColumn", .string, "CSV: the retention column's header",
                                 cli: .option("retention-column")),
            ]),
        CommandSpec(
            "outcomes.map", .read,
            "Map an export's imported outcomes onto its sections (section markers when it was exported; the whole "
                + "video without them): per section startRetention, endRetention, change (raw), drop {at, change, "
                + "words}, lift {at, change}, replayPeak {at, retention} and viewsAtStart (views × start retention); "
                + "then the largest drops of the whole curve {at, from, to, change, section, words}, with the caption "
                + "words heard within window seconds. Retention is in the file's unit (percent or fraction). Missing "
                + "values are null; no verdicts.",
            parameters: [
                exportReference,
                CommandParameter("top", .integer, "Largest drops to list", default: .integer(3), minimum: 0, maximum: 20,
                                 cli: .option("top")),
                CommandParameter("window", .number, "Seconds of words on each side of a drop", default: .number(4),
                                 range: 0...30, cli: .option("window")),
            ]),
    ]
}
