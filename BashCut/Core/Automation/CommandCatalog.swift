import BashCutProject
import Foundation

/// Every automation command, declared once. Modes, CLI parsing, MCP tools and agent instructions derive from it.
public enum CommandCatalog {
    /// Left-rail library panels, matching `LibraryTab` (checked by `EditorUIStateTests`).
    /// Sheets and popovers `ui.open` can show.
    public static let dialogs = [
        "new-project", "export", "export-report", "agent-changes", "review", "history", "plugins", "settings",
        "doctor", "knowledge", "ask", "sections", "external-changes",
    ]
    public static let libraryPanels = ["media", "audio", "text", "stickers", "effects", "transitions", "filters", "voice"]
    public static let exportPresets = ["tiktok", "youtube-1080", "youtube-4k", "quick-draft", "prores"]

    public static let specs: [CommandSpec] = readSpecs + projectSpecs + editSpecs + layerSpecs + capabilitySpecs + privilegedSpecs + uiSpecs
        + toolSpecs

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
        CommandSpec(
            "export.status", .read,
            "Read the export state: while one runs, its job, step, preset and path (last receipt under lastExport); "
                + "otherwise the most recent receipt. Includes the queue (job IDs for jobs.cancel)."),
        CommandSpec("plugins.list", .read, "List installed plugins, their providers and project provider preferences."),
        CommandSpec(
            "jobs.status", .read, "Read one job (plugin call or export), or all recent jobs when job is omitted.",
            parameters: [CommandParameter("job", .string, "Job ID", cli: .positional)]),
    ]

    private static let leaveCurrent = [
        CommandParameter("saveCurrent", .boolean, "Save the open project first when it has unsaved changes",
                         default: .bool(false), cli: .flag("save-current")),
        CommandParameter("discardCurrent", .boolean, "Drop unsaved changes of the open project",
                         default: .bool(false), cli: .flag("discard-current")),
    ]

    private static let projectSpecs: [CommandSpec] = [
        CommandSpec(
            "project.open", .edit,
            "Open a project.bashcut.json (or its folder). Fails if the open project has unsaved changes "
                + "unless saveCurrent or discardCurrent is set. In-app agent tabs close; external agents keep access.",
            parameters: [
                CommandParameter("path", .string, "Absolute path to project.bashcut.json or its folder", required: true,
                                 isPath: true, cli: .positional)
            ] + leaveCurrent),
        CommandSpec(
            "project.create", .edit,
            "Create a project folder (media, footage, render…) like the New Project wizard and open it.",
            parameters: [
                CommandParameter("name", .string, "Project name", required: true, cli: .option("name")),
                CommandParameter("directory", .string, "Absolute parent folder for the new project folder",
                                 required: true, isPath: true, cli: .option("dir")),
                CommandParameter("footage", .string, "Footage folder to link (never modified)", isPath: true,
                                 cli: .option("footage")),
                CommandParameter("canvas", .string, "Canvas", default: .string("portrait"),
                                 choices: ["portrait", "landscape", "square"], cli: .option("canvas")),
                CommandParameter("resolution", .string, "Short-side resolution", default: .string("1080"),
                                 choices: ["720", "1080", "2160"], cli: .option("resolution")),
                CommandParameter("fps", .string, "Frame rate", default: .string("29.97"),
                                 choices: ["29.97", "30", "24", "60"], cli: .option("fps")),
                CommandParameter("language", .string, "Content language tag", default: .string("vi"),
                                 cli: .option("language")),
                CommandParameter("style", .string, "Style preset", default: .string("food-review"),
                                 choices: ["food-review", "cinematic", "custom"], cli: .option("style")),
            ] + leaveCurrent),
        CommandSpec("project.save", .edit, "Save the open project to disk."),
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

    private static let layerSpecs: [CommandSpec] = [
        CommandSpec(
            "layers.add", .edit,
            "Add an empty layer: visual layers go to the front of the picture stack, audio layers below the others.",
            parameters: [
                CommandParameter("kind", .string, "Layer kind", required: true, choices: ["video", "text", "audio"],
                                 cli: .option("kind")),
                CommandParameter("role", .string, "Role such as overlay, captions, music or sfx; never main",
                                 cli: .option("role")),
                CommandParameter("name", .string, "Display name", cli: .option("name")),
                baseRevision,
            ]),
        CommandSpec(
            "media.import", .edit,
            "Add a media file to the project (path relative to the project folder or absolute); "
                + "with place, also put it on a layer like the Import button.",
            parameters: [
                CommandParameter("path", .string, "Media file path", required: true, isPath: true, cli: .positional),
                CommandParameter("kind", .string, "Media kind", default: .string("video"), choices: ["video", "audio"],
                                 cli: .option("kind")),
                CommandParameter("place", .boolean, "Also place it on a layer", default: .bool(false),
                                 cli: .flag("place")),
                CommandParameter("track", .string, "Layer ID for place; defaults to the main layer",
                                 cli: .option("track")),
                CommandParameter("atFrame", .integer, "Timeline frame for place", minimum: 0, cli: .option("at-frame")),
                baseRevision,
            ]),
        CommandSpec(
            "media.proxy", .edit,
            "Queue preview proxies (smaller, quick-to-seek copies in .bashcut/proxies; export keeps the originals) "
                + "for heavy video media, or one media item. Imports queue them automatically. Returns a status per "
                + "media: queued with its job ID, exists, not-needed or skipped.",
            parameters: [
                CommandParameter("media", .string, "Project media ID; all video media by default", cli: .positional),
                CommandParameter("force", .boolean, "Make proxies even for light footage, replacing existing ones",
                                 default: .bool(false), cli: .flag("force")),
            ]),
        CommandSpec(
            "media.place", .edit,
            "Place project media on a layer (main by default), with linked sound on a dialogue layer; "
                + "an occupied range spills onto a free or new layer.",
            parameters: [
                CommandParameter("media", .string, "Project media ID", required: true, cli: .option("media")),
                CommandParameter("track", .string, "Layer ID; defaults to the main layer", cli: .option("track")),
                CommandParameter("atFrame", .integer, "Timeline frame; defaults to the playhead or the end of the main layer",
                                 minimum: 0, cli: .option("at-frame")),
                baseRevision,
            ]),
        CommandSpec(
            "timeline.move", .edit,
            "Move an item and its linked partner; an occupied range spills onto a free or new layer.",
            parameters: [
                CommandParameter("item", .string, "Item ID", required: true, cli: .positional),
                CommandParameter("track", .string, "Destination layer ID", required: true, cli: .option("track")),
                CommandParameter("atFrame", .integer, "Timeline frame", required: true, minimum: 0,
                                 cli: .option("at-frame")),
                baseRevision,
            ]),
    ]

    private static let capabilitySpecs: [CommandSpec] = [
        CommandSpec(
            "jobs.cancel", .edit, "Cancel a queued or running job (plugin call or export).",
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
            "voice.speak", .edit,
            "Synthesize voice takes and insert the best take on the Voiceover track; with keepTakes, insert nothing "
                + "and keep every take file so one can be chosen and placed with media.import.",
            parameters: [
                CommandParameter("text", .string, "Voiceover text in the project content language", required: true,
                                 cli: .positional),
                CommandParameter("takes", .integer, "Number of takes to generate", default: .integer(3), minimum: 1,
                                 maximum: 8, cli: .option("takes")),
                CommandParameter("atFrame", .integer, "Timeline frame; defaults to the playhead", minimum: 0,
                                 cli: .option("at-frame")),
                provider,
                CommandParameter("keepTakes", .boolean, "Keep all takes in voiceover/generated and insert none",
                                 default: .bool(false), cli: .flag("keep-takes")),
            ],
            execution: .job),
    ]

    private static let privilegedSpecs: [CommandSpec] = [
        CommandSpec(
            "export.start", .privileged,
            "Request a background video export; the user approves it in the app first. Approved exports queue behind a running one.",
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
            "ui.dialog", .read,
            "Read the open dialogs (alerts, file panels, sheets), topmost last, with their option IDs."),
        CommandSpec(
            "ui.respond", .ui,
            "Answer the topmost dialog like the user: choose an option ID or title, or give a path to a file panel.",
            parameters: [
                CommandParameter("option", .string, "Option ID or title", cli: .positional),
                CommandParameter("path", .string, "File or folder for an open/save panel", isPath: true,
                                 cli: .option("path")),
                CommandParameter("dialog", .string, "Only answer if this dialog ID is topmost", cli: .option("dialog")),
            ]),
        CommandSpec(
            "ui.open", .ui, "Open a sheet or popover in the app.",
            parameters: [CommandParameter("dialog", .string, "Dialog", required: true, choices: dialogs,
                                          cli: .positional)]),
        CommandSpec(
            "ui.select", .ui,
            "Select a timeline item in the app (omit item to clear the selection), or a layer with --track.",
            parameters: [
                CommandParameter("item", .string, "Stable item ID", cli: .positional),
                CommandParameter("track", .string, "Layer (track) ID to select", cli: .option("track")),
            ]),
        CommandSpec(
            "ui.actions", .read,
            "List every editor action (buttons, menu items, keyboard shortcuts) with its shortcuts and whether it is enabled now."),
        CommandSpec(
            "ui.action", .edit,
            "Run an editor action like the user: by ID (timeline.split, timeline.zoom-in, playback.toggle) or by "
                + "shortcut (cmd+b, space, cmd+=). Actions that open a dialog return at once; answer it with ui.respond.",
            parameters: [CommandParameter("action", .string, "Action ID or shortcut", required: true, cli: .positional)]),
        CommandSpec(
            "ui.view", .ui,
            "Read the editor view state, or change it: timeline zoom (pixels per second), snapping, safe area, "
                + "color compare, agent dock, inspector tab, and scroll the timeline to a frame.",
            parameters: [
                CommandParameter("zoom", .integer, "Timeline zoom in pixels per second", minimum: 10, maximum: 140,
                                 cli: .option("zoom")),
                CommandParameter("snap", .boolean, "Snapping on or off", cli: .option("snap")),
                CommandParameter("safeArea", .boolean, "Safe-area overlay on or off", cli: .option("safe-area")),
                CommandParameter("compare", .boolean, "Color before/after compare on or off", cli: .option("compare")),
                CommandParameter("agentDock", .boolean, "Agent dock shown or hidden", cli: .option("agent-dock")),
                CommandParameter("reveal", .integer, "Scroll the timeline so this frame is visible", minimum: 0,
                                 cli: .option("reveal")),
                CommandParameter("inspector", .string, "Inspector tab", choices: UIAction.inspectorTabs,
                                 cli: .option("inspector")),
            ]),
        CommandSpec(
            "ui.source", .ui, "Open project media in the source viewer, optionally with in/out frames marked.",
            parameters: [
                CommandParameter("media", .string, "Media ID", required: true, cli: .positional),
                CommandParameter("in", .integer, "Source in frame", minimum: 0, cli: .option("in")),
                CommandParameter("out", .integer, "Source out frame (exclusive)", minimum: 1, cli: .option("out")),
            ]),
        CommandSpec(
            "ui.seek", .ui, "Move the viewer to a timeline frame.",
            parameters: [CommandParameter("frame", .integer, "Timeline frame", required: true, minimum: 0,
                                          cli: .positional)]),
        CommandSpec(
            "ui.panel", .ui, "Open a library panel in the left rail.",
            parameters: [CommandParameter("panel", .string, "Panel", required: true, choices: libraryPanels,
                                          cli: .positional)]),
        CommandSpec(
            "ui.notify", .ui, "Show a short status message in BashCut.",
            parameters: [CommandParameter("message", .string, "Message", required: true, cli: .positional)]),
    ]

    /// Library tools, health checks and agent knowledge (each matches a panel or sheet in the app).
    private static let toolSpecs: [CommandSpec] = [
        CommandSpec(
            "luts.import", .edit, "Check a .cube LUT, copy it into the project's luts folder and add it (Filters panel).",
            parameters: [
                CommandParameter("path", .string, ".cube file", required: true, isPath: true, cli: .positional),
                CommandParameter("name", .string, "Display name; defaults to the file name", cli: .option("name")),
                baseRevision,
            ]),
        CommandSpec(
            "edl.import", .edit,
            "Convert a legacy edl.json into project.bashcut.json beside it and open it (Welcome screen). Fails if the "
                + "open project has unsaved changes unless saveCurrent or discardCurrent is set.",
            parameters: [CommandParameter("path", .string, "edl.json file", required: true, isPath: true, cli: .positional)]
                + leaveCurrent),
        CommandSpec("project.recents", .read, "List recently opened projects (Welcome screen)."),
        CommandSpec("doctor.run", .read, "Run the Doctor checks (workspace, tools, plugins) and return the results."),
        CommandSpec(
            "plugins.health", .read, "Run plugin health checks (Plugins sheet, Check Health); all plugins by default.",
            parameters: [CommandParameter("plugin", .string, "Plugin ID", cli: .positional)]),
        CommandSpec("knowledge.get", .read, "Read the project memo and project skills shared with the agents."),
        CommandSpec(
            "knowledge.memo", .edit, "Replace the project memo (.bashcut/agent-memory.md).",
            parameters: [CommandParameter("text", .string, "Memo text (CLI: path to a text file)", required: true,
                                          cli: .positionalTextFile(maximumBytes: 256 * 1024))]),
        CommandSpec(
            "knowledge.skill", .edit,
            "Write a project skill's SKILL.md, creating the skill and sharing it with Claude and Codex if needed.",
            parameters: [
                CommandParameter("name", .string, "Lowercase hyphenated skill name", required: true, cli: .positional),
                CommandParameter("text", .string, "SKILL.md text (CLI: path to a text file)", required: true,
                                 cli: .positionalTextFile(maximumBytes: 256 * 1024)),
            ]),
    ]
}
