import BashCutProject
import Foundation

/// Every automation command, declared once. Modes, CLI parsing, MCP tools and agent instructions derive from it.
public enum CommandCatalog {
    /// Left-rail library panels, matching `LibraryTab` (checked by `EditorUIStateTests`).
    /// Sheets and popovers `ui.open` can show.
    public static let dialogs = [
        "new-project", "export", "export-report", "agent-changes", "review", "history", "plugins", "settings",
        "doctor", "knowledge", "ask", "sections", "external-changes", "plugin-proposals", "commands", "shortcuts",
        "add-plugin", "library-search", "library-generate",
    ]
    public static let libraryPanels = ["media", "audio", "text", "stickers", "effects", "transitions", "filters", "voice"]
    public static let exportPresets = OutputPresetName.all

    public static let specs: [CommandSpec] = readSpecs + projectSpecs + editSpecs + captionSpecs + layerSpecs + styleSpecs
        + formatSpecs + clipSpecs + capabilitySpecs + analysisSpecs + reviewCutSpecs + timelineStillsSpecs + [colorMeasureSpec] + planSpecs
        + workflowSpecs
        + sourceMediaSpecs
        + pluginSpecs + pluginViewSpecs
        + storageSpecs + agentSpecs + appSpecs + chatSpecs
        + privilegedSpecs + uiSpecs + toolSpecs + knowledgeSpecs + skillSpecs + librarySpecs + fontSpecs

    public static let modes: [String: CommandMode] = Dictionary(uniqueKeysWithValues: specs.map { ($0.name, $0.mode) })

    public static func spec(named name: String) -> CommandSpec? { specs.first { $0.name == name } }

    static let baseRevision = CommandParameter(
        "baseRev", .integer, "Current project revision from timeline.get", required: true, minimum: 0,
        cli: .option("base-rev"))
    static let provider = CommandParameter(
        "provider", .string, "Provider ID overriding the project preference for one request", cli: .option("provider"))
    private static let outputName = CommandParameter(
        "name", .string, "Output base name without an extension", required: true, cli: .option("name"))
    private static let outputDirectory = CommandParameter(
        "directory", .string, "Output folder, relative to the project; defaults to its render folder",
        cli: .option("output-dir"))

    private static let readSpecs: [CommandSpec] = [
        CommandSpec(
            "context.get", .read, contextSummary),
        CommandSpec("project.get", .read, "Read the whole open project document."),
        CommandSpec(
            "timeline.get", .read,
            "Read the revision, format and tracks, including track IDs and roles, and scale per video or image item: "
                + "fit or fill, baseScale, zoom and maxZoom (keyframes), pixelRatio (output pixels per source pixel; "
                + "over 1 is upscaled) now and at maxZoom, maxZoomNative (the largest zoom before upscaling), shown "
                + "size and frameCoverage.",
            parameters: [
                CommandParameter(
                    "format", .string, "json (default) or a compact text listing", choices: ["json", "text"],
                    cli: .option("format"))
            ]),
        mediaListSpec,
        reviewSpec,
        reviewMeasureSpec, reviewAcceptSpec,
        reviewPictureSpec,
        reviewShotsSpec,
        reviewLayoutSpec,
        reviewHookSpec,
        platformsListSpec,
        CommandSpec(
            "export.status", .read,
            "Read the export state: while one runs, its job, step, preset and path (last receipt under lastExport); "
                + "otherwise the most recent receipt. Includes the queue (job IDs for jobs.cancel)."),
        CommandSpec(
            "plugins.list", .read,
            "List installed plugins with their category, providers and project provider preferences.",
            parameters: [pluginCategory]),
        CommandSpec(
            "jobs.status", .read, "Read one job (plugin call or export), or all recent jobs when job is omitted.",
            parameters: [CommandParameter("job", .string, "Job ID", cli: .positional)]),
    ]

    static let leaveCurrent = [
        CommandParameter("saveCurrent", .boolean, "Save the open project first when it has unsaved changes",
                         default: .bool(false), cli: .flag("save-current")),
        CommandParameter("discardCurrent", .boolean, "Drop unsaved changes of the open project",
                         default: .bool(false), cli: .flag("discard-current")),
    ]

    private static let editSpecs: [CommandSpec] = [
        CommandSpec(
            "timeline.apply", .edit, "Atomically apply validated timeline operations as one undoable edit; "
                + "returns changed false and keeps the revision when nothing changes.",
            parameters: [
                CommandParameter("ops", .array, "Operations array (CLI: path to ops.json)", required: true,
                                 sensitive: true, cli: .positionalJSONFile),
                baseRevision,
                CommandParameter("label", .string, "Short description of the edit", default: .string("Agent edit"),
                                 cli: .option("label")),
                CommandParameter("dryRun", .boolean, "Validate without editing; return projected duration and changed IDs",
                                 default: .bool(false), cli: .flag("dry-run")),
            ]),
        CommandSpec("timeline.undo", .edit, "Undo one timeline action.", parameters: [baseRevision]),
        CommandSpec("timeline.redo", .edit, "Redo one timeline action.", parameters: [baseRevision]),
    ]

