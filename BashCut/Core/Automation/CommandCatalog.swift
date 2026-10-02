import BashCutProject
import Foundation

/// Every automation command, declared once. Modes, CLI parsing, MCP tools and agent instructions derive from it.
public enum CommandCatalog {
    public static let exportPresets = ["tiktok", "youtube-1080", "youtube-4k", "quick-draft", "prores"]

    public static let specs: [CommandSpec] = readSpecs + editSpecs + capabilitySpecs + privilegedSpecs + uiSpecs

    public static let modes: [String: CommandMode] = Dictionary(uniqueKeysWithValues: specs.map { ($0.name, $0.mode) })

    public static func spec(named name: String) -> CommandSpec? { specs.first { $0.name == name } }

    private static let baseRevision = CommandParameter(
        "baseRev", .integer, "Current project revision from timeline.get", required: true, minimum: 0,
        cli: .option("base-rev"))
    private static let provider = CommandParameter(
        "provider", .string, "Provider ID overriding the project preference for one request", cli: .option("provider"))
    private static let outputName = CommandParameter(
        "name", .string, "Output base name without an extension", required: true, cli: .option("name"))
    private static let outputDirectory = CommandParameter(
        "directory", .string, "Output folder, relative to the project; defaults to its render folder",
        cli: .option("output-dir"))

    private static let readSpecs: [CommandSpec] = [
        CommandSpec("context.get", .read, "Read the project path, revision, playhead and selection."),
        CommandSpec("project.get", .read, "Read the whole open project document."),
        CommandSpec(
            "timeline.get", .read, "Read the revision, format and tracks, including track IDs and roles.",
            parameters: [
                CommandParameter(
                    "format", .string, "json (default) or a compact text listing", choices: ["json", "text"],
                    cli: .option("format"))
            ]),
        CommandSpec("media.list", .read, "List project media."),
        CommandSpec("review.run", .read, "Run the structural timeline review (not measured audio loudness)."),
        CommandSpec("captions.export", .read, "Export captions as SubRip text."),
        CommandSpec("export.status", .read, "Read the active export, or the most recent export receipt."),
        CommandSpec("plugins.list", .read, "List installed plugins, their providers and project provider preferences."),
        CommandSpec(
            "jobs.status", .read, "Read one provider-backed job, or all recent jobs when job is omitted.",
            parameters: [CommandParameter("job", .string, "Job ID", cli: .positional)]),
    ]

    private static let editSpecs: [CommandSpec] = [
        CommandSpec(
            "timeline.apply", .edit, "Atomically apply validated timeline operations as one undoable edit.",
            parameters: [
                CommandParameter("ops", .array, "Operations array (CLI: path to ops.json)", required: true,
                                 cli: .positionalJSONFile),
                baseRevision,
                CommandParameter("label", .string, "Short description of the edit", default: .string("Agent edit"),
                                 cli: .option("label")),
            ]),
        CommandSpec("timeline.undo", .edit, "Undo one timeline action.", parameters: [baseRevision]),
        CommandSpec("timeline.redo", .edit, "Redo one timeline action.", parameters: [baseRevision]),
        CommandSpec(
            "captions.import", .edit, "Import UTF-8 SubRip captions as one undoable edit.",
            parameters: [
                CommandParameter("text", .string, "SubRip text (CLI: path to a .srt file)", required: true,
                                 cli: .positionalTextFile(maximumBytes: SubRip.maximumBytes)),
                baseRevision,
                CommandParameter("replace", .boolean, "Replace existing captions", default: .bool(false),
                                 cli: .flag("replace")),
            ]),
    ]

    private static let capabilitySpecs: [CommandSpec] = [
        CommandSpec(
            "jobs.cancel", .edit, "Cancel a running provider-backed job.",
            parameters: [CommandParameter("job", .string, "Job ID", required: true, cli: .positional)]),
        CommandSpec(
            "captions.generate", .edit,
            "Transcribe project media with a captions.transcribe provider and import the captions as one undoable edit.",
            parameters: [
                CommandParameter("media", .string, "Project media ID", required: true, cli: .option("media")),
                CommandParameter("replace", .boolean, "Replace existing captions", default: .bool(false),
                                 cli: .flag("replace")),
                provider,
            ],
            execution: .job),
        CommandSpec(
            "beats.detect", .edit, "Detect beats in audio media and set its beat grid as one undoable edit.",
            parameters: [
                CommandParameter("media", .string, "Audio media ID already placed on the timeline", required: true,
                                 cli: .option("media")),
                provider,
            ],
            execution: .job),
        CommandSpec(
            "voice.speak", .edit, "Synthesize voice takes and insert the best take on the Voiceover track.",
            parameters: [
                CommandParameter("text", .string, "Voiceover text in the project content language", required: true,
                                 cli: .positional),
                CommandParameter("takes", .integer, "Number of takes to generate", default: .integer(3), minimum: 1,
                                 maximum: 8, cli: .option("takes")),
                CommandParameter("atFrame", .integer, "Timeline frame; defaults to the playhead", minimum: 0,
                                 cli: .option("at-frame")),
                provider,
            ],
            execution: .job),
    ]

    private static let privilegedSpecs: [CommandSpec] = [
        CommandSpec(
            "export.start", .privileged, "Request a background video export; the user approves it in the app first.",
            parameters: [
                CommandParameter("preset", .string, "Export preset", required: true, choices: exportPresets,
                                 cli: .option("preset")),
                outputName,
                outputDirectory,
                CommandParameter("includeSRT", .boolean, "Also write a SubRip file", default: .bool(false),
                                 cli: .flag("include-srt")),
                CommandParameter("normalizeAudio", .boolean, "Run two-pass LUFS normalization with a plugin",
                                 default: .bool(false), cli: .flag("normalize-audio")),
            ],
            execution: .approval),
        CommandSpec(
            "export.otio", .privileged, "Request an OpenTimelineIO export; the user approves it in the app first.",
            parameters: [outputName, outputDirectory],
            execution: .approval),
    ]

    private static let uiSpecs: [CommandSpec] = [
        CommandSpec(
            "ui.select", .ui, "Select a timeline item in the app; omit item to clear the selection.",
            parameters: [CommandParameter("item", .string, "Stable item ID", cli: .positional)]),
        CommandSpec(
            "ui.seek", .ui, "Move the viewer to a timeline frame.",
            parameters: [CommandParameter("frame", .integer, "Timeline frame", required: true, minimum: 0,
                                          cli: .positional)]),
        CommandSpec(
            "ui.notify", .ui, "Show a short status message in BashCut.",
            parameters: [CommandParameter("message", .string, "Message", required: true, cli: .positional)]),
    ]
}
