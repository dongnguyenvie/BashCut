# Command reference

<!-- Generated from CommandCatalog by scripts/update-commands.sh. Do not edit by hand. -->

Every automation command, 152 in all. Each is the same command on the CLI (`bashcut …`), as an
MCP tool (`bashcut_<group>_<command>`, same parameter names as JSON-RPC) and over the socket. Modes and
approval are explained in the [automation guide](../guides/automation.md#permission-modes).

## context

### `bashcut context get`

Read the project path, revision, playhead and selection, and a summary of the agent knowledge: active lessons, preferences, project facts and the number of proposals; scope lists the timeline items attached to your tab's request (edit only those), with the scope guard's mode, a held edit and the user's answer to the last one (last); agentPermissions tells what you may do without asking.

- Mode: read · Runs: immediately · MCP: `bashcut_context_get`

## project

### `bashcut project get`

Read the whole open project document.

- Mode: read · Runs: immediately · MCP: `bashcut_project_get`

### `bashcut project open <path> [--save-current] [--discard-current]`

Open a project.bashcut.json (or its folder). Fails if the open project has unsaved changes unless saveCurrent or discardCurrent is set. Agent tabs stay open; every agent must read the new project (context get or timeline get) before its next edit.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_open`
- `path`: string, required, path. Absolute path to project.bashcut.json or its folder
- `saveCurrent`: boolean, default false. Save the open project first when it has unsaved changes
- `discardCurrent`: boolean, default false. Drop unsaved changes of the open project

### `bashcut project close [--save-current] [--discard-current]`

Close the open project and show the Welcome screen, like File › Close Project. Fails if it has unsaved changes unless saveCurrent or discardCurrent is set. Agent tabs stay open; edits fail until a project is opened or created.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_close`
- `saveCurrent`: boolean, default false. Save the open project first when it has unsaved changes
- `discardCurrent`: boolean, default false. Drop unsaved changes of the open project

### `bashcut project create --name <name> [--dir <directory>] [--footage <footage>] [--canvas <canvas>] [--resolution <resolution>] [--fps <fps>] [--language <language>] [--save-current] [--discard-current]`

Create a project folder (media, footage, render…) like the New Project wizard and open it.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_create`
- `name`: string, required. Project name
- `directory`: string, path. Absolute parent folder for the new project folder; defaults to the projects folder (see project folder)
- `footage`: string, path. Footage folder to link (never modified)
- `canvas`: string, one of auto, portrait, landscape, square, default "auto". Canvas; auto starts portrait and lets the first video or image clip set the shape
- `resolution`: string, one of 720, 1080, 2160, default "1080". Short-side resolution
- `fps`: string, one of 29.97, 30, 24, 60, default "29.97". Frame rate
- `language`: string, default "vi". Content language tag
- `saveCurrent`: boolean, default false. Save the open project first when it has unsaved changes
- `discardCurrent`: boolean, default false. Drop unsaved changes of the open project

### `bashcut project folder [<path>] [--reset]`

Show the projects folder that New Project and project create use by default (Settings › General), or change it: a path sets it, --reset returns to ~/Movies/BashCut.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_folder`
- `path`: string, path. Absolute path of an existing folder
- `reset`: boolean, default false. Use ~/Movies/BashCut again

### `bashcut project save`

Save the open project to disk.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_save`

### `bashcut project format [--canvas <canvas>] [--clips <clips>] [--resolution <resolution>] [--outputs <outputs>] --base-rev <baseRev>`

Change the open project's canvas like the format menu in the toolbar: portrait 9:16, landscape 16:9 or square, at a short-side resolution (the current one by default); timing is kept and clip pan/tilt scale with the frame. --clips fit shows each clip whole (bars where its shape differs), fill covers the frame and crops; a clip's own `fill` property overrides it. --outputs sets the export presets the project is made for (first one primary): review checks the first one's platform (safe area, longest length, smallest text) and the Export sheet starts with it. Each change is one undoable edit.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_format`
- `canvas`: string, one of portrait, landscape, square. Canvas
- `clips`: string, one of fit, fill. How clips meet the frame by default
- `resolution`: string, one of 720, 1080, 2160. Short-side resolution; the current one by default
- `outputs`: string. Comma-separated export presets (tiktok, reels, shorts, youtube-1080, youtube-4k, quick-draft, prores); none clears them
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut project recents`

List recently opened projects (Welcome screen).

- Mode: read · Runs: immediately · MCP: `bashcut_project_recents`

## timeline

### `bashcut timeline get [--format <format>]`

Read the revision, format and tracks, including track IDs and roles.

- Mode: read · Runs: immediately · MCP: `bashcut_timeline_get`
- `format`: string, one of json, text. json (default) or a compact text listing

### `bashcut timeline apply <ops.json> --base-rev <baseRev> [--label <label>] [--dry-run]`

Atomically apply validated timeline operations as one undoable edit; returns changed false and keeps the revision when nothing changes.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_apply`
- `ops`: array, required. Operations array (CLI: path to ops.json)
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get
- `label`: string, default "Agent edit". Short description of the edit
- `dryRun`: boolean, default false. Validate without editing; return projected duration and changed IDs

### `bashcut timeline undo --base-rev <baseRev>`

Undo one timeline action.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_undo`
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut timeline redo --base-rev <baseRev>`

Redo one timeline action.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_redo`
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut timeline move <item> --track <track> --at-frame <atFrame> --base-rev <baseRev>`

Move an item and its linked partner; an occupied range spills onto a free or new layer.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_move`
- `item`: string, required. Item ID
- `track`: string, required. Destination layer ID
- `atFrame`: integer, required, ≥ 0. Timeline frame
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut timeline close-gap --at-frame <atFrame> [--track <track>] --base-rev <baseRev>`

Delete an empty gap on a layer (the main layer by default): later clips on that layer move left by the gap's length, with their linked sound.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_close-gap`
- `atFrame`: integer, required, ≥ 0. A frame inside the gap
- `track`: string. Layer ID; defaults to the main layer
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

## media

### `bashcut media list`

List project media.

- Mode: read · Runs: immediately · MCP: `bashcut_media_list`

### `bashcut media import <path> [--kind <kind>] [--place] [--track <track>] [--at-frame <atFrame>] --base-rev <baseRev>`

Add a media file (path relative to the project or absolute): video, audio or a still image (PNG keeps transparency; placed for 3 s, trims to any length). With place, also put it on a layer like Import. A file already in the project, unchanged, reuses its media and returns existing true.

- Mode: edit · Runs: immediately · MCP: `bashcut_media_import`
- `path`: string, required, path. Media file path
- `kind`: string, one of video, audio, image. Media kind; from the file type by default
- `place`: boolean, default false. Also place it on a layer
- `track`: string. Layer ID for place; defaults to the main layer (music for audio)
- `atFrame`: integer, ≥ 0. Timeline frame for place
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut media proxy [<media>] [--force]`

Queue preview proxies (smaller, quick-to-seek copies in .bashcut/cache/proxies; export keeps the originals) for heavy video media, or one media item. Imports queue them automatically. Returns a status per media: queued with its job ID, exists, not-needed or skipped.

- Mode: edit · Runs: immediately · MCP: `bashcut_media_proxy`
- `media`: string. Project media ID; all video media by default
- `force`: boolean, default false. Make proxies even for light footage, replacing existing ones

### `bashcut media place --media <media> [--track <track>] [--at-frame <atFrame>] --base-rev <baseRev>`

Place project media on a layer (main by default, music for audio), with linked sound on a dialogue layer; an occupied range spills onto a free or new layer.

- Mode: edit · Runs: immediately · MCP: `bashcut_media_place`
- `media`: string, required. Project media ID
- `track`: string. Layer ID; defaults to the main layer (music for audio)
- `atFrame`: integer, ≥ 0. Timeline frame; defaults to the playhead or the end of the main layer
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut media sync --media <media> --to <to> [--item <item>] [--provider <provider>]`

Find the time offset between two recordings of the same moment (a camera and a screen recording, or a render played inside a screen recording) from their sound, with an audio.sync provider. The job's result: time in `to` = time in `media` + offsetSeconds, the correlation (below 0.4: no shared sound) and each half of the overlap (steady: no clock drift). With item, also the matching source frame of `to` for that clip's in-point.

- Mode: read · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_media_sync`
- `media`: string, required. Project media ID of the first recording
- `to`: string, required. Project media ID of the second recording
- `item`: string. A timeline item of the first media whose in-point to map
- `provider`: string. Provider ID overriding the project preference for one request

## review

### `bashcut review run [--min-severity <minSeverity>] [--summary]`

Review the timeline before export. Each issue has a severity (error: spoils the export, warning: hurts it, info: a note) and, when one exists, a fix: a command with arguments, or a hint. Errors come first. With summary, the result is {issues, summary: {errors, warnings, infos, passed}}; passed means no error. Loudness is checked from the last normalized export of this revision, black and frozen picture, jump cuts and plugin checks from the last review.measure of this revision. Issues over a stretch carry endFrame. Pacing (shot length, still picture) follows the project's review object (minShotSeconds, maxShotSeconds, maxStillSeconds) when set.

- Mode: read · Runs: immediately · MCP: `bashcut_review_run`
- `minSeverity`: string, one of error, warning, info. Leave out issues less severe than this
- `summary`: boolean. Wrap the issues with counts and a pass flag

### `bashcut review measure [--picture <picture>] [--plugins <plugins>]`

Run the measured review for this revision and keep it, so review.run includes it: render the timeline small (two frames a second and both sides of every hard cut on Main, proxies allowed) for black or empty picture, frozen picture, long static shots and jump cuts, and run every enabled plugin review.check side by side (each at most 30 s; a failing or slow check becomes an info issue). Plugin issues carry source (the plugin ID) and IDs prefixed with the provider. A project turns checks off with review.disabledChecks (plugin or provider IDs; timeline apply setProjectProperties). The job's result has the sample count, the plugin checks that ran and the measured issues; measure again after an edit.

- Mode: read · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_review_measure`
- `picture`: boolean. Measure the picture (default true)
- `plugins`: boolean. Run plugin review checks (default true)

### `bashcut review picture [--from <from>] [--to <to>] [--samples <samples>] [--cuts <cuts>]`

Read the raw picture measurement of the last review.measure: per sample {frame, seconds, luma, spread, change, peak} at a fixed interval and per hard cut on Main {item, fromItem, frame, before, seconds, difference}, with the units and the noise floors the picture checks use (floors). Values are fractions of full scale on a small grey thumbnail. current is false when the timeline changed since; measure again for this revision. No verdicts: read the numbers to find frozen stretches, flat or dark picture and near-identical cuts.

- Mode: read · Runs: immediately · MCP: `bashcut_review_picture`
- `from`: integer, ≥ 0. First timeline frame (default 0)
- `to`: integer, ≥ 1. Timeline frame after the range (default: the end)
- `samples`: boolean. Include the samples (default true)
- `cuts`: boolean. Include the cuts (default true)

### `bashcut review shots [--summary]`

Read the shots on Main in order: index, id, at/atSeconds, duration (frames) and seconds, media, mediaKind, sourceIn and sourceInSeconds, zoom and transform, speed, keyframed properties, freezeFrame/reverse when set, gapBefore (frames since the previous shot), transitionIn {kind, duration} or the picture cutDifference across a hard cut, and motion {mean, peak, samples} (fractions of full scale, see review.picture) when review.measure ran for this revision (pictureMeasured). No verdicts. With summary: count, total, mean, median, min and max seconds and cuts per minute.

- Mode: read · Runs: immediately · MCP: `bashcut_review_shots`
- `summary`: boolean. Add count, length statistics and cuts per minute

### `bashcut review layout [--frame <frame>]`

Read where text sits as the renderer lays it out: per visible text item id, track, trackRole, at/end, text, preset, lines, longestLineChars, fontPixels and fontShare (of the frame's short side), bounds (pixels from the top-left) and edges (distance to each frame edge as a share of that dimension, negative outside), keyframed when keyframes move it (not followed). Also the frame size and the platform whose zones apply (safeArea, minTextSize). No verdicts.

- Mode: read · Runs: immediately · MCP: `bashcut_review_layout`
- `frame`: integer, ≥ 0. Only text on screen at this timeline frame

## export

### `bashcut export status`

Read the export state: while one runs, its job, step, preset and path (last receipt under lastExport); otherwise the most recent receipt. Includes the queue (job IDs for jobs.cancel).

- Mode: read · Runs: immediately · MCP: `bashcut_export_status`

### `bashcut export start --preset <preset> --name <name> [--output-dir <directory>] [--include-srt] [--normalize-audio]`

Request a background video export; the user approves it in the app first. Approved exports queue behind a running one.

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_export_start`
- `preset`: string, required, one of tiktok, reels, shorts, youtube-1080, youtube-4k, quick-draft, prores. Export preset
- `name`: string, required. Output base name without an extension
- `directory`: string. Output folder, relative to the project; defaults to its render folder
- `includeSRT`: boolean, default false. Also write a SubRip file
- `normalizeAudio`: boolean, default false. Run two-pass LUFS normalization with a plugin

### `bashcut export otio --name <name> [--output-dir <directory>]`

Request an OpenTimelineIO export; the user approves it in the app first.

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_export_otio`
- `name`: string, required. Output base name without an extension
- `directory`: string. Output folder, relative to the project; defaults to its render folder

## plugins

### `bashcut plugins list [--category <category>]`

List installed plugins with their category, providers and project provider preferences.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_list`
- `category`: string, one of agents, captions, voice, audio, color, effects, export, utilities. Only plugins in this category

### `bashcut plugins actions [<query>] [--plugin <plugin>]`

List actions plugins add to the editor (Plugins menu, toolbar, context menus, panels) with their parameters as JSON Schema, placements, whether each is available now and when it last ran. MCP lists at most 40 of them as their own tools; find any other action here and run it with plugins run.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_actions`
- `query`: string. Only actions whose ID, title or plugin contains this text
- `plugin`: string. Only actions of this plugin ID

### `bashcut plugins run <action> [--params <params>]`

Run a plugin action like clicking it, with parameters (CLI: --params '{"mode":"vivid"}'). The plugin's proposed operations are validated and applied as one undoable edit attributed to the plugin.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_plugins_run`
- `action`: string, required. Action ID from plugins actions
- `params`: object. Action parameters (JSON object)

### `bashcut plugins hooks`

List plugin hook subscriptions, the delivery queue (limit, running, queued, debouncing), the recent hook runs, hook edits waiting for review, and reviewChecks: the review.check providers with whether this project enables them (project review.disabledChecks) and whether they can run.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_hooks`

### `bashcut plugins proposal <id> --decision <decision>`

Apply or discard an edit a plugin hook proposed (Settings decides whether hook edits wait for review).

- Mode: edit · Runs: immediately · MCP: `bashcut_plugins_proposal`
- `id`: string, required. Proposal ID from plugins hooks
- `decision`: string, required, one of apply, discard. What to do

### `bashcut plugins options <plugin>`

Read a plugin's options (schema, scope and current values).

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_options`
- `plugin`: string, required. Plugin ID

### `bashcut plugins option <plugin> --option <option> [--value <value>]`

Set one plugin option like the Plugins sheet: project-scope values are an undoable project edit, user-scope values are saved for this Mac. Omit value to reset it to the default.

- Mode: edit · Runs: immediately · MCP: `bashcut_plugins_option`
- `plugin`: string, required. Plugin ID
- `option`: string, required. Option ID
- `value`: string. New value as text (on/off, numbers, choices)

### `bashcut plugins search [<query>] [--capability <capability>] [--category <category>] [--refresh]`

Search the plugin registry (Plugins › Browse): name, summary, category, capability, the version this BashCut would install and whether it is installed, has an update or is incompatible.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_search`
- `query`: string. Search text
- `capability`: string. Only providers of this capability, such as captions.transcribe
- `category`: string, one of agents, captions, voice, audio, color, effects, export, utilities. Only plugins in this category
- `refresh`: boolean, default false. Fetch the registry again instead of using the 5-minute cache

### `bashcut plugins updates`

List installed plugins with a newer compatible version in the registry.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_updates`

### `bashcut plugins validate [<path>] [--url <url>] [--ref <ref>] [--sha256 <sha256>]`

Check a plugin that is not in the registry (a folder, its plugin.json, a .zip or .bashcutplugin archive, or a link) without installing or running it: its id, version and capabilities, every problem with the field and the fix (library packs included: each pack.json and the files it names, inside the plugin), and for a link the commit or release it resolved to.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_validate`
- `path`: string, path. Plugin folder, plugin.json, or .zip / .bashcutplugin file (or use url)
- `url`: string. Link to a .zip / .bashcutplugin file, a GitHub repo (or /tree/<ref>/<folder>, or its plugin.json) or a GitHub release; #sha256=<hex> pins it. A private link uses the access token saved in Add Plugin…
- `ref`: string. Tag, branch or commit for a GitHub repo link (release tag for a release link)
- `sha256`: string. Expected SHA-256 of the downloaded archive

### `bashcut plugins install [<plugin>] [--version <version>] [--path <path>] [--url <url>] [--ref <ref>] [--sha256 <sha256>] [--scope <scope>] [--link]`

Download a registry plugin (or its update), check its SHA-256 and manifest, and show the install approval in the Plugins sheet. With path or url instead, add a plugin that is not in the registry (Add Plugin…): a folder, its plugin.json or a .zip / .bashcutplugin file on this Mac, or a link, checked like plugins validate. Only the user can approve; the job ends when the approval is shown.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_plugins_install`
- `plugin`: string. Plugin ID from plugins search (or use path)
- `version`: string. A specific registry version; the newest compatible by default
- `path`: string, path. Plugin folder, plugin.json, or .zip / .bashcutplugin file on this Mac
- `url`: string. Link to a .zip / .bashcutplugin file, a GitHub repo (or /tree/<ref>/<folder>, or its plugin.json) or a GitHub release; #sha256=<hex> pins it. A private link uses the access token saved in Add Plugin…
- `ref`: string. Tag, branch or commit for a GitHub repo link (release tag for a release link)
- `sha256`: string. Expected SHA-256 of the downloaded archive
- `scope`: string, one of user, project. Where a plugin from path or url goes: user (this Mac, every project; the default) or project (the open project)
- `link`: boolean. Link (developer mode): install a link to the plugin folder at path instead of a copy; use plugins reload after editing it

### `bashcut plugins replace <plugin> --path <path>`

Replace… an installed plugin with a new version from a folder, its plugin.json or a .zip / .bashcutplugin file, in the same scope. The new files must have the same plugin ID; only the user can approve, like plugins install.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_plugins_replace`
- `plugin`: string, required. Plugin ID
- `path`: string, required, path. Folder, plugin.json, or .zip / .bashcutplugin file with the new version

### `bashcut plugins reload <plugin>`

Reload a plugin after editing it (for linked plugins in developer mode): stop its session and check its files again. Changed files make it changed until the user chooses Trust; reload never trusts it.

- Mode: edit · Runs: immediately · MCP: `bashcut_plugins_reload`
- `plugin`: string, required. Plugin ID

### `bashcut plugins remove <plugin> [--data]`

Uninstall a plugin from the user or project plugin folder, with its trust and options (plugins that come with BashCut can only be turned off). With data, also delete its downloaded environments and models.

- Mode: edit · Runs: immediately · MCP: `bashcut_plugins_remove`
- `plugin`: string, required. Plugin ID
- `data`: boolean, default false. Also delete the plugin's data and cache folders

### `bashcut plugins setup <plugin>`

Show the approval to run an installed plugin's dependency install recipes again (Install Dependencies…). Only the user can approve; follow it with jobs status.

- Mode: edit · Runs: immediately · MCP: `bashcut_plugins_setup`
- `plugin`: string, required. Plugin ID

### `bashcut plugins set <plugin> [--enabled <enabled>] [--hooks <hooks>]`

Turn a plugin or its hooks off (agents can only turn them off; turning on and trusting a plugin stays with the user in the Plugins sheet).

- Mode: edit · Runs: immediately · MCP: `bashcut_plugins_set`
- `plugin`: string, required. Plugin ID
- `enabled`: boolean. Plugin on or off
- `hooks`: boolean. Hooks on or off

### `bashcut plugins views`

List ready plugins with a panel in the left rail or views (plugin API 8): title and icon, each view with where it lives (panel, dock tab or sheet) and whether it is shown, tools (actions), skills, required plugins with their state, the capabilities it uses and whether a ready plugin provides each, the open panel and sheet. Also lists the host's plugin features.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_views`

### `bashcut plugins show-view <plugin> --view <view>`

Show a plugin view where it lives: its plugin's panel in the left rail, its tab in the agent dock, or a sheet. Plugins call this for their own views (an action opening a form sheet).

- Mode: ui · Runs: immediately · MCP: `bashcut_plugins_show-view`
- `plugin`: string, required. Plugin ID
- `view`: string, required. View ID from plugins views

### `bashcut plugins view <plugin> [--view <view>] [--open]`

Render a plugin view and return its components as JSON (what the app draws: text, lists, inputs with their current values, buttons by id). With open, also show the view where it lives (panel, dock tab or sheet).

- Mode: ui · Runs: immediately · MCP: `bashcut_plugins_view`
- `plugin`: string, required. Plugin ID
- `view`: string. View ID from plugins views; the plugin's first view by default
- `open`: boolean, default false. Show the view where it lives

### `bashcut plugins view-event <plugin> [--view <view>] --node <node> [--type <type>] [--value <value>]`

Do what a user does in a plugin view: click a button, change an input, submit a text field, select a list row or press a row button. Returns the view's new components.

- Mode: ui · Runs: immediately · MCP: `bashcut_plugins_view-event`
- `plugin`: string, required. Plugin ID
- `view`: string. View ID from plugins views; the plugin's first view by default
- `node`: string, required. Component id from plugins view
- `type`: string, one of click, change, submit, select, action, default "click". What happened
- `value`: string. New value (change), row id (select) or {"item","action"} (action); JSON or text

### `bashcut plugins invoke <capability> [--provider <provider>] [--params <params>]`

Run a plugin capability directly with raw parameters and return the provider's raw result, for capabilities without their own command (prefer voice speak, captions generate, beats detect … when one exists). Files go to the returned outputDirectory. Plugins call this from their views and actions for capabilities listed in their manifest's uses.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_plugins_invoke`
- `capability`: string, required. Capability ID, such as voice.synthesize
- `provider`: string. Provider ID; the project's choice or the highest priority by default
- `params`: object. Request parameters (JSON object)

### `bashcut plugins health [<plugin>]`

Run plugin health checks (Plugins sheet, Check Health); all plugins by default.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_health`
- `plugin`: string. Plugin ID

## jobs

### `bashcut jobs status [<job>]`

Read one job (plugin call or export), or all recent jobs when job is omitted.

- Mode: read · Runs: immediately · MCP: `bashcut_jobs_status`
- `job`: string. Job ID

### `bashcut jobs cancel <job>`

Cancel a queued or running job (plugin call or export).

- Mode: edit · Runs: immediately · MCP: `bashcut_jobs_cancel`
- `job`: string, required. Job ID

## captions

### `bashcut captions export [--as <as>]`

Export the captions (text on text layers, in time order) as: srt (default), SubRip text; json as {revision, fps, cues} with per cue index, item, track, trackRole, at/end/duration (frames), atSeconds, endSeconds, seconds, text, lines, chars (line breaks read as one space), cps, gapBefore (frames since the previous cue ended, negative when they overlap), captionMedia, wordStyle, wordTiming (transcribed or estimated from word length) and words [{text, at, end, atSeconds, endSeconds, source}]; text, one line per cue: #index start–end seconds cps | text (print it with --format text).

- Mode: read · Runs: immediately · MCP: `bashcut_captions_export`
- `as`: string, one of srt, json, text. srt (default), json or text

### `bashcut captions import <text-file> --base-rev <baseRev> [--replace]`

Import UTF-8 SubRip captions as one undoable edit.

- Mode: edit · Runs: immediately · MCP: `bashcut_captions_import`
- `text`: string, required. SubRip text (CLI: path to a .srt file)
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get
- `replace`: boolean, default false. Replace existing captions

### `bashcut captions words [<item>] --style <style> [--all] [--color <color>] --base-rev <baseRev>`

Show caption words as they are spoken (Inspector › Text › Word by word): highlight colours the word being said, karaoke colours the words already said, reveal makes words appear as they are said; none shows them all at once. Timings come from the transcription's word timings (captions generate) or are estimated from word length.

- Mode: edit · Runs: immediately · MCP: `bashcut_captions_words`
- `item`: string. Text item ID; the selection by default
- `style`: string, required, one of highlight, karaoke, reveal, none. Word style
- `all`: boolean, default false. Every caption on the caption layers
- `color`: string. Highlight colour, #RRGGBB (default #FFD400)
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut captions generate --media <media> [--replace] [--word-style <wordStyle>] [--from <from>] [--to <to>] [--provider <provider>]`

Transcribe project media with a captions.transcribe provider and import the captions as one undoable edit. Captions follow the clips where the media is heard (trim, position, speed): place the clips first.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_captions_generate`
- `media`: string, required. Project media ID
- `replace`: boolean, default false. Replace this media's captions
- `wordStyle`: string, one of highlight, karaoke, reveal, none. Show words as they are spoken (see captions.words)
- `from`: number, 0…86400. Transcribe only from this source second of the media (with replace, only this media's captions heard in the range are replaced)
- `to`: number, 0…86400. Transcribe only up to this source second of the media
- `provider`: string. Provider ID overriding the project preference for one request

## transcript

### `bashcut transcript words [--from <from>] [--to <to>] [--media <media>]`

Read every word on the caption layers in timeline order: index, text, at/end (frames), atSeconds, endSeconds, item and cue (captions export numbering), timing (transcribed or estimated from word length), gapBefore (frames since the previous word ended) and, for captions made from a media, source {media, clip, start, end} in that media's seconds through the clip heard there now (null when no clip of it plays there: captions do not move with their clips). No speaker or confidence is stored yet. count is the words returned, total the words on the caption layers.

- Mode: read · Runs: immediately · MCP: `bashcut_transcript_words`
- `from`: integer, ≥ 0. Only words ending after this timeline frame
- `to`: integer, ≥ 0. Only words starting before this timeline frame
- `media`: string. Only captions made from this media ID

## layers

### `bashcut layers add --kind <kind> [--role <role>] [--name <name>] --base-rev <baseRev>`

Add an empty layer: text goes to the front of the picture stack, video and adjustment layers behind text, audio layers below the others.

- Mode: edit · Runs: immediately · MCP: `bashcut_layers_add`
- `kind`: string, required, one of video, adjustment, text, audio. Layer kind
- `role`: string. Role such as overlay, captions, music or sfx; never main
- `name`: string. Display name
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut layers set <track> [--hidden <hidden>] [--muted <muted>] [--locked <locked>] --base-rev <baseRev>`

Change a layer's header switches like the timeline header: hide a visual layer, mute an audio layer, lock any layer (a locked layer refuses edits until unlocked).

- Mode: edit · Runs: immediately · MCP: `bashcut_layers_set`
- `track`: string, required. Layer ID
- `hidden`: boolean. Hidden (visual layers)
- `muted`: boolean. Muted (audio layers)
- `locked`: boolean. Locked
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

## adjustment

### `bashcut adjustment add [--look <look>] [--exposure <exposure>] [--contrast <contrast>] [--saturation <saturation>] [--lut-strength <lutStrength>] [--lut <lut>] [--at-frame <atFrame>] [--duration <duration>] [--track <track>] --base-rev <baseRev>`

Add an adjustment item: a color grade applied to every layer below it for its frame range. Starts from a look, then the given grade values and LUT override it. Defaults to the selected clip's range, else 3 seconds at the playhead; goes on the first adjustment layer, adding one when needed.

- Mode: edit · Runs: immediately · MCP: `bashcut_adjustment_add`
- `look`: string, default "original". Look ID: built-in (original, vivid, muted-film, black-white) or custom from timeline get looks
- `exposure`: number, -10…10. Exposure in stops (0 = unchanged)
- `contrast`: number, 0…4. Contrast multiplier (1 = unchanged)
- `saturation`: number, 0…4. Saturation multiplier (0 = black and white, 1 = unchanged)
- `lutStrength`: number, 0…1. LUT mix (0 = off, 1 = full)
- `lut`: string. LUT ID from timeline get luts
- `atFrame`: integer, ≥ 0. First timeline frame
- `duration`: integer, ≥ 1. Length in timeline frames
- `track`: string. Adjustment layer ID
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

## style

### `bashcut style apply <kit> --base-rev <baseRev>`

Apply a style kit as one undoable edit: a full-length adjustment item with the kit's look (replacing one an earlier kit added) and the kit's preset on captions (titles and cards keep theirs). Apply after captions exist; afterwards everything stays editable on its own.

- Mode: edit · Runs: immediately · MCP: `bashcut_style_apply`
- `kit`: string, required. Kit ID: built-in (food-review, cinematic) or custom from timeline get styleKits
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut style save <id> --title <title> --look <look> [--caption-preset <captionPreset>] --base-rev <baseRev>`

Save a custom style kit in the project (it appears in Filters › Style kits and works with style apply). Saving an existing custom ID replaces it; built-in IDs are reserved.

- Mode: edit · Runs: immediately · MCP: `bashcut_style_save`
- `id`: string, required. Kit ID: lowercase letters, digits and hyphens
- `title`: string, required. Display name
- `look`: string, required. Built-in or custom look ID
- `captionPreset`: string, one of bold-outline, cinematic-serif, keyword-sticker, place-card, hook-title, chapter-card, default "bold-outline". Text preset given to captions
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut style delete <id> --base-rev <baseRev>`

Delete a custom style kit.

- Mode: edit · Runs: immediately · MCP: `bashcut_style_delete`
- `id`: string, required. Custom kit ID
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

## looks

### `bashcut looks save <id> --title <title> [--item <item>] [--exposure <exposure>] [--contrast <contrast>] [--saturation <saturation>] [--lut-strength <lutStrength>] [--lut <lut>] --base-rev <baseRev>`

Save a custom look in the project (it appears in Filters › Looks and works with adjustment add). Starts from an item's grade when item is given, then the grade values override it. Saving an existing custom ID replaces it; built-in IDs are reserved.

- Mode: edit · Runs: immediately · MCP: `bashcut_looks_save`
- `id`: string, required. Look ID: lowercase letters, digits and hyphens
- `title`: string, required. Display name
- `item`: string. Copy the color of this item first
- `exposure`: number, -10…10. Exposure in stops (0 = unchanged)
- `contrast`: number, 0…4. Contrast multiplier (1 = unchanged)
- `saturation`: number, 0…4. Saturation multiplier (0 = black and white, 1 = unchanged)
- `lutStrength`: number, 0…1. LUT mix (0 = off, 1 = full)
- `lut`: string. LUT ID from timeline get luts
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut looks delete <id> --base-rev <baseRev>`

Delete a custom look; refused while a custom style kit uses it.

- Mode: edit · Runs: immediately · MCP: `bashcut_looks_delete`
- `id`: string, required. Custom look ID
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

## schema

### `bashcut schema get`

Read the project.bashcut.json JSON Schema: every field, its type and range. Generated from the same declarations the app validates with.

- Mode: read · Runs: immediately · MCP: `bashcut_schema_get`

## clip

### `bashcut clip speed [<item>] --speed <speed> [--keep-duration] [--preserve-pitch <preservePitch>] --base-rev <baseRev>`

Change a clip's constant speed like Inspector › Speed. By default the clip keeps its source and its length changes (2× halves it), moving later clips on its layer; with keepDuration it keeps its length and uses more or less source. Linked picture and sound change together. A clip is shortened to fit its source even with keepDuration; the result then has shortened: true.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_speed`
- `item`: string. Item ID; the selected clip by default
- `speed`: number, required, 0.1…16. Speed, for example 0.5, 1.5 or 2
- `keepDuration`: boolean, default false. Keep the clip's length instead
- `preservePitch`: boolean. Keep the voice pitch (on by default)
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut clip speed-curve [<item>] [--preset <preset>] [--points <points>] [--keep-duration] --base-rev <baseRev>`

Give a clip a speed ramp (CapCut Curve) like Inspector › Speed › Curve: a preset (montage, hero, bullet, jump-cut, flash-in, flash-out, or none to remove it) or points [[t, speed], …] with t from 0 (clip start) to 1 (clip end). The clip keeps its source and its length follows the average speed unless keepDuration (still shortened to fit its source, reported as shortened: true); linked sound follows; one undo step.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_speed-curve`
- `item`: string. Item ID; the selected clip by default
- `preset`: string, one of montage, hero, bullet, jump-cut, flash-in, flash-out, none. Preset name, or none
- `points`: string. Custom points as JSON, e.g. [[0,1],[0.5,3],[1,1]]
- `keepDuration`: boolean, default false. Keep the clip's length instead
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut clip motion [<item>] [--preset <preset>] [--keyframes <keyframes>] [--focus <focus>] [--focus-to <focusTo>] [--ease <ease>] --base-rev <baseRev>`

Animate a clip, image or text over its length (Inspector › Animation): a preset (zoom-in, zoom-out, pan-left, pan-right, pan-up, pan-down, fade-in-out, pop-in, slide-up, zoom-punch; none removes the animation) sized to the item, or keyframes JSON {property: [{frame, value, ease?}, …]} with frames from the item's start. Properties: zoom, pan, tilt (px, up), rotation (degrees), opacity, and volume (dB, like volumeDb; the only one on audio items, none on text); ease: linear, in, out, inOut, hold (default inOut). Keys replace the item's static value for that property. Images with zoom-in, zoom-out or pan-* make a Ken Burns move; presets are for pictures and text. focus frames a rectangle of a video clip (a panel of a screen recording) without working out zoom, pan and tilt by hand.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_motion`
- `item`: string. Item ID; the selection by default
- `preset`: string, one of zoom-in, zoom-out, pan-left, pan-right, pan-up, pan-down, fade-in-out, pop-in, slide-up, zoom-punch, none. Preset name, or none
- `keyframes`: string. Keyframes as JSON, replacing the item's animation
- `focus`: string. Frame a rectangle of a video clip's picture: x,y,width,height in source pixels from the top left (media.list width/height); sets zoom, pan and tilt and keeps the other keys
- `focusTo`: string. With focus: move to this rectangle by the item's last frame
- `ease`: string, one of linear, in, out, inOut, hold. With focus-to: the move's ease
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut clip keyframe [<item>] [--property <property>] [--value <value>] [--at-frame <atFrame>] [--ease <ease>] [--remove] --base-rev <baseRev>`

Set one keyframe like the Inspector's controls with keyframes on: property at a timeline frame (the playhead by default) to value (its current value when omitted); remove deletes that key. Without property, keys every picture property at its current value (the Inspector's Keyframe at playhead); on an audio item, its volume. Volume (dB) works on audio items and clips with sound.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_keyframe`
- `item`: string. Item ID; the selection by default
- `property`: string, one of opacity, pan, rotation, tilt, volume, zoom. Property; all of them by default
- `value`: number. Value
- `atFrame`: integer, ≥ 0. Timeline frame inside the item; the playhead by default
- `ease`: string, one of linear, in, out, inOut, hold. Change to the next key
- `remove`: boolean, default false. Remove the key at that frame
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut clip reverse [<item>]`

Play a video clip backwards (with its linked sound): renders a reversed copy of the source it uses into the project's reversed/ folder and points the clip at it. Reversing again restores the original.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_clip_reverse`
- `item`: string. Item ID; the selected clip by default

## beats

### `bashcut beats detect --media <media> [--provider <provider>]`

Detect beats in audio media and set its beat grid as one undoable edit.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_beats_detect`
- `media`: string, required. Audio media ID already placed on the timeline
- `provider`: string. Provider ID overriding the project preference for one request

## voice

### `bashcut voice speak <text> [--takes <takes>] [--at-frame <atFrame>] [--provider <provider>] [--keep-takes]`

Synthesize voice takes and insert the best take on the Voiceover track; with keepTakes, insert nothing and keep every take file so one can be chosen and placed with media.import.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_voice_speak`
- `text`: string, required. Voiceover text in the project content language
- `takes`: integer, 1…8, default 3. Number of takes to generate
- `atFrame`: integer, ≥ 0. Timeline frame; defaults to the playhead
- `provider`: string. Provider ID overriding the project preference for one request
- `keepTakes`: boolean, default false. Keep all takes in voiceover/generated and insert none

## audio

### `bashcut audio measure --media <media> [--provider <provider>]`

Measure a media file's sound with an audio.loudness provider: integrated loudness (LUFS), true peak, loudness range (LU) and the energy share in the speech band (300-3000 Hz) and the presence band (1-4 kHz, where consonants carry words). Under a voice, prefer music with a low presence share and loudness range. The job's result holds the values.

- Mode: read · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_audio_measure`
- `media`: string, required. Project media ID
- `provider`: string. Provider ID overriding the project preference for one request

## storage

### `bashcut storage get`

What BashCut keeps on disk (Settings › Storage): each plugin's folder, data and cache, the saved plugin registry, the shared plugin runtimes, this project's preview proxies, ramp audio and the audit log, with sizes and paths. plugins lists each plugin's total, largest first.

- Mode: read · Runs: immediately · MCP: `bashcut_storage_get`

### `bashcut storage clear <target> [--plugin <plugin>]`

Delete what can be made or downloaded again: plugin-cache (all plugins, or --plugin), shared-cache, registry, proxies or ramp-audio (made again on demand), plugin-data --plugin ID (the plugin must be set up again), or shared-data (plugins using the shared runtimes must be set up again).

- Mode: edit · Runs: immediately · MCP: `bashcut_storage_clear`
- `target`: string, required, one of plugin-cache, plugin-data, shared-cache, shared-data, registry, proxies, ramp-audio. What to clear
- `plugin`: string. Only this plugin's data or cache

## agent

### `bashcut agent status`

The agent kit (editing skills) BashCut uses: its folder, version and skills, whether BashCut's Claude and Codex tabs load it, and for Claude Code and Codex outside BashCut: the CLI, whether the kit is set up, and the configuration folder (CLAUDE_CONFIG_DIR, CODEX_HOME) with where it came from.

- Mode: read · Runs: immediately · MCP: `bashcut_agent_status`

### `bashcut agent setup <target> [--remove] [--kit <kit>] [--claude-config-dir <claudeConfigDir>] [--codex-home <codexHome>]`

Set up the agent kit like Settings › Agents: in-app (load it in BashCut's tabs), claude (install the bashcut plugin in Claude Code) or codex (link the skills and register the MCP server); remove undoes it. Can also choose the kit folder and the agents' configuration folders.

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_agent_setup`
- `target`: string, required, one of in-app, claude, codex. What to set up
- `remove`: boolean, default false. Undo the setup instead
- `kit`: string. Kit folder to use, or built-in
- `claudeConfigDir`: string. Claude Code's configuration folder (CLAUDE_CONFIG_DIR), or default to detect it
- `codexHome`: string. Codex's home folder (CODEX_HOME), or default to detect it

### `bashcut agent kit-check`

Check bashcut-agent-kit's signed releases for a newer agent kit than the one BashCut uses (built-in or downloaded). A chosen kit folder is never updated.

- Mode: read · Runs: immediately · MCP: `bashcut_agent_kit-check`

### `bashcut agent kit-update`

Download and install the newest signed agent kit release (Settings › Agents › Download & Update), then refresh Claude Code and Codex where the kit is set up.

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_agent_kit-update`

### `bashcut agent terminals`

The terminals the agent dock can open: built-in (claude, codex, shell) and agent CLIs from plugins with the agent.terminal capability, whether each can continue its last conversation in this project, and the open terminal tabs.

- Mode: read · Runs: immediately · MCP: `bashcut_agent_terminals`

### `bashcut agent open <terminal> [--new]`

Open a terminal tab in the agent dock like its + menu: claude, codex, shell or a terminal plugin's ID. Returns once it started; a plugin's launch error is this command's error.

- Mode: ui · Runs: immediately · MCP: `bashcut_agent_open`
- `terminal`: string, required. claude, codex, shell or a plugin ID (agent terminals)
- `new`: boolean, default false. Start a new conversation instead of continuing the last one

### `bashcut agent detach [--items <items>]`

Remove timeline items sent to the shown terminal tab with Send to Agent (ui action clip.send-to-agent), like the chip's ×; without --items, all of them. While items are attached, the scope guard checks that tab's edits against them.

- Mode: ui · Runs: immediately · MCP: `bashcut_agent_detach`
- `items`: string. Item IDs, comma-separated

## app

### `bashcut app version`

This BashCut's version and build, how it was installed (homebrew, direct, app-store, development) and the plugin API it offers, like About BashCut.

- Mode: read · Runs: immediately · MCP: `bashcut_app_version`

### `bashcut app update-check`

Ask GitHub for the latest BashCut release, like BashCut › Check for Updates…. Returns this version, the latest release (version, page, notes) when it is newer, and how to update: the Homebrew command or the release page. Never installs anything; App Store and TestFlight copies are not checked.

- Mode: read · Runs: immediately · MCP: `bashcut_app_update-check`

## chat

### `bashcut chat status`

The chat agents in the agent dock (plugins with the agent.chat capability): each one's plugin ID, name, provider and model, whether it is ready (an API key is set) and whether a turn is running.

- Mode: read · Runs: immediately · MCP: `bashcut_chat_status`

### `bashcut chat send <text> [--plugin <plugin>] [--image <image>]`

Send a message to a chat agent like typing it in its tab. Returns at once; poll chat transcript until running is false to read the reply and the commands it ran.

- Mode: edit · Runs: immediately · MCP: `bashcut_chat_send`
- `text`: string, required. Message
- `plugin`: string. Chat agent plugin ID; by default the one shown in the dock, else the first
- `image`: string. PNG or JPEG to attach, such as a ui frame

### `bashcut chat attach --items <items> [--plugin <plugin>]`

Attach timeline items to a chat agent's request like Send to Agent on the clip menu: they show as chips in its input, and every message carries them with the rule to edit only these items until they are detached. Items already attached (or their linked partner) are skipped.

- Mode: ui · Runs: immediately · MCP: `bashcut_chat_attach`
- `items`: string, required. Item IDs, comma-separated
- `plugin`: string. Chat agent plugin ID; by default the one shown in the dock, else the first

### `bashcut chat detach [--items <items>] [--plugin <plugin>]`

Remove attached timeline items from a chat agent's request, like the chip's ×; without --items, all of them.

- Mode: ui · Runs: immediately · MCP: `bashcut_chat_detach`
- `items`: string. Item IDs, comma-separated
- `plugin`: string. Chat agent plugin ID; by default the one shown in the dock, else the first

### `bashcut chat stop [--plugin <plugin>]`

Stop a chat agent's running turn.

- Mode: ui · Runs: immediately · MCP: `bashcut_chat_stop`
- `plugin`: string. Chat agent plugin ID; by default the one shown in the dock, else the first

### `bashcut chat commands [--plugin <plugin>]`

The slash commands a chat agent's tab offers: the app's (new, clear, stop, settings, copy, export), the agent kit's skills (skill:<name>) and the plugin's own (for AI Editor: compact, model, thinking, session), with their arguments and choices.

- Mode: read · Runs: immediately · MCP: `bashcut_chat_commands`
- `plugin`: string. Chat agent plugin ID; by default the one shown in the dock, else the first

### `bashcut chat command <line> [--plugin <plugin>]`

Run a slash command as typed in a chat agent's tab, such as "/compact keep the caption decisions" or "/thinking low"; returns what it showed. /export needs a path here.

- Mode: edit · Runs: immediately · MCP: `bashcut_chat_command`
- `line`: string, required. The command line, starting with /
- `plugin`: string. Chat agent plugin ID; by default the one shown in the dock, else the first

### `bashcut chat reset [--plugin <plugin>]`

Start a new conversation with a chat agent for this project; the old one is forgotten.

- Mode: edit · Runs: immediately · MCP: `bashcut_chat_reset`
- `plugin`: string. Chat agent plugin ID; by default the one shown in the dock, else the first

### `bashcut chat transcript [--plugin <plugin>]`

A chat agent's conversation for this project: messages, tool rows (command, ok) and whether a turn is running.

- Mode: read · Runs: immediately · MCP: `bashcut_chat_transcript`
- `plugin`: string. Chat agent plugin ID; by default the one shown in the dock, else the first

## ui

### `bashcut ui dialog`

Read the open dialogs (alerts, file panels, sheets), topmost last, with their option IDs.

- Mode: read · Runs: immediately · MCP: `bashcut_ui_dialog`

### `bashcut ui respond [<option>] [--path <path>] [--dialog <dialog>]`

Answer the topmost dialog like the user: choose an option ID or title, or give a path to a file panel.

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_respond`
- `option`: string. Option ID or title
- `path`: string, path. File or folder for an open/save panel
- `dialog`: string. Only answer if this dialog ID is topmost

### `bashcut ui open <dialog>`

Open a sheet or popover in the app.

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_open`
- `dialog`: string, required, one of new-project, export, export-report, agent-changes, review, history, plugins, settings, doctor, knowledge, ask, sections, external-changes, plugin-proposals, commands, shortcuts, add-plugin, library-search, library-generate. Dialog

### `bashcut ui select [<item>] [--items <items>] [--add] [--track <track>]`

Select timeline items in the app (omit them to clear the selection), or a layer with --track. Several items: --items a,b,c; --add keeps the current selection.

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_select`
- `item`: string. Stable item ID
- `items`: string. More item IDs, comma-separated
- `add`: boolean. Add to the current selection
- `track`: string. Layer (track) ID to select

### `bashcut ui actions`

List every editor action (buttons, menu items, keyboard shortcuts) with its shortcuts and whether it is enabled now.

- Mode: read · Runs: immediately · MCP: `bashcut_ui_actions`

### `bashcut ui action <action>`

Run an editor action like the user: by ID (timeline.split, timeline.zoom-in, playback.toggle) or by shortcut (cmd+b, space, cmd+=). Actions that open a dialog return at once; answer it with ui.respond.

- Mode: edit · Runs: immediately · MCP: `bashcut_ui_action`
- `action`: string, required. Action ID or shortcut

### `bashcut ui view [--zoom <zoom>] [--zoom-anchor <zoomAnchor>] [--snap <snap>] [--safe-area <safeArea>] [--viewer-zoom <viewerZoom>] [--compare <compare>] [--agent-dock <agentDock>] [--reveal <reveal>] [--inspector <inspector>] [--settings-section <settingsSection>] [--settings-search <settingsSearch>] [--knowledge-section <knowledgeSection>] [--plugins-tab <pluginsTab>] [--plugins-category <pluginsCategory>] [--library-query <libraryQuery>] [--library-pack <libraryPack>] [--library-tag <libraryTag>] [--library-scope <libraryScope>]`

Read the editor view state, or change it: timeline zoom (pixels per second), viewer zoom, snapping, safe area, color compare, agent dock, inspector tab, Settings section and search, Knowledge section, Plugins tab and Browse category, the open library panel's search and filters, and scroll the timeline to a frame.

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_view`
- `zoom`: integer, 1…600. Timeline zoom in pixels per second
- `zoomAnchor`: integer, ≥ 0. Frame kept in place by --zoom; the playhead by default
- `snap`: boolean. Snapping on or off
- `safeArea`: boolean. Safe-area overlay on or off
- `viewerZoom`: string, one of fit, 25, 50, 100, 200. Viewer zoom: fit, or a percentage of the output size
- `compare`: boolean. Color before/after compare on or off
- `agentDock`: boolean. Agent dock shown or hidden
- `reveal`: integer, ≥ 0. Scroll the timeline so this frame is visible
- `inspector`: string, one of video, audio, text, color, speed. Inspector tab
- `settingsSection`: string, one of general, agents, plugins, storage. Settings section (open Settings with ui.open settings)
- `settingsSearch`: string. Settings search text: lists matching settings of every section; empty clears it
- `knowledgeSection`: string, one of inbox, lessons, prefs, facts, notes, skills, history. Knowledge window section (open it with ui.open knowledge)
- `pluginsTab`: string, one of installed, browse, updates, activity. Plugins sheet tab (open it with ui.open plugins)
- `pluginsCategory`: string, one of all, agents, captions, voice, audio, color, effects, export, utilities. Category Plugins › Browse shows; all shows every one
- `libraryQuery`: string. Search text of the open library panel; empty clears it
- `libraryPack`: string. Pack the open library panel shows; empty shows all
- `libraryTag`: string. Tag the open library panel shows; empty shows all
- `libraryScope`: string, one of all, built-in, user, project, plugin. Scope the open library panel shows

### `bashcut ui source <media> [--in <in>] [--out <out>]`

Open project media in the source viewer, optionally with in/out frames marked.

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_source`
- `media`: string, required. Media ID
- `in`: integer, ≥ 0. Source in frame
- `out`: integer, ≥ 1. Source out frame (exclusive)

### `bashcut ui seek <frame>`

Move the viewer to a timeline frame.

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_seek`
- `frame`: integer, required, ≥ 0. Timeline frame

### `bashcut ui frame [<frame>]`

Render the viewer's picture at a timeline frame (the playhead by default) to a PNG, like attaching the viewer frame in Ask; returns its path. Read the file to look at the edit. Keeps the ten newest.

- Mode: read · Runs: immediately · MCP: `bashcut_ui_frame`
- `frame`: integer, ≥ 0. Timeline frame; the playhead by default

### `bashcut ui panel <panel>`

Open a library panel in the left rail.

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_panel`
- `panel`: string, required, one of media, audio, text, stickers, effects, transitions, filters, voice. Panel

### `bashcut ui notify <message>`

Show a short status message in BashCut.

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_notify`
- `message`: string, required. Message

## luts

### `bashcut luts import <path> [--name <name>] --base-rev <baseRev>`

Check a .cube LUT, copy it into the project's luts folder and add it (Filters panel).

- Mode: edit · Runs: immediately · MCP: `bashcut_luts_import`
- `path`: string, required, path. .cube file
- `name`: string. Display name; defaults to the file name
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

## edl

### `bashcut edl import <path> [--save-current] [--discard-current]`

Convert a legacy edl.json into project.bashcut.json beside it and open it (Welcome screen). Fails if the open project has unsaved changes unless saveCurrent or discardCurrent is set.

- Mode: edit · Runs: immediately · MCP: `bashcut_edl_import`
- `path`: string, required, path. edl.json file
- `saveCurrent`: boolean, default false. Save the open project first when it has unsaved changes
- `discardCurrent`: boolean, default false. Drop unsaved changes of the open project

## doctor

### `bashcut doctor run`

Run the Doctor checks (workspace, tools, plugins) and return the results.

- Mode: read · Runs: immediately · MCP: `bashcut_doctor_run`

## knowledge

### `bashcut knowledge get`

Read the project memo and skills (stored in the project folder), the notes for every project, and any older memo left in the agent workspace or home folder (legacy).

- Mode: read · Runs: immediately · MCP: `bashcut_knowledge_get`

### `bashcut knowledge memo [<text-file>] [--clear] [--scope <scope>]`

Replace a memo: the project memo (.bashcut/agent-memory.md in the project) or, with scope user, the notes every project reads (Application Support/BashCut/Knowledge). clear empties it. Agents need approval for scope user.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_memo`
- `text`: string. Memo text (CLI: path to a text file); omit it with clear
- `clear`: boolean. Empty the memo instead of replacing its text
- `scope`: string, one of project, user. project (default) or user

### `bashcut knowledge migrate [--to <to>]`

Move the older memo that earlier versions kept in the agent workspace or home folder into the notes for every project (default) or this project's memo; the old file is renamed agent-memory.migrated.md.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_migrate`
- `to`: string, one of user, project. user (default) or project

### `bashcut knowledge split-memo [<entries.json>] [--scope <scope>] [--keep] [--session <session>]`

Split a memo into structured entries, once (#72): read it with knowledge get, then pass a JSON object {"lessons": [{"title", "symptom", "cause", "fix", "evidence", "tags"}], "prefs": [{"key", "value"}], "facts": [{"key", "value"}]} of what it says. Everything waits in the Knowledge inbox for the user's review; entries that already exist are skipped. The memo stays as notes. With keep, nothing is split and the split is not offered again.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_split-memo`
- `entries`: object. What the memo says (CLI: path to a JSON file); required unless keep is set
- `scope`: string, one of project, user. The memo to split: project (default) or user (notes for every project; no facts)
- `keep`: boolean. Keep the memo as notes only and stop offering the split
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge skill <name> <text-file>`

Write a project skill's SKILL.md in the project folder, creating the skill and linking it into the project's .claude/skills and .agents/skills if needed. Needs a saved project.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_skill`
- `name`: string, required. Lowercase hyphenated skill name
- `text`: string, required. SKILL.md text (CLI: path to a text file)

### `bashcut knowledge lessons [--scope <scope>] [--status <status>] [--tag <tag>] [--query <query>] [--sort <sort>]`

List lessons the agent learned (symptom, cause, fix), from this project and for every project, newest first. Read the active ones before editing; proposed ones wait for the user's review.

- Mode: read · Runs: immediately · MCP: `bashcut_knowledge_lessons`
- `scope`: string, one of project, user. Only this scope; both by default
- `status`: string, one of proposed, active, disabled. Only this status
- `tag`: string. Only lessons with this tag
- `query`: string. Text to find in the title, symptom, cause, fix, evidence or tags
- `sort`: string, one of newest, oldest, default "newest". Order by last change; newest first by default

### `bashcut knowledge add-lesson <title> [--symptom <symptom>] [--cause <cause>] [--fix <fix>] [--evidence <evidence>] [--tags <tags>] [--scope <scope>] [--status <status>] [--session <session>]`

Record a lesson: in this project (default) or, with scope user, for every project. Use status proposed when unsure. Agents' lessons for every project are always proposed until the user approves them.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_add-lesson`
- `title`: string, required. Short title
- `symptom`: string. What went wrong or what was noticed
- `cause`: string. Why it happened
- `fix`: string. What to do next time
- `evidence`: string. What shows it (frames, files, the user's words)
- `tags`: string. Comma-separated tags (captions, audio, pacing…)
- `scope`: string, one of project, user, default "project". project (default) or user
- `status`: string, one of active, proposed, default "active". active (default) or proposed
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge update-lesson <id> [--title <title>] [--symptom <symptom>] [--cause <cause>] [--fix <fix>] [--evidence <evidence>] [--tags <tags>] [--status <status>] [--session <session>]`

Change a lesson's fields or status (proposed, active, disabled). Agents changing a lesson for every project need approval.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_update-lesson`
- `id`: string, required. Lesson ID (l-…) from knowledge lessons
- `title`: string. Short title
- `symptom`: string. What went wrong or what was noticed
- `cause`: string. Why it happened
- `fix`: string. What to do next time
- `evidence`: string. What shows it (frames, files, the user's words)
- `tags`: string. Comma-separated tags (captions, audio, pacing…)
- `status`: string, one of proposed, active, disabled. New status
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge remove-lesson <id> [--session <session>]`

Remove a lesson (history keeps it). Agents removing a lesson for every project need approval.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_remove-lesson`
- `id`: string, required. Lesson ID (l-…) from knowledge lessons
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge prefs [<key>] [--scope <scope>]`

Read the user's preferences (taste: length, pace, voice, caption style, music…). A project value wins over the one for every project.

- Mode: read · Runs: immediately · MCP: `bashcut_knowledge_prefs`
- `key`: string. Only this key
- `scope`: string, one of project, user. Only this scope; both by default

### `bashcut knowledge set-pref <key> [<value>] [--remove] [--scope <scope>] [--session <session>]`

Set or remove a preference: for every project (default) or only this project. An agent's change for every project waits in the Knowledge inbox (approval proposed) unless the user lets agents act without confirmation.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_set-pref`
- `key`: string, required. Key
- `value`: string. Value; required unless remove is set
- `remove`: boolean. Remove the key instead of setting it
- `scope`: string, one of project, user, default "user". user (default) or project
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge facts [<key>]`

Read this project's facts (people, places, footage notes, what was approved).

- Mode: read · Runs: immediately · MCP: `bashcut_knowledge_facts`
- `key`: string. Only this key

### `bashcut knowledge set-fact <key> [<value>] [--remove] [--session <session>]`

Set or remove a fact about this project. Needs a saved project.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_set-fact`
- `key`: string, required. Key
- `value`: string. Value; required unless remove is set
- `remove`: boolean. Remove the key instead of setting it
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge proposals [--scope <scope>]`

List what waits for the user's review in the Knowledge inbox: proposed lessons (type lesson, id l-…) and agents' preference changes for every project (type value, id p-…; value null removes the key).

- Mode: read · Runs: immediately · MCP: `bashcut_knowledge_proposals`
- `scope`: string, one of project, user. Only this scope; both by default

### `bashcut knowledge approve <id> [--value <value>] [--session <session>]`

Approve a proposal: a proposed lesson becomes active, a preference change is applied. The user decides: an agent's request asks for approval.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_approve`
- `id`: string, required. Proposal ID (l-… or p-…) from knowledge proposals
- `value`: string. For a preference proposal: apply this value instead (edit)
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge reject <id> [--session <session>]`

Reject a proposal: a proposed lesson is removed, a preference change is dropped; history keeps both. An agent's request asks for approval.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_reject`
- `id`: string, required. Proposal ID (l-… or p-…) from knowledge proposals
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge history [--scope <scope>] [--kind <kind>] [--target <target>] [--limit <limit>]`

List changes to lessons, preferences, facts, memos and project skills, newest first: who made them, the entry before and after, and a line diff. Undo one with knowledge revert.

- Mode: read · Runs: immediately · MCP: `bashcut_knowledge_history`
- `scope`: string, one of project, user. Only this scope; both by default
- `kind`: string, one of lesson, prefs, facts, memo, skill. Only changes to this kind of entry
- `target`: string. Only changes to this lesson ID, key or skill name
- `limit`: integer, 1…500, default 50. Number of changes

### `bashcut knowledge revert <id> [--session <session>]`

Put an entry back to how it was before a change from knowledge history: a removed entry comes back, an added one goes, an edit is undone (later changes to the same entry too). History records the revert. Agents reverting a change for every project need approval.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_revert`
- `id`: string, required. Change ID from knowledge history
- `session`: string. Your agent session ID, recorded as the source

## skills

### `bashcut skills list [--scope <scope>]`

List skills: this project's, the ones for every project (user), the ones trusted and enabled plugins ship (plugin, read-only, named <plugin-id>:<name>) and the agent kit's (read-only), with whether agents get them (enabled), their description and path.

- Mode: read · Runs: immediately · MCP: `bashcut_skills_list`
- `scope`: string, one of project, user, plugin, kit. Only this scope

### `bashcut skills get <name> [--scope <scope>]`

Read a skill's SKILL.md. Without scope, the project's skill wins over the one for every project, then a plugin's (<plugin-id>:<name>; with scope plugin a bare name works when one plugin has it), then the kit's. To change a plugin's skill, save a copy with skills save.

- Mode: read · Runs: immediately · MCP: `bashcut_skills_get`
- `name`: string, required. Skill name; a plugin's is <plugin-id>:<name>
- `scope`: string, one of project, user, plugin, kit. Where to look

### `bashcut skills save <name> <text-file> [--scope <scope>] [--session <session>]`

Write a skill's SKILL.md, creating the skill if needed: in the project (linked for Claude and Codex; needs a saved project) or, with scope user, for every project (agents need approval). Kit skills are read-only: use skills propose.

- Mode: edit · Runs: immediately · MCP: `bashcut_skills_save`
- `name`: string, required. Skill name (lowercase, hyphenated)
- `text`: string, required. SKILL.md text (CLI: path to a text file)
- `scope`: string, one of project, user, default "project". project (default) or user (every project)
- `session`: string. Your agent session ID, recorded as the source

### `bashcut skills enable <name> [--scope <scope>]`

Turn a skill on for agents: a project skill is linked into the project's .claude/skills and .agents/skills; a skill for every project is listed in the agents' knowledge again. Agents need approval for scope user.

- Mode: edit · Runs: immediately · MCP: `bashcut_skills_enable`
- `name`: string, required. Skill name (lowercase, hyphenated)
- `scope`: string, one of project, user, default "project". project (default) or user (every project)

### `bashcut skills disable <name> [--scope <scope>]`

Turn a skill off without deleting it: a project skill is unlinked from the project's agent folders; a skill for every project is left out of the agents' knowledge. Agents need approval for scope user.

- Mode: edit · Runs: immediately · MCP: `bashcut_skills_disable`
- `name`: string, required. Skill name (lowercase, hyphenated)
- `scope`: string, one of project, user, default "project". project (default) or user (every project)

### `bashcut skills remove <name> [--scope <scope>] [--session <session>]`

Delete a project skill or a skill for every project (history keeps its text; knowledge revert brings it back). Agents need approval for scope user.

- Mode: edit · Runs: immediately · MCP: `bashcut_skills_remove`
- `name`: string, required. Skill name (lowercase, hyphenated)
- `scope`: string, one of project, user, default "project". project (default) or user (every project)
- `session`: string. Your agent session ID, recorded as the source

### `bashcut skills propose <name> <text-file> --summary <summary> [--reason <reason>] [--session <session>]`

Propose a change to an agent kit skill: the line diff against the kit's SKILL.md waits in the Knowledge inbox as a lesson for every project tagged kit. The kit itself is not changed.

- Mode: edit · Runs: immediately · MCP: `bashcut_skills_propose`
- `name`: string, required. Skill name (lowercase, hyphenated)
- `text`: string, required. SKILL.md text (CLI: path to a text file)
- `summary`: string, required. What the change does, in a few words
- `reason`: string. What happened that shows the kit is wrong or missing a step
- `session`: string. Your agent session ID, recorded as the source

## library

### `bashcut library list [--kind <kind>] [--panel <panel>] [--tag <tag>] [--scope <scope>] [--created-by <createdBy>] [--pack <pack>] [--query <query>]`

List library items (Audio, Text, Stickers, Effects, Transitions, Filters, Voice) from the open project, this Mac, plugins and built-in packs, with usage. Check here before making something new.

- Mode: read · Runs: immediately · MCP: `bashcut_library_list`
- `kind`: string, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice. Item kind
- `panel`: string, one of audio, text, stickers, effects, transitions, filters, voice. Only items the library panel shows
- `tag`: string. Only items with this tag
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `createdBy`: string, one of user, agent, plugin, built-in. Only items made by
- `pack`: string. Only items in this pack
- `query`: string. Text to find in the id, name, pack or tags

### `bashcut library get <id> [--scope <scope>]`

Read one library item, with its earlier versions and file paths.

- Mode: read · Runs: immediately · MCP: `bashcut_library_get`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in

### `bashcut library stats [--kind <kind>] [--panel <panel>]`

Usage of every library item, the saved items nobody used, and groups of duplicates (same kind and content), to find what to prune or merge.

- Mode: read · Runs: immediately · MCP: `bashcut_library_stats`
- `kind`: string, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice. Item kind
- `panel`: string, one of audio, text, stickers, effects, transitions, filters, voice. Only items the library panel shows

### `bashcut library add [--kind <kind>] [--name <name>] [--from-result <fromResult>] [--id <id>] [--scope <scope>] [--tags <tags>] [--pack <pack>] [--params <params>] [--file <file>] [--preview <preview>] [--source <source>] [--license <license>]`

Save a new library item in the project or on this Mac. Files are copied in. Agents saving to the user scope wait for approval. To improve an existing item, use library update. fromResult saves a candidate of a finished library search or library generate job instead (its kind, name, files, source and license; the other fields here override them).

- Mode: edit · Runs: immediately · MCP: `bashcut_library_add`
- `kind`: string, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice. Item kind (required unless fromResult)
- `name`: string. Display name (required unless fromResult)
- `fromResult`: string. A library search or generate candidate as <job>:<index> (index from 0, as the job result lists it)
- `id`: string. Item ID: lowercase letters, digits and hyphens; from the name by default
- `scope`: string, one of project, user, default "project". project (the open project's .bashcut/library; the default) or user (this Mac; agents need approval)
- `tags`: string. Comma-separated tags (mood, use, genre…)
- `pack`: string. Pack or collection name the panel groups it under
- `params`: object. What the kind needs (JSON): text-preset {textPreset, text, textStyle: {size, positionY, strokeWidth} (the item property ranges), animation: a clip motion preset}, the last two optional; sticker {emoji, textPreset} or a file (PNG, JPEG, HEIC, WebP, GIF, APNG, or a .mov/.mp4 with alpha; not Lottie) with {stickerKind: emoji|image|animated|video-alpha (from the file by default), size: width as 0.01–1 of the frame, position: center|top|bottom|left|right|top-left|top-right|bottom-left|bottom-right or {x, y} in 0–1, animation: a clip motion preset, seconds}, all optional; effect-preset (a recipe) {steps: [{op: motion|keyframes|speed|speedCurve|reverse|freeze|patch|sfx|text, …}], parameters: {name: {default, min, max}}} or the older {patch: item properties}, with its own sound as file; transition-preset {kind, duration, easing: linear|in|out|inOut, sfx: audio item ID} (or its own sound as file); look (a filter stack) {color: {exposure, contrast, saturation, lutStrength}, lutName} with an optional .cube LUT as file; audio (its file required) {role: music|sfx|ambience, seconds, bpm, loopable, lufs, truePeak}, all optional (library add measures seconds and picks a role by length; library analyze fills the rest), with mood and genre as tags
- `file`: string, path. File to copy in (audio, image or alpha-movie sticker, a look's .cube LUT…)
- `preview`: string, path. Preview image, GIF or audio snippet to copy in
- `source`: string. Where it came from (URL or note)
- `license`: string. License or terms of use

### `bashcut library update <id> [--scope <scope>] [--name <name>] [--tags <tags>] [--pack <pack>] [--params <params>] [--file <file>] [--preview <preview>] [--source <source>] [--license <license>] [--as <as>] [--into <into>]`

Improve a library item: saves a new version (the old one stays in its history). Built-in and plugin items are read-only, so pass as to save an improved copy under a new ID instead.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_update`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `name`: string. New display name
- `tags`: string. Comma-separated tags (mood, use, genre…)
- `pack`: string. Pack or collection name the panel groups it under
- `params`: object. What the kind needs (JSON): text-preset {textPreset, text, textStyle: {size, positionY, strokeWidth} (the item property ranges), animation: a clip motion preset}, the last two optional; sticker {emoji, textPreset} or a file (PNG, JPEG, HEIC, WebP, GIF, APNG, or a .mov/.mp4 with alpha; not Lottie) with {stickerKind: emoji|image|animated|video-alpha (from the file by default), size: width as 0.01–1 of the frame, position: center|top|bottom|left|right|top-left|top-right|bottom-left|bottom-right or {x, y} in 0–1, animation: a clip motion preset, seconds}, all optional; effect-preset (a recipe) {steps: [{op: motion|keyframes|speed|speedCurve|reverse|freeze|patch|sfx|text, …}], parameters: {name: {default, min, max}}} or the older {patch: item properties}, with its own sound as file; transition-preset {kind, duration, easing: linear|in|out|inOut, sfx: audio item ID} (or its own sound as file); look (a filter stack) {color: {exposure, contrast, saturation, lutStrength}, lutName} with an optional .cube LUT as file; audio (its file required) {role: music|sfx|ambience, seconds, bpm, loopable, lufs, truePeak}, all optional (library add measures seconds and picks a role by length; library analyze fills the rest), with mood and genre as tags
- `file`: string, path. File to copy in (audio, image or alpha-movie sticker, a look's .cube LUT…)
- `preview`: string, path. Preview image, GIF or audio snippet to copy in
- `source`: string. Where it came from (URL or note)
- `license`: string. License or terms of use
- `as`: string. Save a copy under this new ID instead of a new version
- `into`: string, one of project, user. Scope of the copy (with as); project by default

### `bashcut library remove <id> [--scope <scope>]`

Remove a project or user library item and its files. Built-in and plugin items cannot be removed. Agents removing from the user scope wait for approval.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_remove`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in

### `bashcut library save-selection --kind <kind> --name <name> [--id <id>] [--item <item>] [--media <media>] [--scope <scope>] [--tags <tags>] [--pack <pack>]`

Save what is selected on the timeline as a new library item (the panels' Save selection as…): a text item's preset, text, textStyle (size, position, outline) and motion preset when its keyframes are one, a clip's effect as a recipe (reverse, speed or speed ramp, framing, keyframes scaled to the clip's length, and the sound effect at its start; a still of the clip as its preview), the transition at the selected clip (kind, duration, easing and the sound a preset placed there), or a grade as a look: the full filter stack, with the project LUT it uses copied in as the look's file, or an audio clip (or project audio media) as an audio item: its file copied in, its length, and music or sfx from its layer, or an overlay item as a sticker: an image or alpha movie with its file, size, position and length, or an emoji text item with its text preset.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_save-selection`
- `kind`: string, required, one of text-preset, effect-preset, transition-preset, look, audio, sticker. What to save
- `name`: string, required. Display name
- `id`: string. Item ID; from the name by default
- `item`: string. Timeline item ID; the selection by default
- `media`: string. Audio: project audio media ID instead of a timeline clip
- `scope`: string, one of project, user, default "project". project (the open project's .bashcut/library; the default) or user (this Mac; agents need approval)
- `tags`: string. Comma-separated tags (mood, use, genre…)
- `pack`: string. Pack or collection name the panel groups it under

### `bashcut library move <id> [--scope <scope>] --to <to>`

Move a saved item between the project and this Mac, with its versions, files and use count. Agents moving into or out of the user scope wait for approval.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_move`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `to`: string, required, one of project, user. Destination

### `bashcut library apply <id> [--scope <scope>] [--item <item>] [--set <set>] [--from <from>] [--to <to>] --base-rev <baseRev>`

Use a library item on an existing timeline item: a text preset on a text item (its preset, then its stored textStyle over the item's and its animation, as one undo step), an effect preset's recipe on a clip (every step, its sounds and text, and a split for a from/to range, as one undo step; set overrides its parameters; when a reverse step needs a new reversed copy it runs as a job), a look's grade (adding its LUT to the project when it has one, in the same undo step), or a transition preset at the cut beside a video clip (its kind, duration and easing, plus its sound on an SFX layer, as one undo step). Defaults to the selected item.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_apply`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `item`: string. Timeline item ID; the selection by default
- `set`: string. Effect preset parameters: name=value pairs (strength=1.5,frames=12) or a JSON object
- `from`: integer, ≥ 0. Effect preset: first timeline frame of the part of the clip to change
- `to`: integer, ≥ 1. Effect preset: timeline frame after that part (the clip's end by default)
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut library place <id> [--scope <scope>] [--at-frame <atFrame>] [--duration <duration>] [--track <track>] [--position <position>] [--size <size>] [--text <text>] --base-rev <baseRev>`

Add a library item to the timeline as a new item: a text preset (with its stored textStyle and animation) or emoji sticker as text, an image, animated or video-alpha sticker (its file copied into the project's stickers/ folder once per content, imported and placed on the Overlay layer, added when missing, at size and position, as one undo step; an animated sticker shows its first frame for now and the result says so), a look as an adjustment (with its LUT added to the project in the same undo step), or audio: its file copied into the project's music/ or sfx/ folder (once per content), imported and placed on the Music layer (music, ambience) or SFX layer (sfx), the layer added when missing, as one undo step. duration trims a sound; longer than the file, a loopable sound repeats back to back and another plays once (the result says so). At the playhead by default.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_place`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `atFrame`: integer, ≥ 0. First timeline frame
- `duration`: integer, ≥ 1. Length in timeline frames
- `track`: string. Layer ID; for audio, the Music or SFX layer by its role by default; for a sticker, the Overlay layer
- `position`: string. Sticker: center, top, bottom, left, right, top-left, top-right, bottom-left or bottom-right (inside the safe area), or x,y in 0–1 (its centre, from the top left); the sticker's default otherwise
- `size`: number, 0.01…1. Sticker: width as a fraction of the frame width (0.3 by default)
- `text`: string. Text for a text preset instead of its sample
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut library analyze <id> [--scope <scope>] [--provider <provider>]`

Measure an audio library item's file and save the values as a new version: its length, integrated loudness and true peak (an audio.loudness provider, as audio measure) and, unless it is a sound effect, its tempo in BPM (an audio.beats provider, as beats detect). Runs as a job; a missing provider leaves that value and says why in notes. Agents saving to the user scope wait for approval. Tag mood and genre with library update --tags after listening or reading the analysis.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_library_analyze`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `provider`: string. audio.loudness provider ID; the project's choice by default

### `bashcut library preview [<id>] [--scope <scope>] [--stop]`

Play a library item's sound in BashCut (the Audio panel's play button), stopping any other; stop, or no id, stops it.

- Mode: ui · Runs: immediately · MCP: `bashcut_library_preview`
- `id`: string. Item ID, or scope:id
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `stop`: boolean, default false. Stop the sound playing

### `bashcut library search <query> --kind <kind> [--provider <provider>] [--limit <limit>] [--save <save>] [--scope <scope>] [--page <page>]`

Ask an installed plugin that provides library.search (sounds, stickers, GIFs… from Freesound, Giphy or another source) for candidate items of a kind. Runs as a job; its result lists candidates with their fields, downloaded file and preview paths, source and license. Nothing is saved until library add --from-result <job>:<index> (or save here) copies one into the library. Network use is the plugin's.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_library_search`
- `query`: string, required. What to look for
- `kind`: string, required, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice. Item kind
- `provider`: string. Plugin or provider ID; the first available provider that serves the kind by default
- `limit`: integer, 1…50, default 12. Most candidates to return
- `save`: integer, ≥ 0. Also save the candidate with this index (from 0) when the job finishes
- `scope`: string, one of project, user, default "project". Where save puts it: project (the default) or user (agents need approval)
- `page`: integer, 1…1000, default 1. Result page, from 1

### `bashcut library generate <prompt> --kind <kind> [--provider <provider>] [--limit <limit>] [--save <save>] [--scope <scope>] [--params <params>]`

Ask an installed plugin that provides library.generate (AI music, stickers…) to make candidate items of a kind from a prompt. Runs as a job; its result lists candidates like library search. Nothing is saved until library add --from-result <job>:<index> (or save here) copies one into the library.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_library_generate`
- `prompt`: string, required. What to make
- `kind`: string, required, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice. Item kind
- `provider`: string. Plugin or provider ID; the first available provider that serves the kind by default
- `limit`: integer, 1…50, default 4. Most candidates to return
- `save`: integer, ≥ 0. Also save the candidate with this index (from 0) when the job finishes
- `scope`: string, one of project, user, default "project". Where save puts it: project (the default) or user (agents need approval)
- `params`: object. Hints for the provider (JSON), such as {"seconds": 30}

### `bashcut library import-pack <path> [--scope <scope>] [--replace]`

Add a pack (a folder with pack.json and files, or a .zip of one) to the project or user library. IDs already there are refused unless replace saves them as new versions.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_import-pack`
- `path`: string, required, path. Pack folder or .zip
- `scope`: string, one of project, user, default "project". project (the open project's .bashcut/library; the default) or user (this Mac; agents need approval)
- `replace`: boolean, default false. Save items whose ID exists as new versions

### `bashcut library export-pack --output <output> [--pack <pack>] [--kind <kind>] [--scope <scope>] [--name <name>]`

Write library items as a pack folder (pack.json and files) to share or import elsewhere: one pack, or every item of a kind or scope.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_export-pack`
- `output`: string, required, path. New or empty folder to write
- `pack`: string. Items in this pack
- `kind`: string, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice. Item kind
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `name`: string. Pack name; the pack filter or the folder name by default

## fonts

### `bashcut fonts list [--query <query>] [--project] [--vietnamese]`

List fonts for text items (Inspector › Text › Font): the project's fonts folder first, then the fonts installed on this Mac, with PostScript names (textStyle.font) and Vietnamese coverage.

- Mode: read · Runs: immediately · MCP: `bashcut_fonts_list`
- `query`: string. Only names or families containing this text
- `project`: boolean, default false. Only the project's own fonts
- `vietnamese`: boolean, default false. Only fonts with every Vietnamese letter

### `bashcut fonts import <path>`

Copy a .ttf, .otf or .ttc font into the project's fonts folder and use it for this project (Inspector › Text › Font › Add Font…). The font travels with the project; nothing is installed on the Mac.

- Mode: edit · Runs: immediately · MCP: `bashcut_fonts_import`
- `path`: string, required, path. Font file