    private static let layerSpecs: [CommandSpec] = [
        CommandSpec(
            "layers.add", .edit,
            "Add an empty layer: text goes to the front of the picture stack, video and adjustment layers behind text, "
                + "audio layers below the others.",
            parameters: [
                CommandParameter("kind", .string, "Layer kind", required: true,
                                 choices: ["video", "adjustment", "text", "audio"], cli: .option("kind")),
                CommandParameter("role", .string, "Role such as overlay, captions, music or sfx; never main",
                                 cli: .option("role")),
                CommandParameter("name", .string, "Display name", cli: .option("name")),
                baseRevision,
            ]),
        CommandSpec(
            "media.import", .edit,
            "Add a media file (path relative to the project or absolute): video, audio or a still image (PNG keeps "
                + "transparency; placed for 3 s, trims to any length). With place, also put it on a layer like Import. "
                + "A file already in the project, unchanged, reuses its media and returns existing true.",
            parameters: [
                CommandParameter("path", .string, "Media file path", required: true, isPath: true, cli: .positional),
                CommandParameter("kind", .string, "Media kind; from the file type by default",
                                 choices: ["video", "audio", "image"], cli: .option("kind")),
                CommandParameter("place", .boolean, "Also place it on a layer", default: .bool(false),
                                 cli: .flag("place")),
                CommandParameter("track", .string, "Layer ID for place; defaults to the main layer (music for audio)",
                                 cli: .option("track")),
                CommandParameter("atFrame", .integer, "Timeline frame for place", minimum: 0, cli: .option("at-frame")),
                baseRevision,
            ]),
        CommandSpec(
            "media.proxy", .edit,
            "Queue preview proxies (smaller, quick-to-seek copies in .bashcut/cache/proxies; export keeps the originals) "
                + "for heavy video media, or one media item. Imports queue them automatically. Returns a status per "
                + "media: queued with its job ID, exists, not-needed or skipped.",
            parameters: [
                CommandParameter("media", .string, "Project media ID; all video media by default", cli: .positional),
                CommandParameter("force", .boolean, "Make proxies even for light footage, replacing existing ones",
                                 default: .bool(false), cli: .flag("force")),
            ]),
        CommandSpec(
            "media.place", .edit,
            "Place project media on a layer (main by default, music for audio), with linked sound on a dialogue layer; "
                + "an occupied range spills onto a free or new layer.",
            parameters: [
                CommandParameter("media", .string, "Project media ID", required: true, cli: .option("media")),
                CommandParameter("track", .string, "Layer ID; defaults to the main layer (music for audio)",
                                 cli: .option("track")),
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
        CommandSpec(
            "timeline.close-gap", .edit,
            "Delete an empty gap on a layer (the main layer by default): later clips on that layer move left by the "
                + "gap's length, with their linked sound.",
            parameters: [
                CommandParameter("atFrame", .integer, "A frame inside the gap", required: true, minimum: 0,
                                 cli: .option("at-frame")),
                CommandParameter("track", .string, "Layer ID; defaults to the main layer", cli: .option("track")),
                baseRevision,
            ]),
        CommandSpec(
            "layers.set", .edit,
            "Change a layer's header switches like the timeline header: hide a visual layer, mute an audio layer, "
                + "lock any layer (a locked layer refuses edits until unlocked).",
            parameters: [
                CommandParameter("track", .string, "Layer ID", required: true, cli: .positional),
                CommandParameter("hidden", .boolean, "Hidden (visual layers)", cli: .option("hidden")),
                CommandParameter("muted", .boolean, "Muted (audio layers)", cli: .option("muted")),
                CommandParameter("locked", .boolean, "Locked", cli: .option("locked")),
                baseRevision,
            ]),
    ]

    private static let capabilitySpecs: [CommandSpec] = [
        CommandSpec(
            "jobs.cancel", .edit, "Cancel a queued or running job (plugin call or export).",
            parameters: [CommandParameter("job", .string, "Job ID", required: true, cli: .positional)]),
        CommandSpec(
            "captions.generate", .edit,
            "Place captions of project media as one undoable edit, from its stored transcript (media.transcribe) or by "
                + "transcribing it with a captions.transcribe provider (the whole file is kept as its transcript). "
                + "Captions follow the clips where the media is heard (trim, position, speed): place the clips first. "
                + "The job's result says transcript: stored, transcribed or range (only from/to transcribed).",
            parameters: [
                CommandParameter("media", .string, "Project media ID", required: true, cli: .option("media")),
                CommandParameter("replace", .boolean, "Replace this media's captions", default: .bool(false), cli: .flag("replace")),
                CommandParameter("wordStyle", .string, "Show words as they are spoken (see captions.words)",
                                 choices: CaptionWords.styles + ["none"], cli: .option("word-style")),
                CommandParameter("from", .number, "Transcribe only from this source second of the media (with replace, "
                                 + "only this media's captions heard in the range are replaced)", range: 0...86_400,
                                 cli: .option("from")),
                CommandParameter("to", .number, "Transcribe only up to this source second of the media", range: 0...86_400,
                                 cli: .option("to")),
                provider, freshTranscript,
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
            "Select timeline items in the app (omit them to clear the selection), or a layer with --track. "
                + "Several items: --items a,b,c; --add keeps the current selection.",
            parameters: [
                CommandParameter("item", .string, "Stable item ID", cli: .positional),
                CommandParameter("items", .string, "More item IDs, comma-separated", cli: .option("items")),
                CommandParameter("add", .boolean, "Add to the current selection", cli: .flag("add")),
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
            "Read the editor view state, or change it: timeline zoom (pixels per second), viewer zoom, snapping, safe area, "
                + "color compare, agent dock, inspector tab, Settings section and search, Knowledge section, Plugins tab and Browse "
                + "category, the open library panel's search and filters, and scroll the timeline to a frame.",
            parameters: [
                CommandParameter("zoom", .integer, "Timeline zoom in pixels per second", minimum: 1, maximum: 600,
                                 cli: .option("zoom")),
                CommandParameter("zoomAnchor", .integer, "Frame kept in place by --zoom; the playhead by default",
                                 minimum: 0, cli: .option("zoom-anchor")),
                CommandParameter("snap", .boolean, "Snapping on or off", cli: .option("snap")),
                CommandParameter("safeArea", .boolean, "Safe-area overlay on or off", cli: .option("safe-area")),
                CommandParameter("viewerZoom", .string, "Viewer zoom: fit, or a percentage of the output size",
                                 choices: EditorViewerZoom.choices, cli: .option("viewer-zoom")),
                CommandParameter("compare", .boolean, "Color before/after compare on or off", cli: .option("compare")),
                CommandParameter("agentDock", .boolean, "Agent dock shown or hidden", cli: .option("agent-dock")),
                CommandParameter("reveal", .integer, "Scroll the timeline so this frame is visible", minimum: 0,
                                 cli: .option("reveal")),
                CommandParameter("inspector", .string, "Inspector tab", choices: UIAction.inspectorTabs,
                                 cli: .option("inspector")),
                CommandParameter("settingsSection", .string, "Settings section (open Settings with ui.open settings)",
                                 choices: UIAction.settingsSections, cli: .option("settings-section")),
                CommandParameter("settingsSearch", .string, "Settings search text: lists matching settings of every "
                                 + "section; empty clears it", cli: .option("settings-search")),
                CommandParameter("knowledgeSection", .string, "Knowledge window section (open it with ui.open knowledge)",
                                 choices: UIAction.knowledgeSections, cli: .option("knowledge-section")),
                CommandParameter("pluginsTab", .string, "Plugins sheet tab (open it with ui.open plugins)",
                                 choices: UIAction.pluginsTabs, cli: .option("plugins-tab")),
                CommandParameter("pluginsCategory", .string, "Category Plugins › Browse shows; all shows every one",
                                 choices: ["all"] + UIAction.pluginCategories,
                                 cli: .option("plugins-category")),
                CommandParameter("libraryQuery", .string, "Search text of the open library panel; empty clears it",
                                 cli: .option("library-query")),
                CommandParameter("libraryPack", .string, "Pack the open library panel shows; empty shows all",
                                 cli: .option("library-pack")),
                CommandParameter("libraryTag", .string, "Tag the open library panel shows; empty shows all",
                                 cli: .option("library-tag")),
                CommandParameter("libraryScope", .string, "Scope the open library panel shows",
                                 choices: ["all"] + LibraryScope.allCases.map(\.rawValue), cli: .option("library-scope")),
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
        uiFrameSpec, uiFramesSpec,
        CommandSpec(
            "ui.panel", .ui, "Open a library panel in the left rail.",
            parameters: [CommandParameter("panel", .string, "Panel", required: true, choices: libraryPanels,
                                          cli: .positional)]),
        CommandSpec(
            "ui.notify", .ui, "Show a short status message in BashCut.",
            parameters: [CommandParameter("message", .string, "Message", required: true, cli: .positional)]),
    ]

    /// Library tools and health checks (each matches a panel or sheet in the app).
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
    ]
}
