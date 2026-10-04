# Command reference

<!-- Generated from CommandCatalog by scripts/update-commands.sh. Do not edit by hand. -->

Every automation command, 86 in all. Each is the same command on the CLI (`bashcut …`), as an
MCP tool (`bashcut_<group>_<command>`, same parameter names as JSON-RPC) and over the socket. Modes and
approval are explained in the [automation guide](../guides/automation.md#permission-modes).

## context

### `bashcut context get`

Read the project path, revision, playhead and selection.

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

### `bashcut project create --name <name> --dir <directory> [--footage <footage>] [--canvas <canvas>] [--resolution <resolution>] [--fps <fps>] [--language <language>] [--save-current] [--discard-current]`

Create a project folder (media, footage, render…) like the New Project wizard and open it.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_create`
- `name`: string, required. Project name
- `directory`: string, required, path. Absolute parent folder for the new project folder
- `footage`: string, path. Footage folder to link (never modified)
- `canvas`: string, one of portrait, landscape, square, default "portrait". Canvas
- `resolution`: string, one of 720, 1080, 2160, default "1080". Short-side resolution
- `fps`: string, one of 29.97, 30, 24, 60, default "29.97". Frame rate
- `language`: string, default "vi". Content language tag
- `saveCurrent`: boolean, default false. Save the open project first when it has unsaved changes
- `discardCurrent`: boolean, default false. Drop unsaved changes of the open project

### `bashcut project save`

Save the open project to disk.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_save`

### `bashcut project format [--canvas <canvas>] [--clips <clips>] [--resolution <resolution>] --base-rev <baseRev>`

Change the open project's canvas like the format menu in the toolbar: portrait 9:16, landscape 16:9 or square, at a short-side resolution (the current one by default); timing is kept and clip pan/tilt scale with the frame. --clips fit shows each clip whole (bars where its shape differs), fill covers the frame and crops; a clip's own `fill` property overrides it. Each change is one undoable edit.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_format`
- `canvas`: string, one of portrait, landscape, square. Canvas
- `clips`: string, one of fit, fill. How clips meet the frame by default
- `resolution`: string, one of 720, 1080, 2160. Short-side resolution; the current one by default
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

Atomically apply validated timeline operations as one undoable edit.

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

Add a media file (path relative to the project or absolute): video, audio or a still image (PNG keeps transparency; placed for 3 s, trims to any length). With place, also put it on a layer like Import.

- Mode: edit · Runs: immediately · MCP: `bashcut_media_import`
- `path`: string, required, path. Media file path
- `kind`: string, one of video, audio, image. Media kind; from the file type by default
- `place`: boolean, default false. Also place it on a layer
- `track`: string. Layer ID for place; defaults to the main layer
- `atFrame`: integer, ≥ 0. Timeline frame for place
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut media proxy [<media>] [--force]`

Queue preview proxies (smaller, quick-to-seek copies in .bashcut/proxies; export keeps the originals) for heavy video media, or one media item. Imports queue them automatically. Returns a status per media: queued with its job ID, exists, not-needed or skipped.

- Mode: edit · Runs: immediately · MCP: `bashcut_media_proxy`
- `media`: string. Project media ID; all video media by default
- `force`: boolean, default false. Make proxies even for light footage, replacing existing ones

### `bashcut media place --media <media> [--track <track>] [--at-frame <atFrame>] --base-rev <baseRev>`

Place project media on a layer (main by default), with linked sound on a dialogue layer; an occupied range spills onto a free or new layer.

- Mode: edit · Runs: immediately · MCP: `bashcut_media_place`
- `media`: string, required. Project media ID
- `track`: string. Layer ID; defaults to the main layer
- `atFrame`: integer, ≥ 0. Timeline frame; defaults to the playhead or the end of the main layer
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

## review

### `bashcut review run`

Run the structural timeline review (not measured audio loudness).

- Mode: read · Runs: immediately · MCP: `bashcut_review_run`

## captions

### `bashcut captions export`

Export captions as SubRip text.

- Mode: read · Runs: immediately · MCP: `bashcut_captions_export`

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

### `bashcut captions generate --media <media> [--replace] [--word-style <wordStyle>] [--provider <provider>]`

Transcribe project media with a captions.transcribe provider and import the captions as one undoable edit. Captions follow the clips where the media is heard (trim, position, speed): place the clips first.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_captions_generate`
- `media`: string, required. Project media ID
- `replace`: boolean, default false. Replace this media's captions
- `wordStyle`: string, one of highlight, karaoke, reveal, none. Show words as they are spoken (see captions.words)
- `provider`: string. Provider ID overriding the project preference for one request

## export

### `bashcut export status`

Read the export state: while one runs, its job, step, preset and path (last receipt under lastExport); otherwise the most recent receipt. Includes the queue (job IDs for jobs.cancel).

- Mode: read · Runs: immediately · MCP: `bashcut_export_status`

### `bashcut export start --preset <preset> --name <name> [--output-dir <directory>] [--include-srt] [--normalize-audio]`

Request a background video export; the user approves it in the app first. Approved exports queue behind a running one.

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_export_start`
- `preset`: string, required, one of tiktok, youtube-1080, youtube-4k, quick-draft, prores. Export preset
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

### `bashcut plugins list`

List installed plugins, their providers and project provider preferences.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_list`

### `bashcut plugins actions`

List actions plugins add to the editor (Plugins menu, toolbar, context menus, panels) with their parameters as JSON Schema, placements and whether each is available now.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_actions`

### `bashcut plugins run <action> [--params <params>]`

Run a plugin action like clicking it, with parameters (CLI: --params '{"mode":"vivid"}'). The plugin's proposed operations are validated and applied as one undoable edit attributed to the plugin.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_plugins_run`
- `action`: string, required. Action ID from plugins actions
- `params`: object. Action parameters (JSON object)

### `bashcut plugins hooks`

List plugin hook subscriptions, the recent hook runs and hook edits waiting for review.

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

### `bashcut plugins search [<query>] [--capability <capability>] [--refresh]`

Search the plugin registry (Plugins › Browse): name, summary, capability, the version this BashCut would install and whether it is installed, has an update or is incompatible.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_search`
- `query`: string. Search text
- `capability`: string. Only providers of this capability, such as captions.transcribe
- `refresh`: boolean, default false. Fetch the registry again instead of using the 5-minute cache

### `bashcut plugins updates`

List installed plugins with a newer compatible version in the registry.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_updates`

### `bashcut plugins install <plugin> [--version <version>]`

Download a registry plugin (or its update), check its SHA-256 and manifest, and show the install approval in the Plugins sheet. Only the user can approve; the job ends when the approval is shown.

- Mode: edit · Runs: as a background job (poll `jobs status`) · MCP: `bashcut_plugins_install`
- `plugin`: string, required. Plugin ID from plugins search
- `version`: string. A specific registry version; the newest compatible by default

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

### `bashcut clip motion [<item>] [--preset <preset>] [--keyframes <keyframes>] --base-rev <baseRev>`

Animate a clip, image or text over its length (Inspector › Animation): a preset (zoom-in, zoom-out, pan-left, pan-right, pan-up, pan-down, fade-in-out, pop-in, slide-up, zoom-punch; none removes the animation) sized to the item, or keyframes JSON {property: [{frame, value, ease?}, …]} with frames from the item's start. Properties: zoom, pan, tilt (px, up), rotation (degrees), opacity, and volume (dB, like volumeDb; the only one on audio items, none on text); ease: linear, in, out, inOut, hold (default inOut). Keys replace the item's static value for that property. Images with zoom-in, zoom-out or pan-* make a Ken Burns move; presets are for pictures and text.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_motion`
- `item`: string. Item ID; the selection by default
- `preset`: string, one of zoom-in, zoom-out, pan-left, pan-right, pan-up, pan-down, fade-in-out, pop-in, slide-up, zoom-punch, none. Preset name, or none
- `keyframes`: string. Keyframes as JSON, replacing the item's animation
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

## storage

### `bashcut storage get`

What BashCut keeps on disk (Settings › Storage): plugin folders, each plugin's data and cache, the saved plugin registry, this project's preview proxies, ramp audio and the audit log, with sizes and paths.

- Mode: read · Runs: immediately · MCP: `bashcut_storage_get`

### `bashcut storage clear <target> [--plugin <plugin>]`

Delete what can be made or downloaded again: plugin-cache (all plugins, or --plugin), registry, proxies or ramp-audio (made again on demand), or plugin-data --plugin ID (the plugin must be set up again).

- Mode: edit · Runs: immediately · MCP: `bashcut_storage_clear`
- `target`: string, required, one of plugin-cache, plugin-data, registry, proxies, ramp-audio. What to clear
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

### `bashcut chat stop [--plugin <plugin>]`

Stop a chat agent's running turn.

- Mode: ui · Runs: immediately · MCP: `bashcut_chat_stop`
- `plugin`: string. Chat agent plugin ID; by default the one shown in the dock, else the first

### `bashcut chat commands [--plugin <plugin>]`

The slash commands a chat agent's tab offers: the app's (new, clear, stop, settings, copy, export), the agent kit's skills (skill:<name>) and the plugin's own (for Director: compact, model, thinking, session), with their arguments and choices.

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
- `dialog`: string, required, one of new-project, export, export-report, agent-changes, review, history, plugins, settings, doctor, knowledge, ask, sections, external-changes, plugin-proposals, commands, shortcuts. Dialog

### `bashcut ui select [<item>] [--track <track>]`

Select a timeline item in the app (omit item to clear the selection), or a layer with --track.

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_select`
- `item`: string. Stable item ID
- `track`: string. Layer (track) ID to select

### `bashcut ui actions`

List every editor action (buttons, menu items, keyboard shortcuts) with its shortcuts and whether it is enabled now.

- Mode: read · Runs: immediately · MCP: `bashcut_ui_actions`

### `bashcut ui action <action>`

Run an editor action like the user: by ID (timeline.split, timeline.zoom-in, playback.toggle) or by shortcut (cmd+b, space, cmd+=). Actions that open a dialog return at once; answer it with ui.respond.

- Mode: edit · Runs: immediately · MCP: `bashcut_ui_action`
- `action`: string, required. Action ID or shortcut

### `bashcut ui view [--zoom <zoom>] [--zoom-anchor <zoomAnchor>] [--snap <snap>] [--safe-area <safeArea>] [--viewer-zoom <viewerZoom>] [--compare <compare>] [--agent-dock <agentDock>] [--reveal <reveal>] [--inspector <inspector>] [--settings-section <settingsSection>]`

Read the editor view state, or change it: timeline zoom (pixels per second), viewer zoom, snapping, safe area, color compare, agent dock, inspector tab, Settings section, and scroll the timeline to a frame.

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

Read the project memo and project skills shared with the agents.

- Mode: read · Runs: immediately · MCP: `bashcut_knowledge_get`

### `bashcut knowledge memo <text-file>`

Replace the project memo (.bashcut/agent-memory.md).

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_memo`
- `text`: string, required. Memo text (CLI: path to a text file)

### `bashcut knowledge skill <name> <text-file>`

Write a project skill's SKILL.md, creating the skill and sharing it with Claude and Codex if needed.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_skill`
- `name`: string, required. Lowercase hyphenated skill name
- `text`: string, required. SKILL.md text (CLI: path to a text file)
