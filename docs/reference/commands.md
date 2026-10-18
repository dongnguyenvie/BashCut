# Command reference

<!-- Generated from CommandCatalog by scripts/update-commands.sh. Do not edit by hand. -->

Every automation command, 249 in all. Each is the same command on the CLI (`bashcut …`), as an
MCP tool (`bashcut_<group>_<command>`, same parameter names as JSON-RPC) and over the socket. Modes and
approval are explained in the [automation guide](../guides/automation.md#permission-modes).

## context

### `bashcut context get`

Read the project path, revision, playhead and selection, and a summary of the agent knowledge: active lessons, preferences, project facts and the number of proposals; scope lists the timeline items attached to your tab's request (edit only those), with the scope guard's mode, a held edit and the user's answer to the last one (last); agentPermissions tells what you may do without asking; analysis lists running analysis jobs and the media not yet measured (media.analyze), transcribed (media.transcribe) or described (media.describe), so a plan does not use defaults where measurements are missing; plan summarises the brief (goal, outputs, length) and the edit plan (mode, stage, section/shot/beat counts, frozen sections, recipe, promise, checks count, requiredStages, naStages); workflow has the gates, the checkpoint, checklist (each stage's status, audit verdicts, open points; run checklist has it all) and next {stage, skill, skillRead, recipe when unread}: the one skill to read now; recentFailures lists your session's failed requests of the last 15 minutes (method, code, category, message) and repeated, how many in a row at the newest end share a method and category: stop and rethink after repeated ones.

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

### `bashcut project create --name <name> [--dir <directory>] [--footage <footage>] [--canvas <canvas>] [--resolution <resolution>] [--fps <fps>] [--language <language>] [--import] [--brand <brand>] [--save-current] [--discard-current]`

Create a project folder (media, footage, render…) like the New Project wizard and open it. With import, also import every video, audio and image file in footage (as media import FOLDER) and start media transcribe and media analyze for them: the result adds import (files, converting) and jobs {transcribe, analyze} (a job ID, or {error} when it could not start), so one call readies the footage for a survey. A folder of that name without a project (say one the footage was copied into) becomes the project: the project folders are added and its files stay where they are.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_create`
- `name`: string, required. Project name
- `directory`: string, path. Absolute parent folder for the new project folder; defaults to the projects folder (see project folder)
- `footage`: string, path. Footage folder to link (never modified), or one file: its folder is linked and import takes only that file
- `canvas`: string, one of auto, portrait, landscape, square, default "auto". Canvas; auto starts portrait and lets the first video or image clip set the shape
- `resolution`: string, one of 720, 1080, 2160, default "1080". Short-side resolution
- `fps`: string, one of 29.97, 30, 24, 60, default "29.97". Frame rate
- `language`: string. Content language (BCP 47) of speech and captions, from the user's prompt or answer; no default
- `importFootage`: boolean, default false. Import the footage folder's files and start transcription and picture analysis
- `brand`: string. A brand kit from the library (this Mac, a plugin or built in) to apply to the new project, as library apply
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

### `bashcut project format [--canvas <canvas>] [--clips <clips>] [--resolution <resolution>] [--outputs <outputs>] [--language <language>] --base-rev <baseRev>`

Change the open project's canvas like the format menu in the toolbar: portrait 9:16, landscape 16:9 or square, at a short-side resolution (the current one by default); timing is kept and clip pan/tilt scale with the frame. --clips fit shows each clip whole (bars where its shape differs), fill covers the frame and crops; a clip's own `fill` property overrides it. --outputs sets the export presets the project is made for (first one primary): review checks the first one's platform (safe area, longest length, smallest text) and the Export sheet starts with it. --language sets the content language (captions, speech-rate units, voices, font checks), for a project created without one once its footage is transcribed. Each change is one undoable edit.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_format`
- `canvas`: string, one of portrait, landscape, square. Canvas
- `clips`: string, one of fit, fill. How clips meet the frame by default
- `resolution`: string, one of 720, 1080, 2160. Short-side resolution; the current one by default
- `outputs`: string. Comma-separated export presets (tiktok, reels, shorts, feed-4x5, square, portrait-3x4, youtube-1080, youtube-4k, quick-draft, prores); none clears them
- `language`: string. Content language, a BCP 47 tag (vi, en, en-US); none clears it
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut project credits`

Rights facts of the media the edit plays (P2-H9): per media {media, name, kind, license and provenance as stored, framesOnTop (frames where it is the picture on top)}, frames, and ai {media, pictureShare}. Raw facts on request; credit wording and disclosure are yours. Nothing is added to the video. With the project's review.credits true, review notes AI picture as info and each export's job result carries these facts.

- Mode: read · Runs: immediately · MCP: `bashcut_project_credits`

### `bashcut project data <key>`

Read a top-level project field: brief, plan or any key of your own (a free JSON object, the agent's notes); null when unset.

- Mode: read · Runs: immediately · MCP: `bashcut_project_data`
- `key`: string, required. brief, plan or your own key

### `bashcut project set-data <key> <value.json> [--merge] [--echo] --base-rev <baseRev>`

Set a top-level project field to a JSON object as one undoable edit; with merge, only the given fields change (null removes one). Identity, format, media and tracks are not data. Core reads only: brief lengthSeconds {min, max} and outputs [names], plan sections [{id, label, lengthSeconds {min, max}, frozen}], shots and beats [{id, text, section}] when present (directly or under value): review compares them with the edit, as info, and context get summarises them so work can resume from them. Returns {key, bytes, keys, rev}; --echo returns the stored value too.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_set-data`
- `key`: string, required. brief, plan or your own key
- `value`: object, required. The object (CLI: path to a JSON file)
- `merge`: boolean. Merge into the stored value: objects key by key (null deletes), arrays and values replace
- `echo`: boolean. Return the stored value as well
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut project derive [--ids <ids>] [--dir <directory>]`

Write a sibling project per select (the kept ones, or ids): same canvas, outputs, review profile, brief and layers, only that media (paths made absolute) and the select's range on Main, with derivedFrom. Several shorts from one long recording; the open project does not change and nothing opens.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_derive`
- `ids`: string. Select IDs instead of the kept ones
- `directory`: string, path. Parent folder; defaults to the one holding this project's folder

### `bashcut project history [--limit <limit>]`

The last projects opened (Welcome screen order, the open one first), each with its exports, posted links and the fingerprint of its latest export (the open project's current timeline when it has none), then what they share: looks, caption presets, music and transitions with how many projects used each, and the hook and cut numbers per project. For variety checks and the creator's own medians; no verdicts.

- Mode: read · Runs: immediately · MCP: `bashcut_project_history`
- `limit`: integer, 1…50, default 10. Projects to read

### `bashcut project recents [--query <query>] [--remove <remove>]`

List recently opened projects, newest first (Open Recent › View All…): name, path, lastOpened and exists. --remove takes one off the list (needs a session).

- Mode: read · Runs: immediately · MCP: `bashcut_project_recents`
- `query`: string. Only projects whose name or path matches these words (fuzzy)
- `remove`: string, path. Project file or folder to remove from the list

## timeline

### `bashcut timeline get [--format <format>]`

Read the revision, format and tracks (IDs, roles, V1/A1 labels), and scale per video or image item: fit or fill, baseScale, zoom and maxZoom (keyframes), pixelRatio (output pixels per source pixel; over 1 is upscaled) now and at maxZoom, maxZoomNative (the largest zoom before upscaling), shown size, frameCoverage and backdrop (blur, color or null). media lists each media's path, kind, license and provenance as stored.

- Mode: read · Runs: immediately · MCP: `bashcut_timeline_get`
- `format`: string, one of json, text. json (default) or a compact text listing

### `bashcut timeline apply <ops.json> --base-rev <baseRev> [--label <label>] [--dry-run] [--why <why>] [--evidence <evidence>] [--expect-fingerprint <expectFingerprint>]`

Atomically apply validated timeline operations as one undoable edit; returns changed false and keeps the revision when nothing changes. why and evidence stay with the undo step (timeline.changes lists them). Both the dry run and the apply return fingerprint (the ops and baseRev); expectFingerprint refuses an apply whose ops differ from the reviewed dry run.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_apply`
- `ops`: array, required. Operations array (CLI: path to ops.json)
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since
- `label`: string, default "Agent edit". Short description of the edit
- `dryRun`: boolean, default false. Validate without editing; return projected duration, changed IDs, cutsInsideWord (clip edges the edit leaves inside a transcribed word), fingerprint and, when the attached scope would hold or refuse the edit, outsideScope
- `why`: string. Why this edit, in one sentence (up to 500 characters)
- `evidence`: string. What it rests on, separated by ; (review issue IDs, transcript ranges, measurements; up to 20, 200 characters each)
- `expectFingerprint`: string. The dry run's fingerprint; refuse other ops

### `bashcut timeline cut-range --from <from> --to <to> [--tracks <tracks>] [--continuous <continuous>] [--label <label>] [--dry-run] [--why <why>] [--evidence <evidence>] --base-rev <baseRev>`

Cut a span of time out of the whole timeline as one undoable edit (op rippleDeleteRange): on every layer (or tracks) items inside go, items over an edge are trimmed, a clip over the whole span is split with its parts joined, and captions lose the words inside; everything later moves left with the markers, sections and beat grid. Linked sound gets its picture's cut; a music bed keeps playing and loses its tail. Returns rev, duration and cutsInsideWord (clip edges left inside a transcribed word); dryRun returns what timeline.apply's dry run does.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_cut-range`
- `from`: integer, required, ≥ 0. First timeline frame to remove
- `to`: integer, required, ≥ 1. Timeline frame after the last one removed
- `tracks`: string. Only these layers, comma-separated IDs or labels (V1, A2); linked partners' layers are cut too. Default: every layer
- `continuous`: string. Layers whose items keep their source running and lose their tail instead of being split, comma-separated; none for no layer. Default: the music layers
- `label`: string. Short description of the edit
- `dryRun`: boolean, default false. Validate without editing; return the projected result
- `why`: string. Why this edit, in one sentence (up to 500 characters)
- `evidence`: string. What it rests on, separated by ;
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut timeline changes [--limit <limit>] [--author <author>]`

Recent edits from the undo history, newest first: step, label, author, why, evidence, at, the rev each produced and changes {counts, text, truncated}; undone lists what redo would bring back. Edits made before why was recorded have only label and author.

- Mode: read · Runs: immediately · MCP: `bashcut_timeline_changes`
- `limit`: integer, 1…50, default 10. Most edits to list
- `author`: string. Only this author (user, claude, codex, …), or agent for any agent

### `bashcut timeline undo --base-rev <baseRev>`

Undo one timeline action.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_undo`
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut timeline redo --base-rev <baseRev>`

Redo one timeline action.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_redo`
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut timeline move <item> --track <track> --at-frame <atFrame> --base-rev <baseRev>`

Move an item and its linked partner; an occupied range spills onto a free or new layer.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_move`
- `item`: string, required. Item ID
- `track`: string, required. Destination layer ID
- `atFrame`: integer, required, ≥ 0. Timeline frame
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut timeline close-gap --at-frame <atFrame> [--track <track>] --base-rev <baseRev>`

Delete an empty gap on a layer (the main layer by default): later clips on that layer move left by the gap's length, with their linked sound.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_close-gap`
- `atFrame`: integer, required, ≥ 0. A frame inside the gap
- `track`: string. Layer ID; defaults to the main layer
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut timeline move-items --items <items> [--by <by>] [--before <before>] [--track <track>] --base-rev <baseRev>`

Move several items together in one undo step, like dragging a timeline selection: by shifts each item that many frames on its own layer, keeping their offsets (items on a magnetic layer stay; one landing on another clip spills to a free layer); before moves the given items of the magnetic layer track (Main by default) as one block, in their order, before that clip (an item outside the list) or to the end (end); the layer packs again and linked sound follows. Give by or before. Returns rev and items.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_move-items`
- `items`: string, required. Item IDs, comma separated
- `by`: integer. Frames to move (negative: earlier)
- `before`: string. Magnetic layer: the clip the block goes before, or end
- `track`: string. The magnetic layer for before (default: the main layer)
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut timeline sheet [--at <at>] [--cuts] [--text] [--entries <entries>] [--every <every>] [--size <size>] [--columns <columns>] [--rows <rows>] [--outputs <outputs>]`

Lay the composed edit out on contact sheets without exporting: cells at listed frames (at: numbers, first, last), at every cut on Main (cuts), in the middle of every title (text) and every N seconds (every; 2 s when nothing else is asked), labelled '<cell> <m:ss.s>'. Returns {sheets [{path, output, firstCell, cells}], cells [{cell, frame, seconds, items on screen, text on screen}], index (the same as index.json), cached}. Kept per revision and request in .bashcut/cache/timeline-sheets. With outputs (all: the project's outputs; or preset names) another set of sheets per output of the frame's shape with the zones its interface covers shaded.

- Mode: read · Runs: immediately · MCP: `bashcut_timeline_sheet`
- `at`: string. Frames, comma separated; first and last allowed
- `cuts`: boolean. A cell at the start of every shot on Main
- `text`: boolean. A cell in the middle of every title
- `entries`: string. plan.cut entry IDs, comma separated (c2,t1): a cell in the middle of each item built for them, to look at only what a revision changed
- `every`: number, 0.1…3600. Seconds between cells
- `size`: integer, 64…2048. Long edge of each cell in pixels (default 320)
- `columns`: integer, 1…24. Cells per row (default 8 portrait, 6 landscape)
- `rows`: integer, 1…24. Rows per sheet (default 3 portrait, 6 landscape)
- `outputs`: string. all, or export preset names: sheets with each one's zones

## media

### `bashcut media list [--analysis]`

List project media. With analysis, each media also has analysis: measured false, or {measured, key, measuredAt, picture, sound, shots at the default cut limit, corrected} from media.analyze, and transcript: transcribed false, or the media.transcript overview from media.transcribe. A described media has description {shots, describedBy, describedAt}; with analysis, its media.description coverage.

- Mode: read · Runs: immediately · MCP: `bashcut_media_list`
- `analysis`: boolean. Add what media.analyze measured and media.transcribe heard

### `bashcut media import <path> [--kind <kind>] [--place] [--track <track>] [--at-frame <atFrame>] [--origin <origin>] [--license <license>] [--source <source>] [--author <author>] --base-rev <baseRev>`

Add a media file (path relative to the project or absolute): video, audio or a still image (PNG keeps transparency; placed for 3 s, trims to any length). A folder adds every video, audio and image file directly inside it, in name order, as one edit: {files [{path, media, kind, seconds, existing}], added}; import a folder once rather than file by file. With place (one file), also put it on a layer like Import. A file already in the project, unchanged, reuses its media and returns existing true. origin, license, source and author record where it came from (license is free text, or a JSON object with an open id and the facts you know: commercial, redistribute, attributionRequired, attribution; stored as given). proxy reports the preview copy: converting with a job when this Mac cannot decode the video (AV1, VP9) and BashCut converts it to H.264 in media/converted.

- Mode: edit · Runs: immediately · MCP: `bashcut_media_import`
- `path`: string, required, path. Media file or folder path
- `kind`: string, one of video, audio, image. Media kind; from the file type by default
- `place`: boolean, default false. Also place it on a layer
- `track`: string. Layer ID for place; defaults to the main layer (music for audio)
- `atFrame`: integer, ≥ 0. Timeline frame for place
- `origin`: string, one of stock, web, ai, own, built-in. Where the file came from: stock (a stock library), web (downloaded from another page, such as a CC BY clip), ai, own (the user's footage) or built-in
- `license`: string. Its licence: text as written, or a JSON object {id, redistribute, commercial, attribution…}; stored as given
- `source`: string. Where it was found (URL)
- `author`: string. Who made it, for the credit line
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut media proxy [<media>] [--force]`

Queue preview proxies (smaller, quick-to-seek copies in .bashcut/cache/proxies; export keeps the originals) for heavy video media, or one media item. Imports queue them automatically. Returns a status per media: queued with its job ID, exists, not-needed, skipped, converting (with codec and job) when this Mac cannot decode the video and ffmpeg converts it to H.264 in media/converted (the media then reads the copy), or unsupported (with codec and reason) when there is no ffmpeg.

- Mode: edit · Runs: immediately · MCP: `bashcut_media_proxy`
- `media`: string. Project media ID; all video media by default
- `force`: boolean, default false. Make proxies even for light footage, replacing existing ones

### `bashcut media place --media <media> [--from <from>] [--to <to>] [--track <track>] [--at-frame <atFrame>] --base-rev <baseRev>`

Place project media on a layer (main by default, music for audio), with linked sound on a dialogue layer; an occupied range spills onto a free or new layer. With from and to (source seconds, such as media resolve-range gives), only that part is placed.

- Mode: edit · Runs: immediately · MCP: `bashcut_media_place`
- `media`: string, required. Project media ID
- `from`: number, 0…86400. Source start in seconds
- `to`: number, 0…86400. Source end in seconds
- `track`: string. Layer ID; defaults to the main layer (music for audio)
- `atFrame`: integer, ≥ 0. Timeline frame; defaults to the playhead or the end of the main layer
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut media subjects --media <media> [--step <step>] [--from <from>] [--to <to>] [--provider <provider>] [--request-id <requestId>] [--dry-run]`

Faces and people in the picture of a video or image, with a vision.faces provider (built in: Apple Vision): frames [{seconds, frame (source), faces [{box, confidence}], people [{box, confidence}]}] one picture every step source seconds over from…to; box is [x, y, width, height] as shares of the upright picture from the top left. timeline [{item, at, fromSeconds, toSeconds}] places a second. No labels: which face is the speaker or matters is yours. The boxes are kept per file (merged with earlier runs) for clip.reframe and review.layout's faceOverlap. A job.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_media_subjects`
- `media`: string, required. Project media ID
- `step`: number, 0.04…3600. Source seconds between pictures (default 1; at most 3600 pictures)
- `from`: number, 0…86400. From this source second
- `to`: number, 0…86400. Up to this source second
- `provider`: string. Provider ID overriding the project preference for one request
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut media ocr --media <media> [--step <step>] [--from <from>] [--to <to>] [--provider <provider>] [--languages <languages>] [--request-id <requestId>] [--dry-run]`

On-screen text in the picture of a video or image, with a vision.text provider (built in: Apple Vision): frames [{seconds, frame (source), text [{string, box, confidence}]}] one picture every step source seconds over from…to, lines top to bottom; box as in media.subjects. Use it to read a reference's text cards and caption placement. Whether a line is a caption, a title or a sign is yours. A job.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_media_ocr`
- `media`: string, required. Project media ID
- `step`: number, 0.04…3600. Source seconds between pictures (default 1; at most 3600 pictures)
- `from`: number, 0…86400. From this source second
- `to`: number, 0…86400. Up to this source second
- `provider`: string. Provider ID overriding the project preference for one request
- `languages`: string. BCP 47 languages to try in order, comma separated (default: the provider picks)
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut media sync --media <media> --to <to> [--item <item>] [--provider <provider>] [--request-id <requestId>] [--dry-run]`

Find the time offset between two recordings of the same moment (a camera and a screen recording, or a render played inside a screen recording) from their sound, with an audio.sync provider. The job's result: time in `to` = time in `media` + offsetSeconds, the correlation (below 0.4: no shared sound) and each half of the overlap (steady: no clock drift). With item, also the matching source frame of `to` for that clip's in-point.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_media_sync`
- `media`: string, required. Project media ID of the first recording
- `to`: string, required. Project media ID of the second recording
- `item`: string. A timeline item of the first media whose in-point to map
- `provider`: string. Provider ID overriding the project preference for one request
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut media resolve-range <media> [--quote <quote>] [--words <words>] [--from <from>] [--to <to>]`

A source range from what was said, in the media's stored transcript: a quote (the place its words match best; equal places listed in alternatives, in order, never ranked), word indices FIRST-LAST, or rough from/to seconds snapped outwards to the words they cut into (snap gives how far each edge moved). A quote's matched is the share of its words heard in place: under 1 the transcript differs (a misheard word, or a quote that is not there), so read text before using the range. Returns from/to seconds and in/out frames for media place, the text, and per edge midWord, midSentence (inside a transcript phrase) and the nearest word and sentence edges before and after.

- Mode: read · Runs: immediately · MCP: `bashcut_media_resolve-range`
- `media`: string, required. Project media ID
- `quote`: string. Words as said
- `words`: string. Word indices FIRST-LAST
- `from`: number, 0…86400. Rough start, seconds
- `to`: number, 0…86400. Rough end, seconds

### `bashcut media analyze [--media <media>] [--force] [--rate <rate>]`

Measure source media once and keep the record (by file content, in .bashcut/cache/analysis): file facts (codec, size, rotation, frame timing for variable frame rate, colour transfer/primaries/bit depth, track lengths), picture samples (luma, spread, change, peak as in review.picture, plus sharpness and colourfulness) with every jump searched to its exact frame as a cut candidate, and sound levels (RMS per 0.1 s, peak, stereo correlation). Read it with media.analysis. A record that exists is reused unless force. Ask right after import: media still being converted are measured when the conversion lands. The job's result lists each media with its key and whether it was reused.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_media_analyze`
- `media`: string. Project media ID, or several as A,B; every video and audio media by default
- `force`: boolean. Measure again even when a record exists (drops corrections)
- `rate`: number, 0.5…30. Picture samples per second (default 4)

### `bashcut media analysis --media <media> [--min-score <minScore>] [--activity-db <activityDb>] [--bridge <bridgeSeconds>] [--samples] [--curve]`

Read the media.analyze record of one media without measuring: tech (file facts, variableFrameRate, transferKind sdr/pq/hlg/log/unknown, audioMinusVideoSeconds), picture {cuts (score = cutDifference, or added), shots with the review.shots fields (index, at/atSeconds, duration/seconds in source frames, cutDifference, motion) plus mean luma/spread/sharpness/colourfulness, summary (the review.shots statistics, a shot-length histogram and cuts per 10 s)}, sound {floorDb, medianDb, loudDb, peakDb, silentShare, active spans over floor + activityDb, activeShare, stereoCorrelation} and corrections. The limits are yours: lower minScore to see weaker cuts. No verdicts.

- Mode: read · Runs: immediately · MCP: `bashcut_media_analysis`
- `media`: string, required. Project media ID
- `minScore`: number, 0…1. Lowest candidate score read as a cut (default 0.1)
- `activityDb`: number, 0…80. dB over the sound floor that counts as active (default 10)
- `bridgeSeconds`: number, 0…10. Quiet gaps bridged inside an active span (default 0.3)
- `samples`: boolean. Include every picture sample
- `curve`: boolean. Include the sound level per second (dBFS)

### `bashcut media speech-map --media <media> [--threshold-db <thresholdDb>] [--bridge <bridgeSeconds>] [--min-speech <minSpeechSeconds>] [--min-separation-db <minSeparationDb>]`

Map where an analysed media has sound that may be speech, and the gaps, with the calibration used: the media.analyze level windows (broadband RMS per 0.1 s; digital silence counts as quiet and is left out) are split into quiet and loud by Otsu's method unless thresholdDb is given. calibration {method otsu/given, floorDb, speechDb, separationDb, eta (share of level variance the split explains), otsuThresholdDb, thresholdDb, minSeparationDb, separation clear/weak/none/given}. When the classes are closer than minSeparationDb (noise, music under the voice) separation is none and spans/gaps are null with a reason, instead of made-up silences. Otherwise spans and gaps [{start, end, seconds}] in source seconds, speechSeconds, speechShare, gapStats. With a stored transcript (media.transcribe), transcript {words, spans, gaps, speechSeconds, levelCoveredByWords, wordsCoveredByLevel}. Spans are sound, not proof of speech.

- Mode: read · Runs: immediately · MCP: `bashcut_media_speech-map`
- `media`: string, required. Project media ID
- `thresholdDb`: number, -120…0. dBFS that counts as sound, instead of calibrating
- `bridgeSeconds`: number, 0…10. Gaps bridged inside a span (default 0.3)
- `minSpeechSeconds`: number, 0…10. Shortest span kept (default 0.2)
- `minSeparationDb`: number, 0…60. Classes closer than this do not separate (default 6)

### `bashcut media cuts --media <media> [--add <add>] [--remove <remove>] [--clear]`

Correct the cut list of an analysed media: add cuts or remove candidates at source seconds (a removal matches within one sample interval; removing an added cut takes it back). Shots and statistics in media.analysis follow. Corrections live in the record and are dropped when the file is measured again. Returns the corrected cuts.

- Mode: edit · Runs: immediately · MCP: `bashcut_media_cuts`
- `media`: string, required. Project media ID
- `add`: string. Source seconds to cut at, comma separated
- `remove`: string. Source seconds of cuts to drop, comma separated
- `clear`: boolean. Drop earlier corrections first

### `bashcut media transcribe [--media <media>] [--force] [--provider <provider>] [--request-id <requestId>] [--dry-run]`

Transcribe whole source media once and keep the transcript. A captions.transcribe provider makes it, stored by file content in .bashcut/cache/transcripts; nothing is placed on the timeline. Read it with media.transcript; captions.generate places captions from it without transcribing again, and transcript.words --heard maps its words through the clips. A transcript in the project's content language (by the given provider) is reused unless force. The job's result lists each media with status transcribed, reused or failed and its overview.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_media_transcribe`
- `media`: string. Project media ID; every video and audio media by default
- `force`: boolean. Transcribe again even when a transcript exists
- `provider`: string. Provider ID overriding the project preference for one request
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut media transcript --media <media> [--as <as>] [--from <from>] [--to <to>] [--ranges <ranges>]`

Read the stored transcript of one media in its own seconds (word times kept out of the silences media.analyze measured, as every command reads them; wordsKeptOutOfSilences counts the words moved), with words and phrases counted: language, provider, transcribedAt, speechSeconds, firstSpeech/lastSpeech, precision (wordTimes provider or none, and whether words carry confidence, speakers, events, noSpeechProb, avgLogprob, compressionRatio), then as words: wordList [{index, text, start, end, gapBefore, confidence?, speaker?, event?, noSpeechProb?, avgLogprob?, compressionRatio?}]; phrases (default): phraseList [{index, start, end, seconds, text, words, confidence (mean), gapBefore}]; json: both; text: one line per phrase (#index start–end seconds | text; print it with --format text). from/to keep what overlaps; ranges reads several windows in one call: text joins them under "== A–B" lines, other formats return {media, ranges: [one result per window]}.

- Mode: read · Runs: immediately · MCP: `bashcut_media_transcript`
- `media`: string, required. Project media ID
- `as`: string, one of words, phrases, json, text. phrases (default), words, json or text
- `from`: number, 0…86400. Only from this source second
- `to`: number, 0…86400. Only up to this source second
- `ranges`: string. Several windows instead of from/to: A:B,C:D in source seconds

### `bashcut media describe [<shots.json>] --media <media> [--merge] [--clear] --base-rev <baseRev>`

Store what you saw in a source media, shot by shot, as one undoable edit (it is saved with the project). Each shot: start and end in source seconds (shots may not overlap) and at least one fact: size, angle, move, direction (open labels; suggested: size ECU/CU/MCU/MS/MWS/WS/EWS/insert, angle eye/high/low/top/dutch/pov/ots, move static/pan/tilt/push/pull/track/orbit/handheld/zoom/crane, direction left/right/toward/away/none), subjects (up to 12 names), tags, people, onScreenText, confidence 0–1, bestMoment (source seconds or null), looked (source seconds of the frames you looked at), note; any other field is kept as given. Replaces the description unless merge (shots overlapping the new ones are replaced) or clear. Obvious slips are repaired and listed in adjusted: numbers as text ("659 s"), subjects as one comma-separated string, labels and notes over their length, a best moment or looked frames outside the shot, a shot running into the next (it ends where the next starts); what cannot be repaired is reported for every shot at once. Returns rev, coverage and adjusted.

- Mode: edit · Runs: immediately · MCP: `bashcut_media_describe`
- `shots`: array. Shots array, or {shots: […]} (CLI: path to shots.json)
- `media`: string, required. Project media ID
- `merge`: boolean. Keep stored shots that the new ones do not overlap
- `clear`: boolean. Remove the description
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut media description [--media <media>]`

Read media descriptions. With media: description {shots, describedBy, describedAt} and coverage {shots, describedSeconds, describedShare, and with a media.analyze record measuredShots, coveredShots (half or more of the measured shot described) and missing [{index, start, end}]}. Without: each media's coverage, describedMedia/totalMedia, measuredShots/coveredShots, missing media IDs and the vocabulary.

- Mode: read · Runs: immediately · MCP: `bashcut_media_description`
- `media`: string. Project media ID; every media by default

### `bashcut media frames [--media <media>] [--file <file>] [--at <at>] [--every <every>] [--count <count>] [--from <from>] [--to <to>] [--sheet] [--columns <columns>] [--rows <rows>] [--size <size>] [--reference <reference>] [--reference-from <referenceFrom>] [--reference-to <referenceTo>]`

Read exact source frames of media as PNG files (in .bashcut/cache/media-stills; read them to look): at the given source seconds, every N seconds, or count evenly spaced (default 8, each in the middle of its part) over from…to (the whole file by default). Every media with a picture by default. frames [{path, media, frame (exact source frame index), seconds, width, height}]. With sheet: contact sheets of columns × rows cells labelled '<cell> <file> <m:ss.s>' (the colour changes with each media), sheets [{path, cells [{cell, media, frame, seconds}]}], so a cell maps back to its media and second. With reference (one media): a sheet with a REF row from that media (over referenceFrom…referenceTo) above an OURS row, cell for cell. At most 400 frames per call. With file: frames of a video not in the project (a stock or library candidate), at or count over the whole file, frames [{path, file, frame, seconds, width, height}].

- Mode: read · Runs: immediately · MCP: `bashcut_media_frames`
- `media`: string. Media IDs, comma separated; every media with a picture by default
- `file`: string. Absolute path of a video not in the project, instead of media
- `at`: string. Source seconds, comma separated (one media)
- `every`: number, 0.04…3600. Seconds between frames
- `count`: integer, 1…400. Frames per media, evenly spaced (default 8)
- `from`: number, 0…86400. From this source second (one media)
- `to`: number, 0…86400. Up to this source second (one media)
- `sheet`: boolean. Contact sheets instead of one file per frame
- `columns`: integer, 1…24. Cells per row (default 8 portrait, 6 landscape)
- `rows`: integer, 1…24. Rows per sheet (default 3 portrait, 6 landscape)
- `size`: integer, 64…4096. Long edge of each frame in pixels (default 320 on a sheet, 640)
- `reference`: string. Media ID of a reference shown as a REF row
- `referenceFrom`: number, 0…86400. Reference from this source second
- `referenceTo`: number, 0…86400. Reference up to this source second

### `bashcut media frame --media <media> [--at <at>] [--index <index>] [--edge <edge>] [--size <size>]`

Write one source frame of a media as a PNG at source size (or size on the long edge): at source seconds, an exact frame index, or edge first/last (the first frame by default), for chaining, transitions or a generation reference. Returns {path, media, frame, seconds, width, height}.

- Mode: read · Runs: immediately · MCP: `bashcut_media_frame`
- `media`: string, required. Project media ID
- `at`: number, 0…86400. Source seconds
- `index`: integer, ≥ 0. Source frame index
- `edge`: string, one of first, last. first or last
- `size`: integer, 16…16384. Long edge in pixels; the source size by default

### `bashcut media strip --media <media> [--from <from>] [--to <to>] [--count <count>] [--width <width>]`

Draw a filmstrip of a source range as one PNG: count frames (default 8) along the top with their time, a time ruler, the sound level (−60…0 dBFS per 0.1 s, from the media.analyze record or measured now), the media.speech-map gaps shaded (left out when speech and floor do not separate), and the stored transcript's words at their times. Returns {path, width, height, from, to, frames, levels (analysis, measured or null), gaps {shown, count or reason}, words}.

- Mode: read · Runs: immediately · MCP: `bashcut_media_strip`
- `media`: string, required. Project media ID
- `from`: number, 0…86400. From this source second (default 0)
- `to`: number, 0…86400. Up to this source second (default the end)
- `count`: integer, 1…24. Frames along the top (default 8)
- `width`: integer, 400…8192. Image width in pixels (default 1600)

### `bashcut media inventory [--location-grid <locationGrid>]`

What the footage holds, from one call (read only; capture facts are read once per file and kept in .bashcut/cache/inventory). media [{id, path, folder, kind, seconds, width/height shown and orientation, capturedAt and location as the file records them (null when it does not), device, hasAudio, measured (media.analyze), transcript {language, speechSeconds, words} or null, description coverage}], folders and totals {media, seconds, speechSeconds, languages, measured, transcribed, described, notMeasured, notTranscribed, notDescribed (IDs), capturedFrom/To, locations [{latitude, longitude, media}] grouped on a locationGrid-degree grid, withoutLocation}. Facts only.

- Mode: read · Runs: immediately · MCP: `bashcut_media_inventory`
- `locationGrid`: number, 0…10. Degrees that group places (default 0.001, about 100 m)

### `bashcut media digest [--media <media>] [--from <from>] [--to <to>] [--as <as>]`

Footage facts in one read. A header (seconds, size, speech share, counts), then in time order the described shots (`shot FROM-TO size angle move | subjects | note | best T`, from media describe), each transcript phrase (`START text`, with `[again T]` when a phrase within 120 s says nearly the same words: a possible retake) and the measured cuts no description covers. Whether a line is a retake or a cue to the camera is yours to judge. Reads stored analysis, descriptions and transcripts only (run media analyze, media transcribe and media describe first). The whole project's digest is also written to analysis/digest.json. as json returns {media, name, seconds, size, cuts, speechSeconds, shots [{from, to, size, angle, move, subjects, note, best}], phrases [[start, end, text, againAt?]]}.

- Mode: read · Runs: immediately · MCP: `bashcut_media_digest`
- `media`: string. Only this media
- `from`: number, 0…1000000. From this source second
- `to`: number, 0…1000000. To this source second
- `as`: string, one of text, json. text (default) or json

## review

### `bashcut review run [--measure] [--since-rev <sinceRev>] [--min-severity <minSeverity>] [--summary] [--accepted] [--from <from>] [--to <to>]`

Review the timeline before export: issues {id, kind, severity error|warning|info, title, detail, frame, endFrame?, facts {raw numbers}, fix? {command?, arguments?, hint?}}, errors first. Invariants (gaps, black picture, cut-in-word, missing fonts or glyphs, output length and shape, true peak) are always checked; editorial checks only against the limits in the project's review object, and nothing without them. IDs are anchored to clips. With summary: {issues, summary, checks (measured, stale, notChecked, failed, unreliable, unsetLimits: only limits a check of this timeline reads, atExport: loudness until a normalized export measures it)} and summary.status: fail (errors), incomplete (no errors, but a limit unset or a check not run; atExport does not count) or pass (passed is status == pass; the CLI exits 0, 1 or 2); a pass by an agent is recorded as the review stage unless a stage the plan requires before review is still open (listed in stagesPending); with sinceRev also diff {fixed, new, persisting}. With measure, a revision not measured yet is measured first (review.measure, waited for up to 100 s; measured {job, timedOut} says so), so one call measures and reviews. With from/to only the issues touching those frames are listed and counted (range in the result; a pass is not the review stage), the check after a quick edit. Issues kept with review accept are left out of the list (their IDs in acceptedHidden with summary; counted as accepted) unless accepted is given, which lists them with accepted {reason}.

- Mode: read · Runs: immediately · MCP: `bashcut_review_run`
- `measure`: boolean. Run review measure first when this revision is not measured, and wait for it
- `sinceRev`: integer, ≥ 0. Compare with the review of this revision (this session)
- `minSeverity`: string, one of error, warning, info. Leave out issues less severe than this
- `summary`: boolean. Wrap the issues with counts and a status
- `accepted`: boolean. Also list the issues kept with review accept
- `from`: integer, ≥ 0. Only issues that touch frames from here (with to: [from, to))
- `to`: integer, ≥ 1. Only issues that touch frames before this one

### `bashcut review measure [--picture <picture>] [--plugins <plugins>]`

Run the measured review for this revision and keep it, so review.run includes it: render the timeline small (two frames a second and both sides of every hard cut on Main, proxies allowed) for black or empty picture, frozen picture, long static shots and jump cuts, the contrast of every title and up to eight captions against the picture behind them (review.minTextContrast, a WCAG ratio; unset: the lowest as info), and run every enabled plugin review.check side by side (each at most 30 s; a failing or slow check becomes an info issue). Plugin issues carry source (the plugin ID) and IDs prefixed with the provider. A project turns checks off with review.disabledChecks (plugin or provider IDs; timeline apply setProjectProperties). The job's result has the sample count, hardCuts (touching clips on Main without a transition, the ones measured), the plugin checks that ran and the measured issues; measure again after an edit.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_review_measure`
- `picture`: boolean. Measure the picture (default true)
- `plugins`: boolean. Run plugin review checks (default true)

### `bashcut review accept <id> [--reason <reason>] [--remove] --base-rev <baseRev>`

Keep an issue on purpose, with the reason, as one undoable edit (review.accepted); later runs show it with accepted.reason, leave it out of the counts, and the export report lists it. Accept an error only when no fix exists (the summary counts it as acceptedErrors); to change a whole check, set review.severities.<check> to {severity, reason}. With remove, the issue counts again.

- Mode: edit · Runs: immediately · MCP: `bashcut_review_accept`
- `id`: string, required. Issue ID from review run
- `reason`: string. Why it stays
- `remove`: boolean. Count the issue again
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut review verify <id>`

Prove a fix: the issue as an earlier review of this session saw it (before, beforeRev) against now, measured over the issue's own range and a second around it (picture issues re-sample just that range; others re-run the review), status fixed or persisting, other issues nearby, and window: a still strip of the range with the cuts, words and levels. Loudness needs a normalized export of the revision. Several IDs (comma-separated) or all (the errors and warnings of the last earlier review) are proved in one call: fixed and persisting counts, a row per issue (a window only for what persists) and new issues.

- Mode: read · Runs: immediately · MCP: `bashcut_review_verify`
- `id`: string, required. Issue ID, ID1,ID2,… or all

### `bashcut review packet [--point <point>]`

Write an evidence folder for a fresh critic (a sub-agent with only this folder and bc:review): README, plan.json (brief, plan, review profile, outputs), digest.json (what changed since the last review round), issues.json (with the round diff), shots.json (review.shots with summary), word-landing.json (words against cuts and titles), coverage.json (described shot per clip, script beats heard), measured.json (what was and was not measured), checks.json (the kit's generic checks, plan.checks and plan.promise) and a contact sheet of every cut and title. No editor reasons are included. point picks the audit: draft (default, this folder), strategy (brief with inferred fields, plan, checks, a sheet when the timeline has one, missing) or process (run checklist, run log, timeline changes).

- Mode: read · Runs: immediately · MCP: `bashcut_review_packet`
- `point`: string, one of strategy, draft, process. Audit point (default draft)

### `bashcut review compare --reference <reference> --ours <ours>`

A reference and our render, both imported and measured (media analyze), side by side by the same functions: duration, shots and shot-length median/p25/p75, cuts per minute, picture medians (luma, spread, change, colourfulness, sharpness), sound level median/p10/p90/range and peak, each with ours − reference. No verdict; a metric gets within only when the project's review.compare sets its tolerance.

- Mode: read · Runs: immediately · MCP: `bashcut_review_compare`
- `reference`: string, required. Reference media ID
- `ours`: string, required. Our render's media ID

### `bashcut review picture [--from <from>] [--to <to>] [--samples <samples>] [--cuts <cuts>]`

Read the raw picture measurement of the last review.measure: per sample {frame, seconds, luma, spread, change, peak} at a fixed interval and per hard cut on Main {item, fromItem, frame, before, seconds, difference}, with the units and the noise floors the picture checks use (floors). Values are fractions of full scale on a small grey thumbnail. current is false when the timeline changed since; measure again for this revision. No verdicts: read the numbers to find frozen stretches, flat or dark picture and near-identical cuts.

- Mode: read · Runs: immediately · MCP: `bashcut_review_picture`
- `from`: integer, ≥ 0. First timeline frame (default 0)
- `to`: integer, ≥ 1. Timeline frame after the range (default: the end)
- `samples`: boolean. Include the samples (default true)
- `cuts`: boolean. Include the cuts (default true)

### `bashcut review shots [--summary] [--from <from>] [--to <to>] [--media <media>] [--min-score <minScore>]`

Read the shots on Main in order: index, id, at/atSeconds, duration (frames) and seconds, media, mediaKind, sourceIn and sourceInSeconds, zoom and transform, speed, keyframed properties, freezeFrame/reverse when set, gapBefore (frames since the previous shot), transitionIn {kind, duration, easing} or the picture cutDifference across a hard cut, and motion {mean, peak, samples} (fractions of full scale, see review.picture) when review.measure ran for this revision (pictureMeasured), described (the media.describe facts of the source shot it plays), cameraMove [{property, from, to, perSecond, unit, ease}] from its keyframes, and cut (into it): kind (hard or the transition's kind), sameMedia, sameSetup (same media, overlapping or adjacent source), sourceGapSeconds, framingBefore/After {zoom, pan, tilt} (keyframes included), sameFraming, size/move/direction {from, to} when described. With from/to, only the shots that overlap those frames. No verdicts. With summary: count, total, mean, median, min and max seconds and cuts per minute; rhythm {overall, sections [per section marker]} with mean, median, cv, cutsPerMinute, mode (the most common length bin and its share); shares of each size, move and direction. With media: the same for a source file's measured shots (media.analyze) and its descriptions.

- Mode: read · Runs: immediately · MCP: `bashcut_review_shots`
- `summary`: boolean. Add statistics, rhythm and shares
- `from`: integer, ≥ 0. Only shots that end after this timeline frame
- `to`: integer, ≥ 1. Only shots that start before this timeline frame
- `media`: string. Read a source file's measured shots instead of Main
- `minScore`: number, 0…1. With media: lowest cut score (default 0.1)

### `bashcut review layout [--frame <frame>] [--from <from>] [--to <to>] [--ink] [--contrast]`

Read where text sits as the renderer lays it out: per visible text item id, track, trackRole, at/end, text, preset, lines, longestLineChars, fontPixels and fontShare (of the frame's short side), bounds (pixels from the top-left) and edges (distance to each frame edge as a share of that dimension, negative outside), keyframed when keyframes move it (not followed); holdSeconds, words and wordsPerSecond; speech {onsetOffsetFrames (from the nearest word start), narrationShare (of its time with words spoken)} from the heard or caption words; captionOverlap {item, ratio of its box} for titles; templateRepeats (items with its preset on its layer); faceOverlap {ratio (largest share of one face box the text box covers), frame, item and media of the clip, confidence, samples (pictures with a face while it shows)} from the face boxes media subjects stored for the clips under it (placed with fit/fill, zoom, pan and tilt; null when none are stored: unknown, not "no face"; review.maxFaceOverlap turns it into a text-face review issue). With contrast: contrast {ratio (WCAG, 1–21; basis mean: of the mean text, outline: the stronger of fill and outline, plate: the letters against their box), meanRatio, lightRatio and darkRatio (the light and dark parts of the text, such as fill and outline), textLuminance, backgroundLuminance, textPixels} measured on the frame with and without text (at frame, or each item's middle). Also the frame size, the platform whose zones apply (safeArea, minTextSize), density (titles and captions per minute), facesProvider (face boxes are stored for a clip on screen) and, at a frame, pictures on screen with their scale and coverage (and faceOverlap of an overlay's box with the faces of the other clips). With from/to, only text that overlaps those frames. With ink: ink {frame, luma, mid (0–100), inkShare (pixels text and overlay layers change)} of the composed frame (frame, default 0) against Main alone. No verdicts.

- Mode: read · Runs: immediately · MCP: `bashcut_review_layout`
- `frame`: integer, ≥ 0. Only text on screen at this timeline frame
- `from`: integer, ≥ 0. Only text that ends after this timeline frame
- `to`: integer, ≥ 1. Only text that starts before this timeline frame
- `ink`: boolean. Measure the composed frame (frame, default 0): luma, mid and inkShare
- `contrast`: boolean. Measure each item's contrast on rendered frames

### `bashcut review sync [--events <events>] [--impact-frames <impactFrames>] [--run-gap-seconds <runGapSeconds>] [--bins] [--rendered]`

Time events against the beat grid and the spoken words: per event (cuts on Main by default; text items and sfx items on request) the nearest beat and the nearest word edge (start or end, its text, whether the event falls inside the word) with offsetFrames and offsetMs (positive = after it), and for beats and words count, mean and median offset (with bins also p10, p90 and counts per offset from −6 to +6 frames). Words are the stored transcripts heard through the clips (media.transcribe), else the caption words. With rendered: rendered {windows [{at, lagMs, correlation}], driftMsPerMinute, lagStartMs, lagEndMs} from matching the last export's sound to the timeline's mix every 10 s (positive lag = the render is later); the export must show this revision. impacts adds impacts {summary {count, perMinute, minSpacingSeconds, minSpacingBeats, onStrongestQuarterOfBeats}, events [{frame, frames, source transition|keyframes|overlay, item, kind or changes {property: [from, to]} or media, beat {frame, offsetFrames, strength}, secondsSincePrevious, beatsSincePrevious}]}: changes to the whole picture lasting at most impactFrames (transitions on Main, fast zoom/pan/tilt/rotation/opacity/exposure keys on Main clips and adjustment layers, short pictures over Main). sfx adds sfxRuns [{media, count, items, frames, gainsDb, intervalsFrames, constantGain, constantSpacing}]: three or more placements of one sound file with starts at most runGapSeconds apart. No limit is applied.

- Mode: read · Runs: immediately · MCP: `bashcut_review_sync`
- `events`: string. cuts, text, sfx, captions, impacts (comma separated; default cuts)
- `impactFrames`: integer, 1…120. Longest impact, frames (default 12)
- `runGapSeconds`: number. Largest gap in an sfx run, s (default 2)
- `bins`: boolean. Add p10/p90 and counts per offset
- `rendered`: boolean. Also measure the last export's timing against the timeline

### `bashcut review window <frame> [--span <span>] [--step <step>] [--width <width>]`

Look across a moment of the edit without exporting: one PNG with the composed frames from frame − span to frame + span (every step frames) labelled with their time, the cuts on Main drawn as lines, the timeline's sound level (−60…0 dBFS) and the words heard there. Returns {path, frames, cuts, words [{text, at, end}], levels [{frame, db}] (the mix per frame, null without sound)}.

- Mode: read · Runs: immediately · MCP: `bashcut_review_window`
- `frame`: integer, required, ≥ 0. Timeline frame in the middle
- `span`: integer, 1…120. Frames on each side (default 6)
- `step`: integer, 1…60. Frames between pictures (default 1)
- `width`: integer, 400…8192. Image width in pixels (default 1600)

### `bashcut review coverage`

Which described source shot each clip plays: per clip on the video layers in time order item, track, at/end, media, planShot when the clip has that field, and described {index, start, end and the media.describe facts} or null (no description covers it: media describe); counts. Join it with your plan yourself; media description lists the shots not played.

- Mode: read · Runs: immediately · MCP: `bashcut_review_coverage`

## platforms

### `bashcut platforms get [<id>] [--facts]`

Read the platform facts review uses: per platform (TikTok, Reels, Shorts, YouTube) shape, maxSeconds, targetLUFS, maxTruePeakDbTP and safeArea (zones the app covers, as fractions), with the project's review.platform overrides applied, whether it is one of the project's outputs and whether it was overridden; layout: the zones text is checked against (the strictest of the outputs of the frame's shape, null when none); targets: each output preset's loudness target (output.targets, else the platform's); data: the platform table's version and origin (built-in or the plugin that shipped a newer one). With facts, every field with {value, kind hard|recommended|info, source, checked, confidence}, including bitrateMbps, post text limits (title.maxChars, description.maxChars, caption.maxChars, hashtags.max, hashtags.ignoredAbove), cover facts, chapter and disclosure rules where known. With id, that one platform's row with its facts.

- Mode: read · Runs: immediately · MCP: `bashcut_platforms_get`
- `id`: string. tiktok, reels, shorts, youtube, or an export preset (youtube-1080 → youtube)
- `facts`: boolean. Include each field's provenance

## export

### `bashcut export status`

Read the export state: while one runs, its job, step, preset and path (last receipt under lastExport); after a failed export, state failed with its error and path (receipt under lastExport); otherwise the most recent receipt (clips on Main, cuts: the joins between them, transitions included). Includes the queue (job IDs for jobs.cancel) and delivered: each exported file of this session measured (stream starts and drift, fps and size against the preset, black and silent stretches), which review run reads (P1-E6).

- Mode: read · Runs: immediately · MCP: `bashcut_export_status`

### `bashcut export cover <frame> [--aspect <aspect>] [--size <size>] [--title <title>] [--preset <preset>] [--title-size <titleSize>]`

Write a still of the composed frame for each cover aspect into render/: the asked aspects (W:H, comma separated), else each output's cover aspect from platforms get (cover.aspect, else its shape), cropped from the centre. With title, the text is drawn on each cover in preset (a text preset or a library text-preset ID, bold-outline by default), at title-size of each cover's short side (default 0.12, about 7 % of a 9:16 cover's height; a starting point) and fitted to its width; each cover gives titleBox {x, y, width, height} as fractions from the top-left, to check against the platform's zones (platforms get), and its file ends in -title. Pick the frame from real frames (timeline sheet); look at the result.

- Mode: ui · Runs: immediately · MCP: `bashcut_export_cover`
- `frame`: integer, required, ≥ 0. Timeline frame
- `aspect`: string. Aspects such as 16:9,9:16
- `size`: integer, 160…3840. Long edge in pixels
- `title`: string. Title text drawn on each cover
- `preset`: string. Text preset of the title
- `titleSize`: number, 0.02…0.4. Title size as a fraction of the cover's short side (default 0.12)

### `bashcut export chapters [--platform <platform>] [--write]`

A chapter list from the section markers (00:00 first; an Intro at 0 when no marker is there) and each rule of the platform's chapter fact (first at 00:00, the least count, the shortest chapter) with whether it holds. With write, saves render/chapters-<platform>.txt. Caption mode per output is output.captions (preset → {mode burn|sidecar|both|none, format srt|vtt, track}); the export follows it.

- Mode: ui · Runs: immediately · MCP: `bashcut_export_chapters`
- `platform`: string. Platform whose rule applies (default youtube)
- `write`: boolean. Save the list in render/

### `bashcut export history [--limit <limit>] [--full]`

The project's export ledger, newest first: {index, id, rev, preset, path, seconds, completedAt, links [{url, platform, postedAt}], outcomes (imported or not), hook {firstCutSeconds, firstTextSeconds, firstText, firstMedia, cutsInHook, words}, sections (count)}. full adds each export's fingerprint (look, caption and title presets, music, transitions, clips, average and median cut, sections). Exports made before the ledger have no id, rev or fingerprint.

- Mode: read · Runs: immediately · MCP: `bashcut_export_history`
- `limit`: integer, 1…100, default 20. Exports to list
- `full`: boolean. Add the fingerprint of each export

### `bashcut export link --url <url> [--platform <platform>] [--posted-at <postedAt>] [--export <export>]`

Record where an export was posted: its URL, the platform and when it went live. The same URL again replaces its platform and date. Needs a saved project.

- Mode: edit · Runs: immediately · MCP: `bashcut_export_link`
- `url`: string, required. The post's URL
- `platform`: string. tiktok, youtube, reels… (platforms get lists them)
- `postedAt`: string. When it went live, ISO 8601 (2026-10-13 or 2026-10-13T18:00)
- `export`: string. The export: its ID (x-…), index or path from export history; the latest by default

### `bashcut export reveal-output [--export <export>]`

Reveal an exported file in Finder, like the result card's per-file icon: the export by ID, index or path from export history (the run's files are in run status result.outputs), the latest by default. Returns its path.

- Mode: ui · Runs: immediately · MCP: `bashcut_export_reveal-output`
- `export`: string. The export: its ID (x-…), index or path from export history; the latest by default

### `bashcut export start [--preset <preset>] [--presets <presets>] --name <name> [--output-dir <directory>] [--include-srt] [--normalize-audio] [--without <without>] [--no-steps] [--bitrate <bitrate>] [--overwrite] [--wait] [--save]`

Request a background video export; the user approves it in the app first. Approved exports queue behind a running one. Vertical presets default under the platform's recompression line (platforms list: bitrateMbps); bitrate overrides it. Feed shapes: feed-4x5 (1080×1350), square, portrait-3x4 (1080×1440). The export status reports the bitrate written. Started at once (no approval needed), the result has job: wait with jobs wait JOB --done, or pass wait to get the finished job (up to 100 s; save also saves the project once it lands). An agent's export with any preset but quick-draft needs a draft audit with verdict pass of the current timeline (run append audit --point draft) or the user's G5 approval at this revision: else audit_missing. Every stage the plan marks required before review must be done or skipped with a reason: else stage_pending. It also refuses graphics a plugin rendered as drafts (media data.graphics.draft): else graphics_draft, listing them and the plugin's final render (bin/graphic plan --final or rerender --all --final). When a ready plugin contributes an export step whose when holds (plugin API 12, e.g. HyperFrames finalising draft graphics), a final export runs it first unless no-steps: job is then the steps' job (exportSteps lists them; its result names the export jobs), the step applies its own change in one undo step, and the guards run again before exporting; a failed or cancelled step exports nothing. With presets, one approval queues an export per preset, each named name-<preset> (trip-tiktok, trip-shorts); the result lists them in exports (preset, output, job) and wait waits for the last. A name already on disk or queued gets the next free suffix (name-2…; the result says renamedFrom); overwrite replaces the files on disk (moved to the Trash) instead. without leaves audio layers of those roles out of this file (music: the same cut with voice and sound effects only, for a platform's own sound); its loudness and QC stay out of review.

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_export_start`
- `preset`: string, one of tiktok, reels, shorts, feed-4x5, square, portrait-3x4, youtube-1080, youtube-4k, quick-draft, prores. Export preset (one output; or give presets)
- `presets`: string. Several export presets, comma separated (tiktok,shorts): one job each
- `name`: string, required. Output base name without an extension
- `directory`: string. Output folder, relative to the project; defaults to its render folder
- `includeSRT`: boolean, default false. Also write a SubRip file
- `normalizeAudio`: boolean, default false. Run two-pass LUFS normalization with a plugin
- `without`: string. Audio roles to leave out (music, sfx, voiceover, dialogue)
- `noSteps`: boolean, default false. Do not run plugin export steps first (a final export over draft graphics is then refused)
- `bitrate`: number, 0.5…200. Video bit rate in Mbps instead of the preset's
- `overwrite`: boolean, default false. Replace an earlier export of this name instead of suffixing it
- `wait`: boolean, default false. When it starts at once, wait up to 100 s for it to finish and return the job
- `save`: boolean, default false. Save the project after a waited export lands

### `bashcut export otio --name <name> [--output-dir <directory>]`

Request an OpenTimelineIO export; the user approves it in the app first.

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_export_otio`
- `name`: string, required. Output base name without an extension
- `directory`: string. Output folder, relative to the project; defaults to its render folder

## plugins

### `bashcut plugins list [--category <category>] [--health] [--plugin <plugin>] [--views]`

List installed plugins with their category, providers and project provider preferences. With health, health {plugin, state, dependencies} from checks run now (Plugins sheet, Check Health); with views, views {panels (ready plugins with a rail panel or views (plugin API 8): title and icon, each view with where it lives and whether it is shown, tools, skills, required plugins, used capabilities), open panel, sheet, the host's plugin features, apiVersion}.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_list`
- `category`: string, one of agents, captions, voice, audio, color, effects, export, utilities. Only plugins in this category
- `health`: boolean. Run health checks
- `plugin`: string. With health: only this plugin
- `views`: boolean. Add plugin panels and views

### `bashcut plugins actions [<query>] [--plugin <plugin>]`

List actions plugins add to the editor (Plugins menu, toolbar, context menus, panels) with their parameters as JSON Schema, placements, whether each is available now and when it last ran. MCP lists at most 40 of them as their own tools; find any other action here and run it with plugins run.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_actions`
- `query`: string. Only actions whose ID, title or plugin contains this text
- `plugin`: string. Only actions of this plugin ID

### `bashcut plugins run <action> [--params <params>]`

Run a plugin action like clicking it, with parameters (CLI: --params '{"mode":"vivid"}'). The plugin's proposed operations are validated and applied as one undoable edit attributed to the plugin.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_plugins_run`
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

### `bashcut plugins bundles`

List the registry's plugin bundles (Plugins › Browse › Recommended): each plugin with whether it starts checked, whether this Mac can still install it or why not, and its download and setup size. Install one with plugins install --bundle.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_bundles`

### `bashcut plugins validate [<path>] [--url <url>] [--ref <ref>] [--sha256 <sha256>]`

Check a plugin that is not in the registry (a folder, its plugin.json, a .zip or .bashcutplugin archive, or a link) without installing or running it: its id, version and capabilities, every problem with the field and the fix (library packs included: each pack.json and the files it names, inside the plugin), and for a link the commit or release it resolved to.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_validate`
- `path`: string, path. Plugin folder, plugin.json, or .zip / .bashcutplugin file (or use url)
- `url`: string. Link to a .zip / .bashcutplugin file, a GitHub repo (or /tree/<ref>/<folder>, or its plugin.json) or a GitHub release; #sha256=<hex> pins it. A private link uses the access token saved in Add Plugin…
- `ref`: string. Tag, branch or commit for a GitHub repo link (release tag for a release link)
- `sha256`: string. Expected SHA-256 of the downloaded archive

### `bashcut plugins install [<plugin>] [--bundle <bundle>] [--only <only>] [--version <version>] [--path <path>] [--url <url>] [--ref <ref>] [--sha256 <sha256>] [--scope <scope>] [--link]`

Download a registry plugin (or its update), check its SHA-256 and manifest, and show the install approval in the Plugins sheet. With bundle instead, download every plugin of a bundle this Mac does not have and show one approval for all of them, each with a checkbox. With path or url instead, add a plugin that is not in the registry (Add Plugin…): a folder, its plugin.json or a .zip / .bashcutplugin file on this Mac, or a link, checked like plugins validate. With Trust plugins automatically on (the default) it installs at once (approval: approved); otherwise only the user can approve and the job ends when the approval is shown. While another install waits for approval or runs, a registry plugin or bundle is queued (approval: queued) and its approval opens after that one ends; do not ask again.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_plugins_install`
- `plugin`: string. Plugin ID from plugins search (or use path)
- `bundle`: string. Bundle ID from plugins bundles, such as starter
- `only`: string. With bundle: comma-separated plugin IDs to check in the approval; each plugin's default otherwise
- `version`: string. A specific registry version; the newest compatible by default
- `path`: string, path. Plugin folder, plugin.json, or .zip / .bashcutplugin file on this Mac
- `url`: string. Link to a .zip / .bashcutplugin file, a GitHub repo (or /tree/<ref>/<folder>, or its plugin.json) or a GitHub release; #sha256=<hex> pins it. A private link uses the access token saved in Add Plugin…
- `ref`: string. Tag, branch or commit for a GitHub repo link (release tag for a release link)
- `sha256`: string. Expected SHA-256 of the downloaded archive
- `scope`: string, one of user, project. Where a plugin from path or url goes: user (this Mac, every project; the default) or project (the open project)
- `link`: boolean. Link (developer mode): install a link to the plugin folder at path instead of a copy; use plugins reload after editing it

### `bashcut plugins replace <plugin> --path <path>`

Replace… an installed plugin with a new version from a folder, its plugin.json or a .zip / .bashcutplugin file, in the same scope. The new files must have the same plugin ID; only the user can approve, like plugins install.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_plugins_replace`
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

Run an installed plugin's dependency install recipes again (Install Dependencies…): at once with Trust plugins automatically on (approval: approved), otherwise after the user approves; follow it with jobs status.

- Mode: edit · Runs: immediately · MCP: `bashcut_plugins_setup`
- `plugin`: string, required. Plugin ID

### `bashcut plugins set <plugin> [--enabled <enabled>] [--hooks <hooks>]`

Turn a plugin or its hooks off (agents can only turn them off; turning on and trusting a plugin stays with the user in the Plugins sheet).

- Mode: edit · Runs: immediately · MCP: `bashcut_plugins_set`
- `plugin`: string, required. Plugin ID
- `enabled`: boolean. Plugin on or off
- `hooks`: boolean. Hooks on or off

### `bashcut plugins show-view <plugin> --view <view>`

Show a plugin view where it lives: its plugin's panel in the left rail, its tab in the agent dock, or a sheet. Plugins call this for their own views (an action opening a form sheet).

- Mode: ui · Runs: immediately · MCP: `bashcut_plugins_show-view`
- `plugin`: string, required. Plugin ID
- `view`: string, required. View ID from plugins list --views

### `bashcut plugins view <plugin> [--view <view>] [--open]`

Render a plugin view and return its components as JSON (what the app draws: text, lists, inputs with their current values, buttons by id). With open, also show the view where it lives (panel, dock tab or sheet).

- Mode: ui · Runs: immediately · MCP: `bashcut_plugins_view`
- `plugin`: string, required. Plugin ID
- `view`: string. View ID from plugins list --views; the plugin's first view by default
- `open`: boolean, default false. Show the view where it lives

### `bashcut plugins view-event <plugin> [--view <view>] --node <node> [--type <type>] [--value <value>]`

Do what a user does in a plugin view: click a button, change an input, submit a text field, select a list row or press a row button. Returns the view's new components.

- Mode: ui · Runs: immediately · MCP: `bashcut_plugins_view-event`
- `plugin`: string, required. Plugin ID
- `view`: string. View ID from plugins list --views; the plugin's first view by default
- `node`: string, required. Component id from plugins view
- `type`: string, one of click, change, submit, select, action, drag, default "click". What happened
- `value`: string. New value (change), row id (select) or {"item","action"} (action); JSON or text

### `bashcut plugins invoke <capability> [--provider <provider>] [--params <params>]`

Run a plugin capability directly with raw parameters. It returns the provider's raw result, for capabilities without their own command (prefer voice speak, captions generate, beats detect … when one exists). Files go to the returned outputDirectory. Plugins call this from their views and actions for capabilities listed in their manifest's uses.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_plugins_invoke`
- `capability`: string, required. Capability ID, such as voice.synthesize
- `provider`: string. Provider ID; the project's choice or the highest priority by default
- `params`: object. Request parameters (JSON object)

### `bashcut plugins overlays [<plugin>]`

List the overlays plugins draw on the timeline and viewer (ranges, markers and viewer regions with their frames, label and colour), by plugin.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_overlays`
- `plugin`: string. Only this plugin

### `bashcut plugins set-overlays <plugin> --overlays <overlays>`

Replace a plugin's overlays on the timeline and viewer (not saved with the project); an empty list clears them. Plugins call this for their own overlays: [{id, kind: range|marker|region, start, end, track, rect {x,y,width,height} 0–1, label, color, style}].

- Mode: ui · Runs: immediately · MCP: `bashcut_plugins_set-overlays`
- `plugin`: string, required. Plugin ID
- `overlays`: array, required. The overlay set (JSON array); [] clears

## captions

### `bashcut captions export [--as <as>]`

Export the captions (text on text layers, in time order) as: srt (default), SubRip text; json as {revision, fps, cues} with per cue index, item, track, trackRole, at/end/duration (frames), atSeconds, endSeconds, seconds, text, lines, chars (line breaks read as one space), cps, gapBefore (frames since the previous cue ended, negative when they overlap), captionMedia, wordStyle, wordTiming (transcribed or estimated from word length) and words [{text, at, end, atSeconds, endSeconds, source}]; text, one line per cue: #index start–end seconds cps | text (print it with --format text).

- Mode: read · Runs: immediately · MCP: `bashcut_captions_export`
- `as`: string, one of srt, json, text. srt (default), json or text

### `bashcut captions import <text-file> --base-rev <baseRev> [--replace]`

Import UTF-8 SubRip captions as one undoable edit.

- Mode: edit · Runs: immediately · MCP: `bashcut_captions_import`
- `text`: string, required. SubRip text (CLI: path to a .srt file)
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since
- `replace`: boolean, default false. Replace existing captions

### `bashcut captions words [<item>] --style <style> [--all] [--color <color>] --base-rev <baseRev>`

Show caption words as they are spoken (Inspector › Text › Word by word): highlight colours the word being said, karaoke colours the words already said, reveal makes words appear as they are said; none shows them all at once. Timings come from the transcription's word timings (captions generate) or are estimated from word length.

- Mode: edit · Runs: immediately · MCP: `bashcut_captions_words`
- `item`: string. Text item ID; the selection by default
- `style`: string, required, one of highlight, karaoke, reveal, none. Word style
- `all`: boolean, default false. Every caption on the caption layers
- `color`: string. Highlight colour, #RRGGBB (default #FFD400)
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut captions generate --media <media> [--replace] [--word-style <wordStyle>] [--from <from>] [--to <to>] [--provider <provider>] [--fresh] [--request-id <requestId>] [--dry-run]`

Place captions of project media as one undoable edit, from its stored transcript (media.transcribe) or by transcribing it with a captions.transcribe provider (the whole file is kept as its transcript). Captions follow the clips where the media is heard (trim, position, speed): place the clips first. The job's result says transcript: stored, transcribed or range (only from/to transcribed).

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_captions_generate`
- `media`: string, required. Project media ID
- `replace`: boolean, default false. Replace this media's captions
- `wordStyle`: string, one of highlight, karaoke, reveal, none. Show words as they are spoken (see captions.words)
- `from`: number, 0…86400. Transcribe only from this source second of the media (with replace, only this media's captions heard in the range are replaced)
- `to`: number, 0…86400. Transcribe only up to this source second of the media
- `provider`: string. Provider ID overriding the project preference for one request
- `fresh`: boolean. Transcribe again instead of using the media's stored transcript
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut captions find <text>`

Where words are said on the timeline: every place the text's words come in order (stored transcripts heard through the clips, else caption words), with at/end frames.

- Mode: read · Runs: immediately · MCP: `bashcut_captions_find`
- `text`: string, required. Words to find

### `bashcut captions replace <find> [--with <with>] [--match-case] [--whole-word <wholeWord>] [--dry-run] --base-rev <baseRev>`

Find and replace in captions. Every caption on the caption layers, as one undoable edit. Case is ignored unless matchCase; wholeWord (default true) skips matches inside a longer word. Word timings stay when the word count is unchanged, else they are estimated from word length (retimed). No match is not an error: replaced 0. Returns rev, replaced (matches), items [{id, before, after, count, retimed}]; dryRun returns the same without editing.

- Mode: edit · Runs: immediately · MCP: `bashcut_captions_replace`
- `find`: string, required. Text to find
- `with`: string. Replacement text; left out, the matches are removed
- `matchCase`: boolean, default false. Match upper and lower case exactly
- `wholeWord`: boolean, default true. Only whole words
- `dryRun`: boolean, default false. List the changes without editing
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut captions style [--preset <preset>] [<style.json>] [--word-style <wordStyle>] --base-rev <baseRev>`

Restyle every caption on the caption layers as one undoable edit: preset (a library text preset, as library apply: its preset, textStyle, brand roles and animation), then style (textStyle fields: font, size, fill, stroke, strokeWidth, positionY, align, highlight, uppercase…; null removes one) merged over each caption's, then wordStyle (highlight, karaoke, reveal or none). Give at least one. Returns rev and items.

- Mode: edit · Runs: immediately · MCP: `bashcut_captions_style`
- `preset`: string. Library text preset ID, or scope:id
- `style`: object. textStyle fields (CLI: path to style.json)
- `wordStyle`: string, one of highlight, karaoke, reveal, none. Show words as they are spoken (see captions.words)
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut captions group [<groups.json>] [--source <source>] [--max-chars <maxChars>] [--max-seconds <maxSeconds>] [--break-gap <breakGapSeconds>] [--break-at-cuts <breakAtCuts>] [--from <from>] [--to <to>] --base-rev <baseRev>`

Re-cut captions from word groups you choose, as one undoable edit: groups is a list of runs of word indices (from transcript words, or with source heard from transcript words --heard), each becoming one caption from its first word's start to its last word's end with its words timed; the captions those words fall in are replaced (their style and plan apply marks kept). Rule mode instead (maxChars, maxSeconds and breakGapSeconds, all required; from/to limit it) joins words greedily and, unless breakAtCuts is false, never across a cut between clips on Main. The cues remember how they were grouped, so a later plan apply that rebuilds the captions groups them the same way. Returns rev and facts: cues [{frames, seconds, chars, cps, text}], gaps and overlaps between cues in frames. No default grouping.

- Mode: edit · Runs: immediately · MCP: `bashcut_captions_group`
- `groups`: array. Runs of word indices (CLI: path to groups.json)
- `source`: string, one of captions, heard. captions (default) or heard
- `maxChars`: integer, 1…500. Rule mode: longest caption in characters
- `maxSeconds`: number, 0.1…60. Rule mode: longest caption in seconds
- `breakGapSeconds`: number, 0…10. Rule mode: a pause this long starts a caption
- `breakAtCuts`: boolean. Rule mode: start a caption at each cut between clips (default true)
- `from`: integer, ≥ 0. Rule mode: from this timeline frame
- `to`: integer, ≥ 0. Rule mode: up to this timeline frame
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut captions align --media <media> --text <text> [--replace] [--provider <provider>] [--aligner <aligner>] [--request-id <requestId>] [--dry-run]`

Make captions whose text is the script and whose times come from the speech: each non-empty line of text becomes a cue, timed by matching the script's words to the media's words (its stored transcript, or a new transcription), placed through the clips that play the media as one undoable edit. With replace, captions of that media in the aligned stretch are replaced. With aligner, a captions.align provider times the words instead of the transcript. Returns cues, score (matched words over the longer count) and unmatched words with their times. A job.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_captions_align`
- `media`: string, required. Media ID whose speech times the script
- `text`: string, required. The script, one cue per line
- `replace`: boolean. Replace that media's captions in the stretch
- `provider`: string. Provider ID overriding the project preference for one request
- `aligner`: string. A captions.align provider to time the words instead of the transcript
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

## transcript

### `bashcut transcript words [--from <from>] [--to <to>] [--media <media>] [--heard]`

Read every word on the caption layers in timeline order: index, text, at/end (frames), atSeconds, endSeconds, item and cue (captions export numbering), timing (transcribed or estimated from word length), gapBefore (frames since the previous word ended) and, for captions made from a media, source {media, clip, start, end} in that media's seconds through the clip heard there now (null when no clip of it plays there: captions do not move with their clips, except through a speed change). count is the words returned, total the words on the caption layers. With heard, the words come from the stored transcripts (media.transcribe) of the media the timeline plays instead: each word inside a clip that plays it, at that clip's frames (trim, speed), with item = the clip, timing source and the provider's confidence/speaker/event/noSpeechProb/avgLogprob/compressionRatio; transcribed and untranscribed list the media.

- Mode: read · Runs: immediately · MCP: `bashcut_transcript_words`
- `from`: integer, ≥ 0. Only words ending after this timeline frame
- `to`: integer, ≥ 0. Only words starting before this timeline frame
- `media`: string. Only captions made from (or with heard, words of) this media ID
- `heard`: boolean. Words of the source transcripts heard through the clips now

## layers

### `bashcut layers add --kind <kind> [--role <role>] [--name <name>] --base-rev <baseRev>`

Add an empty layer: text goes to the front of the picture stack, video and adjustment layers behind text, audio layers below the others.

- Mode: edit · Runs: immediately · MCP: `bashcut_layers_add`
- `kind`: string, required, one of video, adjustment, text, audio. Layer kind
- `role`: string. Role such as overlay, captions, music or sfx; never main
- `name`: string. Display name
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut layers set <track> [--hidden <hidden>] [--muted <muted>] [--locked <locked>] [--language <language>] --base-rev <baseRev>`

Change a layer's header switches like the timeline header: hide a visual layer, mute an audio layer, lock any layer (a locked layer refuses edits until unlocked); set a caption layer's language (P1-F4), which output.captions picks a layer by.

- Mode: edit · Runs: immediately · MCP: `bashcut_layers_set`
- `track`: string, required. Layer ID or label (V2, A1)
- `hidden`: boolean. Hidden (visual layers)
- `muted`: boolean. Muted (audio layers)
- `locked`: boolean. Locked
- `language`: string. Language tag such as vi or en; none clears it
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

## adjustment

### `bashcut adjustment add [--look <look>] [--exposure <exposure>] [--contrast <contrast>] [--saturation <saturation>] [--lut-strength <lutStrength>] [--lut <lut>] [--at-frame <atFrame>] [--duration <duration>] [--track <track>] --base-rev <baseRev>`

Add an adjustment item: a color grade applied to every layer below it for its frame range. Starts from a library look without a file, then the given grade values and LUT override it. Defaults to the selected clip's range, else 3 seconds at the playhead; goes on the first adjustment layer, adding one when needed.

- Mode: edit · Runs: immediately · MCP: `bashcut_adjustment_add`
- `look`: string, default "original". Library look: built-in (original, vivid, muted-film, black-white, bright-airy, moody) or scope:id from library list --kind look
- `exposure`: number, -10…10. Exposure in stops (0 = unchanged)
- `contrast`: number, 0…4. Contrast multiplier (1 = unchanged)
- `saturation`: number, 0…4. Saturation multiplier (0 = black and white, 1 = unchanged)
- `lutStrength`: number, 0…1. LUT mix (0 = off, 1 = full)
- `lut`: string. LUT ID from timeline get luts
- `atFrame`: integer, ≥ 0. First timeline frame
- `duration`: integer, ≥ 1. Length in timeline frames
- `track`: string. Adjustment layer ID
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

## schema

### `bashcut schema get`

Read the project.bashcut.json JSON Schema: every field, its type and range. Generated from the same declarations the app validates with.

- Mode: read · Runs: immediately · MCP: `bashcut_schema_get`

## clip

### `bashcut clip speed [<item>] [--items <items>] --speed <speed> [--keep-duration] [--preserve-pitch <preservePitch>] --base-rev <baseRev>`

Change a clip's constant speed like Inspector › Speed. By default the clip keeps its source and its length changes (2× halves it; rounded down to a whole frame, so the out edge never plays past the source it played), moving later clips on its layer; with keepDuration it keeps its length and uses more or less source. Linked picture and sound change together, and captions made from the clip's media follow the clips the change retimed or moved, word timings included. A clip is shortened to fit its source even with keepDuration; the result then has shortened: true. With items, every listed clip changes in one undo step, each by these rules (Inspector with several clips selected); items that have no speed are returned as skipped.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_speed`
- `item`: string. Item ID; the selected clip by default
- `items`: string. Several item IDs, comma separated
- `speed`: number, required, 0.1…16. Speed, for example 0.5, 1.5 or 2
- `keepDuration`: boolean, default false. Keep the clip's length instead
- `preservePitch`: boolean. Keep the voice pitch (on by default)
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut clip volume [<item>] [--items <items>] --db <db> --base-rev <baseRev>`

Set a clip's gain in dB (Inspector › Volume; op setProperties {volumeDb}). 0 leaves it as recorded, -6 halves it, positive is louder. Linked picture and sound change together. With items, every listed clip changes in one undo step; items without sound (text, images, graphics) are returned as skipped. Volume keyframes (clip keyframe --property volume) still win where they are set.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_volume`
- `item`: string. Item ID; the selected clip by default
- `items`: string. Several item IDs, comma separated
- `db`: number, required, -120…24. Gain in dB, for example -4 or 3
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut clip speed-curve [<item>] [--preset <preset>] [--points <points>] [--keep-duration] --base-rev <baseRev>`

Give a clip a speed ramp (CapCut Curve) like Inspector › Speed › Curve: a preset (montage, hero, bullet, jump-cut, flash-in, flash-out, or none to remove it) or points [[t, speed], …] with t from 0 (clip start) to 1 (clip end). The clip keeps its source and its length follows the average speed unless keepDuration (still shortened to fit its source, reported as shortened: true); linked sound and captions made from its media follow; one undo step.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_speed-curve`
- `item`: string. Item ID; the selected clip by default
- `preset`: string, one of montage, hero, bullet, jump-cut, flash-in, flash-out, none. Preset name, or none
- `points`: string. Custom points as JSON, e.g. [[0,1],[0.5,3],[1,1]]
- `keepDuration`: boolean, default false. Keep the clip's length instead
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut clip motion [<item>] [--preset <preset>] [--keyframes <keyframes>] [--focus <focus>] [--focus-to <focusTo>] [--within <within>] [--ease <ease>] --base-rev <baseRev>`

Animate a clip, image or text over its length (Inspector › Animation): a preset (zoom-in, zoom-out, pan-left, pan-right, pan-up, pan-down, fade-in-out, pop-in, slide-up, zoom-punch; none removes the animation) sized to the item, or keyframes JSON {property: [{frame, value, ease?}, …]} with frames from the item's start. Properties: zoom, pan, tilt (px, up), rotation (degrees), opacity, and volume (dB, like volumeDb; the only one on audio items, none on text); ease: linear, in, out, inOut, hold or cubic-bezier(x1,y1,x2,y2) (default inOut). Keys replace the item's static value for that property. Images with zoom-in, zoom-out or pan-* make a Ken Burns move; presets are for pictures and text. focus frames a rectangle of a video clip (a panel of a screen recording) without working out zoom, pan and tilt by hand, inside the band of the frame that stays visible: by default the part no opaque picture on a higher layer covers edge to edge (the bottom half under a camera across the top of a split layout), or within. The result gives within, the band used in canvas pixels.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_motion`
- `item`: string. Item ID; the selection by default
- `preset`: string, one of zoom-in, zoom-out, pan-left, pan-right, pan-up, pan-down, fade-in-out, pop-in, slide-up, zoom-punch, none. Preset name, or none
- `keyframes`: string. Keyframes as JSON, replacing the item's animation
- `focus`: string. Frame a rectangle of a video clip's picture: x,y,width,height in source pixels from the top left (media.list width/height); sets zoom, pan and tilt and keeps the other keys
- `focusTo`: string. With focus: move to this rectangle by the item's last frame
- `within`: string. With focus: where on the frame the rectangle lands: auto, full, bottom-half, left-half, right-half, top-half or x,y,width,height (shares 0–1 of the canvas, or canvas pixels); auto (default) is the band higher layers leave visible at the item's start (its end for focus-to), full the whole frame
- `ease`: string. With focus-to: the move's ease (linear, in, out, inOut, hold or cubic-bezier(x1,y1,x2,y2))
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut clip keyframe [<item>] [--property <property>] [--value <value>] [--at-frame <atFrame>] [--ease <ease>] [--remove] --base-rev <baseRev>`

Set one keyframe like the Inspector's controls with keyframes on: property at a timeline frame (the playhead by default) to value (its current value when omitted); remove deletes that key. Without property, keys every picture property at its current value (the Inspector's Keyframe at playhead); on an audio item, its volume. Volume (dB) works on audio items and clips with sound.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_keyframe`
- `item`: string. Item ID; the selection by default
- `property`: string, one of color.contrast, color.exposure, color.lutStrength, color.saturation, crop.bottom, crop.left, crop.radius, crop.right, crop.top, opacity, pan, rotation, textStyle.lineHeight, textStyle.positionX, textStyle.positionY, textStyle.size, textStyle.strokeWidth, textStyle.tracking, tilt, volume, zoom. Property; all of them by default
- `value`: number. Value
- `atFrame`: integer, ≥ 0. Timeline frame inside the item; the playhead by default
- `ease`: string. Change to the next key: linear, in, out, inOut, hold or cubic-bezier(x1,y1,x2,y2)
- `remove`: boolean, default false. Remove the key at that frame
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut clip reframe [<item>] [--mode <mode>] [--subject <subject>] [--min-confidence <minConfidence>] [--anchor <anchor>] [--zoom <zoom>] [--gate <gate>] [--min-subject-share <minSubjectShare>] [--fallback <fallback>] [--drift <drift>] [--min-hold <minHold>] [--smooth <smooth>] [--step <step>] [--measure] [--provider <provider>] --base-rev <baseRev>`

Crop a clip or image to its subject from media.subjects face boxes: the clip fills the frame and pans (and tilts) so the subject's centre sits at anchor. mode locked holds one framing (the subject's median place), cut jumps to a new framing (hold keys) when the subject moves more than drift of the frame and the last framing held minHold seconds, follow keys pan and tilt at every sampled picture, averaged over smooth seconds. Boxes stored for the source the clip plays are used; missing ones are measured first with a vision.faces provider (every step source seconds) and stored. When fewer than minSubjectShare of the clip's pictures have a subject, or the framing keeps less than gate of the subject in view on average, it fits the whole picture instead (fallback fit) or changes nothing (fallback refuse); never a blind centre crop. The defaults are starting points, not verdicts: set them from the skill's ranges. One undo step (fill, transform, zoom/pan/tilt keys; other keys stay). Returns rev, applied (reframe or fit), reason, coverage {samples, subjectSamples, subjectShare, mean, min} (share of the subject box in view), segments [{frame (from the item's start), pan, tilt}], measured (whether boxes were measured now) and preview {path, rows} (source next to the edit at each framing and the least covered picture). A job.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_clip_reframe`
- `item`: string. Video or image item ID; the selection by default
- `mode`: string, one of locked, cut, follow. locked (default), cut or follow
- `subject`: string, one of face, faces, person. face (the largest face, default), faces (all faces) or person
- `minConfidence`: number, 0…1. Ignore boxes below this confidence (default 0.5)
- `anchor`: string. Where the subject's centre sits: x,y as shares of the frame from the top left (default 0.5,0.5)
- `zoom`: number, 1…10. Scale over the filled size (default 1)
- `gate`: number, 0…1. Least mean share of the subject in view (default 0.9)
- `minSubjectShare`: number, 0…1. Least share of pictures with a subject (default 0.5)
- `fallback`: string, one of fit, refuse. Below the gate: fit (default) or refuse
- `drift`: number, 0…1. cut: share of the frame the subject may move before a new framing (default 0.15)
- `minHold`: number, 0…600. cut: shortest framing in seconds (default 1)
- `smooth`: number, 0…60. follow: seconds the path is averaged over (default 1)
- `step`: number, 0.04…60. Source seconds between pictures when measuring (default 0.5)
- `measure`: boolean. Measure the boxes again even when stored
- `provider`: string. Provider ID overriding the project preference for one request
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut clip backdrop [<item>] [--items <items>] --kind <kind> [--color <color>] [--blur <blur>] [--dim <dim>] --base-rev <baseRev>`

Fill a fitted picture's bars with a blur of itself or a colour (Inspector › Video › Backdrop). blur draws a blurred copy of the same frame scaled to fill, color a solid colour; none removes it. The backdrop moves, fades and grades with the clip. blur is the radius as a share of the frame's short side, dim darkens it (0–1). Several items in one undo step. Returns rev and items.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_backdrop`
- `item`: string. Video or image item ID; the selection by default
- `items`: string. Several item IDs, comma separated
- `kind`: string, required, one of blur, color, none. blur, color or none
- `color`: string. Colour #RRGGBB for kind color (default black)
- `blur`: number, 0…0.5. Blur radius, share of the short side (default 0.05)
- `dim`: number, 0…1. Darkening, 0–1 (default 0)
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut clip transition [<item>] [--items <items>] --side <side> --kind <kind> [--frames <frames>] [--easing <easing>] --base-rev <baseRev>`

Give a text, sticker, graphic or overlay item a transition kind as its own entrance or exit (Inspector › In and Out), played inside the item's frame: enter plays the kind's incoming side over its first frames, exit its outgoing side (a wipe or shape runs backwards) over its last; a whip or zoom fades the item on the way. A cut transition at the same edge of a clip wins. Kinds as on upsertTransition; none removes. Stored as the item's enter and exit fields. Returns rev and items.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_transition`
- `item`: string. Item ID; the selection by default
- `items`: string. Several item IDs, comma separated
- `side`: string, required, one of in, out, both. in, out or both
- `kind`: string, required, one of dissolve, blink, flash, dip-black, double-exposure, whip, whip-right, whip-up, whip-down, wipe, wipe-right, wipe-up, wipe-down, barn-door, shutter, slide, slide-up, iris, diamond, zoom, crash-zoom, crash-out, spin, roll, roll-right, swing, arc, arc-right, infinite-zoom, infinite-out, screen-in, screen-out, blur, seamless-zoom, glitch, halftone, flicker, color-shift, kaleidoscope, none. Transition kind, or none
- `frames`: integer, 1…100000. Length in frames; the item's own or half a second by default
- `easing`: string. linear, in, out, inOut or cubic-bezier(x1,y1,x2,y2)
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut clip reverse [<item>]`

Play a video clip backwards (with its linked sound): renders a reversed copy of the source it uses into the project's reversed/ folder and points the clip at it. Reversing again restores the original.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_clip_reverse`
- `item`: string. Item ID; the selected clip by default

### `bashcut clip freeze [<item>] [--at-frame <atFrame>] [--off] --base-rev <baseRev>`

Hold one frame of a video clip for its whole length, like the clip menu's Freeze Frame (ui action clip.freeze): the frame the clip shows at atFrame (the playhead by default), as one undo step; freezing a frozen clip picks again from its source; off removes the freeze. A frozen clip has no speed and cannot be reversed. Returns freezeFrame, the source frame held.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_freeze`
- `item`: string. Item ID; the selected clip by default
- `atFrame`: integer, ≥ 0. Timeline frame inside the clip; the playhead by default
- `off`: boolean, default false. Remove the freeze frame
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

## text

### `bashcut text line-style [<item>] --line <line> [--font <font>] [--scale <scale>] [--fill <fill>] [--stroke <stroke>] [--clear] --base-rev <baseRev>`

Give one text line its own font, size and colours (two fonts in one title; Inspector › Text › Lines). font is a PostScript name from fonts list (family and weight), scale (× the block's font size; the line is fitted to the frame on its own), fill and stroke (#RRGGBB). line counts from the top (0), negative from the bottom. Stored in textStyle.lines (one entry per line, null keeps the block's look); given fields merge into the line's, "none" removes one, clear drops the line's look. One undo step. Returns rev, item and lines.

- Mode: edit · Runs: immediately · MCP: `bashcut_text_line-style`
- `item`: string. Text item ID; the selection by default
- `line`: integer, required. Line from the top (0), negative from the bottom
- `font`: string. Font PostScript name, or none
- `scale`: number, 0.2…5. Size × the block's font size
- `fill`: string. Text colour #RRGGBB, or none
- `stroke`: string. Outline colour #RRGGBB, or none
- `clear`: boolean. Drop the line's own look
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

## jobs

### `bashcut jobs status [<job>]`

Read one job (plugin call or export), or all recent jobs when job is omitted. Each job has state, progress, step and usage {provider, wallSec, units, costUSD, costSource}: units and cost only as a provider reported them, never estimated.

- Mode: read · Runs: immediately · MCP: `bashcut_jobs_status`
- `job`: string. Job ID

### `bashcut jobs wait <job> [--timeout <timeout>] [--done]`

Wait until a job's state or step changes, or it finishes, up to timeout seconds; returns the job, changed and timedOut. With done, only when it finishes. A finished job returns at once. Use it instead of polling jobs status. Several job IDs (comma-separated) wait until all have finished: {jobs, finished, timedOut}.

- Mode: read · Runs: immediately · MCP: `bashcut_jobs_wait`
- `job`: string, required. Job ID, or several comma-separated
- `timeout`: integer, 1…86400, default 25. Seconds to wait at most; more than 110 waits 110 (waitedAtMost says so): call again
- `done`: boolean, default false. Return only when the job has finished (or timeout passed), not on a step change

### `bashcut jobs cancel <job>`

Cancel a queued or running job (plugin call or export).

- Mode: edit · Runs: immediately · MCP: `bashcut_jobs_cancel`
- `job`: string, required. Job ID

## capabilities

### `bashcut capabilities get [<capability>] [--kind <kind>] [--voices]`

Whether each plugin capability (or one) can serve now: available, else reason missing (no plugin provides it), not_configured (turned off, not approved, changed, outdated or missing a required plugin) or unhealthy (a dependency fails its health check). Lists each provider with plugin, priority, paid, state and detail, and the commands that call the capability. A command whose capability cannot serve fails with category capability_missing and the same reason. With voices, voices: the voices of every voice.synthesize provider (per provider plugin, name, availability, clones and cloneRange {minSeconds, maxSeconds}, and the voice its plugin is set to; per voice id, kind (preset, or clone: a saved voice from My voices, listed first under the providers that can speak with it), source (the provider ID, or my-voices), language, region, style, gender, supportsRate, speaksContentLanguage (when the project has a content language) and measuredRate (rates measured on its takes, per language: samples, p10, p50, p90)), and projectVoice (the saved clone the project speaks with, set by voice use); without a capability the result is then {capabilities, voices}.

- Mode: read · Runs: immediately · MCP: `bashcut_capabilities_get`
- `capability`: string. Capability ID, such as captions.transcribe; all by default
- `kind`: string, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice, clip, brand. Only providers serving this library item kind
- `voices`: boolean. Add the voices of the voice providers

## beats

### `bashcut beats detect --media <media> [--provider <provider>] [--request-id <requestId>] [--dry-run]`

Detect beats in audio media and set its beat grid as one undoable edit.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_beats_detect`
- `media`: string, required. Audio media ID already placed on the timeline
- `provider`: string. Provider ID overriding the project preference for one request
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut beats grid --media <media>`

Read the beat grid beats detect stored for a media file, in its own seconds: bpm, beatsSeconds and, when the provider gives them, grid {strengths (0–1 per beat), downbeats and beatsPerBar (the phase where the kick band hits hardest; phaseScores per phase), confidence (how much the tempo stands out, 0–1), fit {periodSeconds, phaseSeconds, rmsErrorMs of the beats from a straight grid}, alternates [{bpm half and double, relative strength}]}, and downbeatFrames on the timeline where the media plays.

- Mode: read · Runs: immediately · MCP: `bashcut_beats_grid`
- `media`: string, required. Project media ID

## audio

### `bashcut audio measure [--media <media>] [--curve] [--timeline] [--provider <provider>] [--request-id <requestId>] [--dry-run]`

Measure a media file's sound with an audio.loudness provider: integrated loudness (LUFS), true peak, loudness range (LU) and the energy share in the speech band (300-3000 Hz) and the presence band (1-4 kHz, where consonants carry words). With curve, loudness over time: curve {step 0.1 s, momentary (400 ms) and shortTerm (3 s) LUFS, peakDb per step}. With timeline (instead of media), the whole mix is rendered to a scratch file (no export) and measured with its curve and silences [{start, end, seconds}] where momentary loudness stays at or under −70 LUFS. The job's result holds the values.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_audio_measure`
- `media`: string. Project media ID
- `curve`: boolean. Add loudness over time
- `timeline`: boolean. Measure the timeline's mix instead of a media file
- `provider`: string. Provider ID overriding the project preference for one request
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut audio energy --media <media> [--provider <provider>] [--request-id <requestId>] [--dry-run]`

How a music file's energy moves, with an audio.energy provider: the curve every step seconds — levelDb, onset (density) and fullness (share of octave bands near the loudest) — and timeline [{item, at, fromSeconds, toSeconds}] where the file plays. Picking lifts and drops is yours. A job.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_audio_energy`
- `media`: string, required. Project media ID
- `provider`: string. Provider ID overriding the project preference for one request
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut audio mix-measure [--near <nearSeconds>] [--provider <provider>] [--request-id <requestId>] [--dry-run]`

Read the mix by role without exporting: one stem each for speech (dialogue and voiceover layers and the sound of video clips), music and sound effects is rendered (other sounds at −120 dB, so ducking stays as in the mix) and measured over time. Spoken blocks are those inside heard or caption words, else where the speech stem is over −70 LUFS. Returns voice, musicUnderSpeech (voice minus music, in LU) and musicInGaps as {median, p10, p90, blocks}; speechWindows with the same per window; effects per sound-effect item: loudness (loudest momentary LUFS), peakDb, the voice at the same moment (voiceDuring LUFS, voicePeakDb) with overVoiceDb and peakOverVoiceDb (the effect minus them; a short effect reads low on 400 ms loudness, so read its peak too), voiceP95 within nearSeconds with deltaDb, sharedWith (effects playing at once, measured together), onset and peak offsets in frames to the nearest cut, beat and word edge; musicBeds per Music layer: ducking false (a fixed bed), or duckDb, minGapSeconds, rises (gaps where it comes back up), shortRises (gaps under 2.5 s), movesPerMinute and pumping (over 4 moves a minute); and each stem's integrated loudness. No other verdicts. A job; no levels are changed. jobs status shows its progress and the stem and timeline second being rendered; a stem rendered without a curve, or silent although its layers hold sound, fails the job with the reason (musicUnderSpeech null otherwise comes with musicUnderSpeechReason).

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_audio_mix-measure`
- `nearSeconds`: number, 0.1…10. Width in seconds of the window on each side of every sound effect where the voice is read (default 1); not a timeline time: the whole timeline is always measured
- `provider`: string. Provider ID overriding the project preference for one request
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

## image

### `bashcut image cutout <source> [--crop] [--provider <provider>] [--request-id <requestId>] [--dry-run]`

Remove a picture's background with a vision.cutout provider (built in: Apple Vision): the subject (a mascot, a product, a person) on a transparent background as a PNG in the project's generated folder. source is an image file (relative to the project or absolute) or a library sticker ID. Returns path, projectPath, width, height, instances (subjects found) and coverage (share of the picture kept). Look at it, then library add --kind sticker --file it (or library update the sticker) to use it. A job.

- Mode: ui · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_image_cutout`
- `source`: string, required. Image file or library sticker ID
- `crop`: boolean, default false. Crop to the subject
- `provider`: string. Provider ID overriding the project preference for one request
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut image generate [<prompts.json>] [--prompt <prompt>] [--style <style>] [--references <references>] [--seed <seed>] [--no-lock] [--width <width>] [--height <height>] [--provider <provider>] [--request-id <requestId>] [--dry-run]`

Make pictures with an image.generate provider: every scene in one job (the batch form: a JSON file of [{id, prompt}] or of prompt texts), with the style lock (image style: style prompt, reference pictures, seed) sent each time and the project's frame size. Each picture is added to the media pool with generated: true and its prompt, so media place puts it on the timeline. Returns images [{id, media, path, projectPath, width, height}], failed [{id, message}] (only those scenes need another call), contactSheet (one PNG of every picture, labelled by id: look at it instead of each picture), the style used and the provider. A job.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_image_generate`
- `prompts`: array. Scenes [{id, prompt}] or prompt texts (CLI: path to a JSON file)
- `prompt`: string. One picture's prompt, instead of prompts
- `style`: string. Style prompt for this call instead of the style lock's
- `references`: string. Comma-separated reference pictures (paths or sticker library ids) for this call instead of the style lock's
- `seed`: integer, ≥ 0. Seed for this call instead of the style lock's
- `noLock`: boolean, default false. Ignore the style lock for this call
- `width`: integer, 64…8192. Picture width; the project's by default
- `height`: integer, 64…8192. Picture height; the project's by default
- `provider`: string. Provider ID overriding the project preference for one request
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut image generate-list`

The project's generated pictures (media with generated: true): per picture media, id, prompt, projectPath, provider and placed (timeline items using it); the style lock in use with where it comes from (project or brand); the disclosure label; and whether an image.generate provider is available (with what to install when not).

- Mode: read · Runs: immediately · MCP: `bashcut_image_generate-list`

### `bashcut image style [--style <style>] [--references <references>] [--seed <seed>] [--disclosure <disclosure>] [--clear]`

Read or set the project's style lock for image generate: style prompt, reference pictures (paths or sticker library ids), seed and the disclosure label shown over generated pictures. Given fields replace those fields; clear removes the project's lock (a brand kit's illustration then applies). With no field, returns the lock in use.

- Mode: edit · Runs: immediately · MCP: `bashcut_image_style`
- `style`: string. Style prompt
- `references`: string. Comma-separated reference pictures; empty clears them
- `seed`: integer, ≥ 0. Seed, for providers that take one
- `disclosure`: string. Label over generated pictures, such as the brand's
- `clear`: boolean, default false. Remove the project's lock

### `bashcut image disclose [--text <text>]`

Put the disclosure label over every generated picture on the timeline that lacks one: one text item (disclosure: true, small, top left) per run of generated pictures, on the titles layer, in one undo step. The label is text, else the style lock's or the brand's disclosure. Returns rev and the added items; move or restyle them like any text. Only when the user asks: by default nothing generated is labelled on the video (AI disclosure is the platform's upload toggle).

- Mode: edit · Runs: immediately · MCP: `bashcut_image_disclose`
- `text`: string. Label text for this call

## color

### `bashcut color measure [--items <items>] [--samples <samples>] [--graded] [--compare <compare>] [--by <by>]`

Measure colour per clip on frames spread over each clip (samples, default 3), on the scale the colour skill reads (0–100): black (luma p1), p5, mid (p50), p95, white (p99), mean, saturation (mean HSV) and saturationP95, tintShadows/Mids/Highlights [R−B, G−(R+B)/2] (bands split at luma 0.25 and 0.7; null with too few pixels), clippedShare and crushedShare; the median over the samples. By default the source frames (no reframe, no grade); graded measures the edit as composed; compare source measures the edit without colour and as graded and adds change {black, mid, white, saturation, tintMids, chromaRatio, blackLift, clippedGrowth, crushedGrowth, meanDeltaE (CIE76)}. by clip adds the median clip and each clip's difference from it. Clips on Main by default, or the given video item IDs. Facts only.

- Mode: read · Runs: immediately · MCP: `bashcut_color_measure`
- `items`: string. Video item IDs, comma separated; the clips on Main by default
- `samples`: integer, 1…24. Frames per clip (default 3)
- `graded`: boolean. Measure the edit as composed
- `compare`: string, one of source. source: the edit without colour against it as graded
- `by`: string, one of clip. clip: each clip's difference from the median clip

## workflow

### `bashcut workflow gates`

The user's workflow gates: G1 brief, G2 strategy, G3 roughCut (rough-cut sheet), G4 script (before speech is made), G5 draft (before export) and any gate a skill stopped at by name, each ask, notify or skip (skip unless the user changed it), and maxReviewRounds. Request each gate with checkpoint request; never decide one is approved yourself.

- Mode: read · Runs: immediately · MCP: `bashcut_workflow_gates`

### `bashcut workflow set-gates [--gate <gate>] [--mode <mode>] [--max-review-rounds <maxReviewRounds>]`

Change a gate or the review round limit. Agents may only make a gate ask more (skip → notify → ask); loosening a gate or changing the round limit is the user's (Settings → Agents → Workflow gates).

- Mode: ui · Runs: immediately · MCP: `bashcut_workflow_set-gates`
- `gate`: string. G1…G5, brief, strategy, roughCut, script, draft or a gate name
- `mode`: string, one of ask, notify, skip. Gate mode
- `maxReviewRounds`: integer, 1…10. Review round limit (user only)

## checkpoint

### `bashcut checkpoint request <gate> --summary <summary> [--attach <attach>]`

Stop at a gate: with ask, the user sees the summary and attachments in BashCut and answers approved, changes (with a note) or rejected; poll checkpoint status until it is not awaiting_user. With notify the user is told and the run goes on; with skip nothing is shown. The answer is bound to the current revision and written to the run log; only the user can answer. G2 needs a strategy audit (run append audit --point strategy) and, when plan.recipe is set, its skill read: else audit_missing or recipe_unread. G5 by an agent needs every stage the plan marks required before review done or skipped with a reason: else stage_pending (data.stages).

- Mode: ui · Runs: immediately · MCP: `bashcut_checkpoint_request`
- `gate`: string, required. G1…G5, brief, strategy, roughCut, script, draft, or any name (1–40 letters, digits, ., -, _) for a stop of your own
- `summary`: string, required. What the user is asked to approve
- `attach`: string. Comma-separated files to show (sheets, stills); relative to the project

### `bashcut checkpoint status [<id>] [--wait <wait>]`

A checkpoint of this session (default the last): status awaiting_user, approved, changes, rejected, skipped, notified or withdrawn, the user's note, the revision it covers and stale when the project has changed since. With wait, the call returns as soon as the user answers, or after that many seconds: wait instead of polling.

- Mode: read · Runs: immediately · MCP: `bashcut_checkpoint_status`
- `id`: string. Checkpoint ID
- `wait`: integer, 1…110. Seconds to wait for the user's answer

## run

### `bashcut run log [--run <run>] [--kind <kind>] [--limit <limit>]`

The run log (.bashcut/run-log.jsonl, append-only): starts, stages, gates with the user's answers, review rounds (fixed, left), what was measured and not measured, notes. Read it for the hand-off report and self-learn instead of the chat.

- Mode: read · Runs: immediately · MCP: `bashcut_run_log`
- `run`: string. current (default), all or a run number
- `kind`: string. Only this kind
- `limit`: integer, 1…10000. Last N entries

### `bashcut run append <kind> [--data <data>] [--stage <stage>] [--status <status>] [--evidence <evidence>] [--reason <reason>] [--name <name>] [--origin <origin>] [--verified-by <verifiedBy>] [--point <point>] [--verdict <verdict>] [--findings <findings>] [--by <by>] [--text <text>] [--progress <progress>] [--eta <eta>] [--round <round>] [--fixed <fixed>] [--left <left>] [--measured <measured>] [--not-measured <notMeasured>]`

Append to the run log: an entry of any kind (start opens a run; stage, skill, audit, round, measured, note and end are the usual ones; gate is reserved for checkpoints) with the fields given and any data object. The revision, author and time are added. stage: --status done needs --evidence (else it is stored unverified), skipped needs --reason; marking the rough-cut stage done while G2 is skip needs what G2 needs (progress reports are never gated); marking review done needs every stage the plan marks required before review done or skipped: else stage_pending. skill: a skill you read (stored verified: false unless the kit hook writes it with --verified-by hook; skills get records plugin and kit skill reads itself). audit: an auditor's verdict at a point (strategy after the story, draft before export, process at the end), bound to the current timeline. BashCut writes these stages itself (auto: true): rough-cut and captions on plan apply, review on a review run that passes while no required stage is open, export when an export lands. The run panel the user watches shows the latest stage entry as the current stage (status started, the default) with its text, progress and eta: one short call as each stage starts, such as run append stage --stage cut --text "Cutting 12 shots" --eta 120 (cut, color and audio mean rough-cut, colour and sound).

- Mode: ui · Runs: immediately · MCP: `bashcut_run_append`
- `kind`: string, required. Entry kind (1–40 characters; not gate)
- `data`: object. More fields as a JSON object
- `stage`: string. Stage ID (intake, survey, story, rough-cut, rhythm, voiceover, sound, captions, colour, effects, review, export, learn, or one the plan adds; cut and color work too)
- `status`: string, one of started, done, skipped. Stage status
- `evidence`: string. What proves the stage done, ;-separated (files, job IDs, issue IDs)
- `reason`: string. Why the stage was skipped
- `name`: string. Skill read (bc:rough-cut, bashcut.vlog:product-ad)
- `origin`: string, one of kit, plugin, project, user. Skill origin: kit, plugin, project or user (default from the name)
- `verifiedBy`: string, one of hook. Set only by the kit's skill hook
- `point`: string, one of strategy, draft, process. Audit point
- `verdict`: string, one of pass, changes, fail. Audit verdict
- `findings`: integer, 0…1000. Audit findings
- `by`: string, one of critic, self. Who audited: a fresh critic or the agent itself (default self)
- `text`: string. What happened; for a stage, the step the run panel shows
- `progress`: number, 0…1. Stage started: how far it is, 0–1
- `eta`: integer, 0…86400. Stage started: seconds it still needs, your estimate
- `round`: integer, 1…100. Review round
- `fixed`: integer, ≥ 0. Issues fixed this round
- `left`: integer, ≥ 0. Issues left
- `measured`: string. Comma-separated checks measured
- `notMeasured`: string. Comma-separated checks not measured

### `bashcut run status`

What the run panel shows: progress {run, startedAt, elapsed, current, text, progress, remaining (the ETA counted down), stageElapsed, finished, exportedAt, stages [{id, status pending|active|started|done|skipped, seconds, text}]} from the run log, and once the run exported result {path, duration, cuts, lufs, truePeakDbTP, loudnessVerified, review {errors, warnings, accepted} on the current timeline, outputs [{path, preset, duration, bytes, exists, completedAt}] newest first, recipe, thumbnail}; progress is null before the first stage entry of the run.

- Mode: read · Runs: immediately · MCP: `bashcut_run_status`

### `bashcut run checklist`

The run's checklist, derived from the plan and the run log (never hand-written): stages [{id, skill (the plan's stages.<id>.skill, else the kit's), skillRead (recorded by BashCut or the kit hook; skillReadUnverified when only you reported it), status pending|started|done|skipped|n/a, required, evidence, reason, unverified (done without evidence), by (n/a from the recipe or plan), rules}], audits {strategy, draft, process: verdict or null}, auditDetails {verdict, by critic|self, findings, rev, current}, recipe {skill, read} and open: what still needs attention; start the hand-off report from it.

- Mode: read · Runs: immediately · MCP: `bashcut_run_checklist`

## script

### `bashcut script check [--beats <beats>] [--text <text>]`

A script against the words heard on the timeline (stored transcripts, else caption words): per beat (the beats given, the text as one beat, else the plan's beats) the share of its words heard as written, the unmatched words, where it was heard and the section marker it starts in against the beat's section, and its onScreen note when the beat has one; overall similarity and extra heard words.

- Mode: read · Runs: immediately · MCP: `bashcut_script_check`
- `beats`: array. Beats [{id, text, section}] as JSON
- `text`: string. The whole script as one beat

## plan

### `bashcut plan check [<cut.json>] [--patch <patch>] [--words] [--save] [--base-rev <baseRev>]`

Check the edit list before building it, without changing anything: each clip's source range (quotes resolved in the stored transcript, edges inside a word or sentence, how much of the quote was heard), where it lands, its described shot and orientation; each title's chars per second and textShare (its smallest line as a share of the short side, the measure of review.minTextSize); problems {id, severity error|warning|info, entry, detail, facts} (quote not found, unknown media, source played twice, same media and size back to back, media against the canvas shape, entry-invalid for each entry it cannot read (all of them at once), transition-no-cut and transition-too-long, stroke-units, plate-units, unknown-field for a field nothing reads, unknown-fact for a facts key that is neither a project fact nor a claim, review-profile-unset with facts.unsetLimits: every review limit the built edit needs and nobody set); and the review of the edit as it would be (the project's review profile; picture and loudness need a render and are not measured). ok is false while an error stands. Voiceover lines report at, seconds, take and the take's similarity; graphics their at, seconds and track (also before they have media, so a graphics plugin renders each to its span; words adds the voiceover words heard during each, in seconds from its start). save keeps the list (cut, or patch merged by entry ID) as plan.cut without building it, as one undoable edit, when its only errors are ones a later stage resolves (graphic-no-media, no-take); else it refuses with the problems. The result is the check's with rev and saved. plan.cut is {clips: [{id, media, quote | words FIRST-LAST | from/to seconds (whole media when none; seconds for a still; from or to next to a quote or words moves that edge, and a patched quote drops the old edges), section, speed, volumeDb, role (speech, broll, underVO; speech by default for quote, words or seconds holding transcribed words), zoom, pan, tilt (its picture's framing: a punch-in such as zoom 1.15 breaks a jump cut between two clips of one camera), focus: [x, y, w, h] (a rectangle of its source in pixels, such as a panel of a screen recording: apply works out zoom, pan and tilt like clip motion --focus; not with zoom, pan, tilt or their keyframes), focusTo (moved to by its last frame), focusKeys: [{at (source seconds), rect [x, y, w, h], move (seconds, default 0.5)}] (one panel after another: each held until the next key, eased in over move), within (where the rectangle lands: auto, the band no opaque picture on a higher layer covers edge to edge such as the bottom half under a camera overlay; full; top-half, bottom-half, left-half, right-half; or [x, y, w, h] in canvas shares or pixels), ease (of the moves), backdrop, crop, keyframes, fill, color (item fields of its picture; null clears one set by hand), cover: [{media, from, seconds, zoom, pan, tilt, focus, focusTo, focusKeys, within, ease, backdrop, crop, keyframes, fill, color}] (pictures shown over the clip's sound, muted, the last filling the rest), overlays: [{media (default the clip's own), from (source seconds; default in sync with the clip for its own media), offset (seconds into the clip), seconds (default the rest of the clip), zoom, pan, tilt, focus, focusTo, focusKeys, within, ease, backdrop, crop, keyframes, fill, color}] (pictures over the clip on an overlay layer, muted, rebuilt and moved with it: a picture-in-picture), transition (the cut into it from the clip before)}], voiceover: [{id, text, caption (what captions show, such as digits), section, pause (seconds after it), at (seconds; else right after the line before), take (a kept take's path; else the best kept take of its text: voice lines makes them), volumeDb}] (on the Voiceover layer from 0; an edit may be lines without clips), graphics: [{id, media, on (a clip, line, title or earlier graphic) | section | at, offset, seconds | until (an entry: to its end), else to its anchor's end, track overlay|main (main: the picture of an edit made of graphics), from, render (a graphics plugin's inputs, not read), transition (the cut into it on its layer), enter, exit (its own In and Out)}] (full canvas), titles: [{id, text, clip (a clip or line) or section (+ offset seconds) | at, seconds (to the end of its clip or section when left out; needed with at), preset, style, enter, exit}], captions: {from: speech, wordStyle highlight|karaoke|reveal, preset, style, replace: {"misheard words": "right words"} (names the transcript got wrong; a line a clip plays only part of shows only the words heard), maxChars (voiceover lines break into cues of at most this many characters)} (captions from the stored transcripts of the clips' media, cut with them, and each voiceover line's own text timed by its take's words), music: {media, from, volumeDb (unset: plan apply sets one fixed level underVoiceDb under the measured voice), underVoiceDb (default 16), duck (default false: no ducking), duckDb (level under speech; turns ducking on), duckMinGapSeconds (default 2.5: shorter gaps between lines keep the music down)}, sfx: [{id, media, on (a clip, line, title or graphic ID) | section | at seconds, offset (negative: before it), seconds (default the whole file), volumeDb}] (on the SFX layer, never past the end), review: {limit: number} (review limits such as minTextSize, minTextContrast, minShotSeconds, chosen from the recipe's ranges; merged over the project's review on apply)}; any entry may give facts: [key] (the project facts or claims it rests on). A transition, enter or exit is "kind", "kind:frames" (such as "dissolve:12"), {kind, duration (frames), easing} or "none" (removes one set by hand); kinds as on upsertTransition; default length half a second. A title's preset is a renderer preset (bold-outline, cinematic-serif, keyword-sticker, place-card, hook-title, chapter-card) or a library text-preset ID (templates such as stacked-keyword, boxed-keyword, headline-subline, two-tone-pop; library list --kind text-preset); its style gives text style fields over the preset's: font (a PostScript name or System-[Condensed|Compressed]Bold|Heavy|Black; fonts list --covers), size (share of the short side), fill, stroke, strokeWidth (points, 0–50), positionX (0 left … 1 right), positionY (baseline height from the bottom: 0.1 low, 0.86 high), align, uppercase, lineHeight, tracking, background {color, opacity, padding, radius (× font size, not pixels: 0.2 rounds the corners)}, shadow {color, opacity, blur, dx, dy}; other keys are item properties. Over bright or busy footage give a stroke or a background. A font missing letters of the content language is an error.

- Mode: read · Runs: immediately · MCP: `bashcut_plan_check`
- `cut`: object. The list {clips, titles, music} (CLI: path to cut.json); plan.cut when omitted
- `patch`: object. Changes merged over the list instead of a whole new one: {clips: {c2: {cover: […]}, c5: null}, titles: {t1: {style: {…}}}}; an entry by ID merges, null removes, an unknown ID adds
- `words`: boolean. Per graphic, the voiceover words heard during it (seconds from its start)
- `save`: boolean. Save the list as plan.cut without building (needs baseRev)
- `baseRev`: integer, ≥ 0. With save: the current project revision, or "last"

### `bashcut plan apply [<cut.json>] [--patch <patch>] [--dry-run] [--sheet] [--full] [--why <why>] [--evidence <evidence>] --base-rev <baseRev>`

Build the edit list as one undoable edit: clips on Main in order (sound linked on the dialogue layer), voiceover lines, graphics, section markers, titles and the music bed, each tagged planCut. Applying again replaces only what an earlier apply built, and keeps what was changed on those items by hand since: a field changed by hand that the list did not change since stays, one the list changed too takes the list's value (volumeDb, muted, fades, crop, keyframes, backdrop, fill, color, a title's text, transform and textStyle key by key; the pieces a ripple cut, split or trim left of a clip while its row gives the same range; where a line, title, graphic or sound starts; the music bed's level and span; a clip's speed or curve unless the list gives speed; cut transitions and In/Out). handEdits lists each one kept and each one overwritten (item, entry, field, hand, list), also with dryRun: check it before applying, and move a value into plan.cut to make it the list's. A row's null picture field clears a hand edit. Other layers are kept but not re-timed: give a picture that must follow a clip as its overlays; Main must hold nothing else. Captions it built, regrouped with captions group too, stay as they are while the list would make the same ones (captionsKept: true); when it would not they are replaced, and the new ones grouped as captions group grouped the old (the same rule, or the same words together), without the words a built clip played with no caption over them (cues deleted by hand stay deleted); speech captions it did not build where its captions go are an error, never a second set. Refuses while plan.check has an error (plan check --save keeps a list not ready to build). With cut or patch, the list is also saved as plan.cut in the same edit (a revision: --patch with only what changes, then nothing else to write); plan.cut.review is merged into the project's review in the same edit. dryRun returns the check. The result has the review's errors and warnings of the built edit (no info rows; picture and loudness need review measure); sheet adds the storyboard image paths (timeline sheet --cuts --text) of the new revision. The result is brief (clips as a count; the per-clip facts are plan check's); full adds clips, changes, items and the sheet's cells. plan.cut is {clips: [{id, media, quote | words FIRST-LAST | from/to seconds (whole media when none; seconds for a still; from or to next to a quote or words moves that edge, and a patched quote drops the old edges), section, speed, volumeDb, role (speech, broll, underVO; speech by default for quote, words or seconds holding transcribed words), zoom, pan, tilt (its picture's framing: a punch-in such as zoom 1.15 breaks a jump cut between two clips of one camera), focus: [x, y, w, h] (a rectangle of its source in pixels, such as a panel of a screen recording: apply works out zoom, pan and tilt like clip motion --focus; not with zoom, pan, tilt or their keyframes), focusTo (moved to by its last frame), focusKeys: [{at (source seconds), rect [x, y, w, h], move (seconds, default 0.5)}] (one panel after another: each held until the next key, eased in over move), within (where the rectangle lands: auto, the band no opaque picture on a higher layer covers edge to edge such as the bottom half under a camera overlay; full; top-half, bottom-half, left-half, right-half; or [x, y, w, h] in canvas shares or pixels), ease (of the moves), backdrop, crop, keyframes, fill, color (item fields of its picture; null clears one set by hand), cover: [{media, from, seconds, zoom, pan, tilt, focus, focusTo, focusKeys, within, ease, backdrop, crop, keyframes, fill, color}] (pictures shown over the clip's sound, muted, the last filling the rest), overlays: [{media (default the clip's own), from (source seconds; default in sync with the clip for its own media), offset (seconds into the clip), seconds (default the rest of the clip), zoom, pan, tilt, focus, focusTo, focusKeys, within, ease, backdrop, crop, keyframes, fill, color}] (pictures over the clip on an overlay layer, muted, rebuilt and moved with it: a picture-in-picture), transition (the cut into it from the clip before)}], voiceover: [{id, text, caption (what captions show, such as digits), section, pause (seconds after it), at (seconds; else right after the line before), take (a kept take's path; else the best kept take of its text: voice lines makes them), volumeDb}] (on the Voiceover layer from 0; an edit may be lines without clips), graphics: [{id, media, on (a clip, line, title or earlier graphic) | section | at, offset, seconds | until (an entry: to its end), else to its anchor's end, track overlay|main (main: the picture of an edit made of graphics), from, render (a graphics plugin's inputs, not read), transition (the cut into it on its layer), enter, exit (its own In and Out)}] (full canvas), titles: [{id, text, clip (a clip or line) or section (+ offset seconds) | at, seconds (to the end of its clip or section when left out; needed with at), preset, style, enter, exit}], captions: {from: speech, wordStyle highlight|karaoke|reveal, preset, style, replace: {"misheard words": "right words"} (names the transcript got wrong; a line a clip plays only part of shows only the words heard), maxChars (voiceover lines break into cues of at most this many characters)} (captions from the stored transcripts of the clips' media, cut with them, and each voiceover line's own text timed by its take's words), music: {media, from, volumeDb (unset: plan apply sets one fixed level underVoiceDb under the measured voice), underVoiceDb (default 16), duck (default false: no ducking), duckDb (level under speech; turns ducking on), duckMinGapSeconds (default 2.5: shorter gaps between lines keep the music down)}, sfx: [{id, media, on (a clip, line, title or graphic ID) | section | at seconds, offset (negative: before it), seconds (default the whole file), volumeDb}] (on the SFX layer, never past the end), review: {limit: number} (review limits such as minTextSize, minTextContrast, minShotSeconds, chosen from the recipe's ranges; merged over the project's review on apply)}; any entry may give facts: [key] (the project facts or claims it rests on). A transition, enter or exit is "kind", "kind:frames" (such as "dissolve:12"), {kind, duration (frames), easing} or "none" (removes one set by hand); kinds as on upsertTransition; default length half a second. A title's preset is a renderer preset (bold-outline, cinematic-serif, keyword-sticker, place-card, hook-title, chapter-card) or a library text-preset ID (templates such as stacked-keyword, boxed-keyword, headline-subline, two-tone-pop; library list --kind text-preset); its style gives text style fields over the preset's: font (a PostScript name or System-[Condensed|Compressed]Bold|Heavy|Black; fonts list --covers), size (share of the short side), fill, stroke, strokeWidth (points, 0–50), positionX (0 left … 1 right), positionY (baseline height from the bottom: 0.1 low, 0.86 high), align, uppercase, lineHeight, tracking, background {color, opacity, padding, radius (× font size, not pixels: 0.2 rounds the corners)}, shadow {color, opacity, blur, dx, dy}; other keys are item properties. Over bright or busy footage give a stroke or a background. A font missing letters of the content language is an error.

- Mode: edit · Runs: immediately · MCP: `bashcut_plan_apply`
- `cut`: object. The list {clips, titles, music} (CLI: path to cut.json); plan.cut when omitted
- `patch`: object. Changes merged over the list instead of a whole new one: {clips: {c2: {cover: […]}, c5: null}, titles: {t1: {style: {…}}}}; an entry by ID merges, null removes, an unknown ID adds
- `dryRun`: boolean. Check without editing
- `sheet`: boolean. Also lay the new revision out on a contact sheet
- `full`: boolean. Return every clip's facts, the changes and the built items
- `why`: string. Why this edit, in one sentence (up to 500 characters)
- `evidence`: string. What it rests on, separated by ;
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

## selects

### `bashcut selects list [--status <status>]`

The project's selects: source ranges {id, media, from, to (seconds), status (free; usually candidate, kept or rejected), quote, reason (why it was picked), evidence, mustKeep, order, statusReason (why its status last changed)} and counts per status. The user sees and overrides them in the Media panel (Selects).

- Mode: read · Runs: immediately · MCP: `bashcut_selects_list`
- `status`: string. Only this status

### `bashcut selects set <value.json> --base-rev <baseRev>`

Add, update or remove selects (by id; a new one without id gets one, status candidate) as one undoable edit. Give the quote, the reason and the evidence (what was measured) with each; media resolve-range gives from/to. On an existing select, status or mustKeep with a reason keeps it as statusReason; {id, remove: true} removes it. A must-keep select no clip plays is a review warning.

- Mode: edit · Runs: immediately · MCP: `bashcut_selects_set`
- `value`: array, required. Selects (CLI: path to selects.json)
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut selects place [--ids <ids>] [--at-frame <atFrame>] --base-rev <baseRev>`

Lay the kept selects (or the given IDs) in order (order, else source start), from atFrame or the first one's layer end, as one undoable edit: pictures on Main, sound-only media on the dialogue layer (else music). An edge inside a transcribed word widens to the word's edge (listed in widened); returns the new item IDs.

- Mode: edit · Runs: immediately · MCP: `bashcut_selects_place`
- `ids`: string. Select IDs instead of the kept ones
- `atFrame`: integer, ≥ 0. Timeline frame
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

## variants

### `bashcut variants create <name> --changed <changed> [--dir <directory>]`

Write a full copy of the project next to it as a variant that records what it changes (one thing per variant), for example an ad with another hook. Open it to make the change; diff compares them.

- Mode: edit · Runs: immediately · MCP: `bashcut_variants_create`
- `name`: string, required. Short name (folder and title suffix)
- `changed`: string, required. What this variant changes
- `directory`: string, path. Parent folder

### `bashcut variants list [--dir <directory>]`

The variants and derived projects of this project in the sibling folders, with what each changes.

- Mode: read · Runs: immediately · MCP: `bashcut_variants_list`
- `directory`: string, path. Parent folder

### `bashcut variants diff <other> [--base <base>]`

What differs between two projects (default: this one against other): top-level fields, items added, removed or changed, durations and each one's recorded change.

- Mode: read · Runs: immediately · MCP: `bashcut_variants_diff`
- `other`: string, required, path. Project file or folder
- `base`: string, path. Project file or folder instead of the open one

## outcomes

### `bashcut outcomes import <data-file> [--export <export>] [--platform <platform>] [--totals <totals>] [--time-column <timeColumn>] [--retention-column <retentionColumn>]`

Import how an export performed: a retention curve and totals from the platform's analytics. JSON {curve: [{t (seconds) | position (% of the video), retention}], totals: {views, likes, shares, averageViewSeconds…}} or a list of points, or CSV with a header (a time or `Video position (%)` column and a retention column; name them when the headers are unclear). Values the file lacks stay null. Stored per export in .bashcut/outcomes; importing again replaces it. Needs an export from the ledger (made with this version or later).

- Mode: edit · Runs: immediately · MCP: `bashcut_outcomes_import`
- `data`: string, required. The file's text (CLI: path to a .csv or .json file)
- `export`: string. The export: its ID (x-…), index or path from export history; the latest by default
- `platform`: string. Where the numbers come from (tiktok, youtube…)
- `totals`: object. Totals to add or override ({"views": 1200})
- `timeColumn`: string. CSV: the time column's header
- `retentionColumn`: string. CSV: the retention column's header

### `bashcut outcomes map [--export <export>] [--top <top>] [--window <window>]`

Map an export's imported outcomes onto its sections (section markers when it was exported; the whole video without them): per section startRetention, endRetention, change (raw), drop {at, change, words}, lift {at, change}, replayPeak {at, retention} and viewsAtStart (views × start retention); then the largest drops of the whole curve {at, from, to, change, section, words}, with the caption words heard within window seconds. Retention is in the file's unit (percent or fraction). Missing values are null; no verdicts.

- Mode: read · Runs: immediately · MCP: `bashcut_outcomes_map`
- `export`: string. The export: its ID (x-…), index or path from export history; the latest by default
- `top`: integer, 0…20, default 3. Largest drops to list
- `window`: number, 0…30, default 4. Seconds of words on each side of a drop

## batch

### `bashcut batch run [<pipeline.json>] [--preset <preset>] [--inputs <inputs>] [--base <base>] [--save-current] [--discard-current]`

Run a pipeline over its inputs after the user approves the batch once in the app (that approval covers its exports). Returns the batch ID at once (state awaiting_approval or running); follow it with batch status --wait. A pipeline is JSON: {name, inputs (paths of media files, folders or projects; or {path, kind}), template {canvas, resolution, fps, language, brand, outputs (export presets)}, steps [{action, params, label}], onFailure skip|stop, concurrency, outputName ({name}-{preset} by default; {name}, {preset}, {index}, {pipeline}), projectsFolder}. Each file becomes a new project from the template (its folder linked as footage); a project input is that project. A step's action is a command that runs immediately or as a job (never one that needs approval, nor project open/create/close) or a plugin action; the export step (action export, params presets, includeSRT, normalizeAudio, bitrate, without) exports each preset (else the template outputs). String params may use {input}, {name}, {project} and {media} (the media the last step returned). Items run one at a time in the open editor, each project saved after its steps; the app must stay open (no headless runs).

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_batch_run`
- `pipeline`: object. The pipeline (CLI: path to pipeline.json)
- `preset`: string. A saved pipeline (batch presets) instead of pipeline
- `inputs`: string. Comma-separated input paths, replacing the pipeline's inputs
- `base`: string, path. Folder that relative input paths resolve against; the CLI sets it to the pipeline file's folder
- `saveCurrent`: boolean, default false. Save the open project first when it has unsaved changes
- `discardCurrent`: boolean, default false. Drop unsaved changes of the open project

### `bashcut batch retry [<batch>] [--items <items>] [--save-current] [--discard-current]`

Rerun a batch's failed or interrupted items from the step that did not complete. Default: the latest batch with failed, cancelled, skipped or interrupted items (a batch BashCut quit during comes back interrupted); each item goes on in the project it made, after the user approves once. Returns at once; follow it with batch status --wait.

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_batch_retry`
- `batch`: string. Batch ID
- `items`: string. Comma-separated item numbers (from 1) to retry; default all of them
- `saveCurrent`: boolean, default false. Save the open project first when it has unsaved changes
- `discardCurrent`: boolean, default false. Drop unsaved changes of the open project

### `bashcut batch status [<batch>] [--all] [--wait <wait>]`

Read a batch (default: the latest): state, concurrency {asked, used}, counts, elapsedSeconds, remainingSeconds (an estimate while it runs), retryable, and per item its input, kind, project, state, current step, outputs and steps (action, state, job, error, errorCategory, outputs, result). Without batch and with all, every kept batch in short form. With wait, holds until the batch or an item changes state or step, or it finishes (changed, timedOut).

- Mode: read · Runs: immediately · MCP: `bashcut_batch_status`
- `batch`: string. Batch ID
- `all`: boolean, default false. Every kept batch, short form
- `wait`: integer, 0…110. Seconds to wait for a change, at most 110

### `bashcut batch cancel [<batch>]`

Cancel a batch (default: the running one) and the job of its running step; items not run yet end cancelled, projects already made stay.

- Mode: edit · Runs: immediately · MCP: `bashcut_batch_cancel`
- `batch`: string. Batch ID

### `bashcut batch presets [<pipeline.json>] [--name <name>] [--keep-inputs] [--get <get>] [--remove <remove>] [--base <base>]`

Saved pipelines in the user store (Application Support/BashCut/Batch/Presets): list them; with pipeline save it (name from name, else the pipeline's; inputs are dropped unless keepInputs; a relative projectsFolder or input is saved absolute, resolved against base), with get return one, with remove delete one.

- Mode: edit · Runs: immediately · MCP: `bashcut_batch_presets`
- `pipeline`: object. Pipeline to save (CLI: path to pipeline.json)
- `name`: string. Preset name for save
- `keepInputs`: boolean, default false. Save the pipeline's inputs too
- `get`: string. Preset name to return
- `remove`: string. Preset name to delete
- `base`: string, path. Folder that relative paths (projectsFolder, kept inputs) resolve against before saving; the CLI sets it to the pipeline file's folder

## music

### `bashcut music replace [--media <media>] [--library <library>] [--from <from>] [--loop <loop>] --base-rev <baseRev>`

Swap the music bed for a new sound. The clips on the Music layers go and the new sound covers their span (first clip's start to last clip's end) on the first clip's layer, so its ducking stays, as one undoable edit, with the old level (volumeDb, muted) and fades. Shorter than the span, it repeats back to back unless loop is false. Give media (project media ID, such as {media} after a media import step) or library (a library audio item, copied into the project's music/ folder). Returns rev, track, removed, items, at, duration, looped and shortened.

- Mode: edit · Runs: immediately · MCP: `bashcut_music_replace`
- `media`: string. Project media ID of the new music
- `library`: string. Library audio item ID, or scope:id
- `from`: number, 0…86400. Start this many seconds into the new music
- `loop`: boolean, default true. Repeat the new music to cover the bed (default true)
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

## speech

### `bashcut speech rate [--media <media>] [--unit <unit>] [--voice <voice>]`

Measure speaking rate in the content language's unit (syllables for Vietnamese, characters for Chinese, Japanese and Korean, else words): per transcribed media (media.transcribe) and speaker, each phrase's rate over its own length as p10/p50/p90, overall (all units over all phrase time) and articulation (over the time words sound); and voices: the rates measured on synthesized takes (voice speak), per voice and language, with sample count and p10/p50/p90. No normal rate is assumed.

- Mode: read · Runs: immediately · MCP: `bashcut_speech_rate`
- `media`: string. Project media ID; every transcribed media by default
- `unit`: string, one of syllables, words, characters. Count in this unit instead
- `voice`: string. Only this voice (provider/voice)

## narration

### `bashcut narration windows --min-seconds <minSeconds> [--rate <rate>] [--levels]`

List stretches of at least minSeconds with no spoken word (heard or caption words) and no voiceover item: at/end frames and seconds, anchors {afterWord (the last word before it), firstCut, firstBeat, section, sectionStartsInside}, covered {music, footage} (shares 0–1 of the window), the shots on Main under it with their described facts, and with rate (units per second, in the content language's unit) a budget of units that fit. With levels, the mix is rendered once (no export) and each window gets its mixLoudness {median, p10, p90}. No length or rate is assumed.

- Mode: read · Runs: immediately · MCP: `bashcut_narration_windows`
- `minSeconds`: number, required, 0.1…600. Shortest window listed
- `rate`: number, 0.1…50. Units per second for the text budget
- `levels`: boolean. Render the mix to add each window's loudness

## voice

### `bashcut voice speak [<text>] [--takes <takes>] [--provider <provider>] [--voice <voice>] [--choose <choose>] [--at-frame <atFrame>] [--replace <replace>] [--clone-consent] [--request-id <requestId>] [--dry-run]`

Synthesize voice takes and measure them: per take index, path, projectPath, seconds, units (syllables, words or characters for the content language), unitsPerSecond over its sound, leadingSilence, trailingSilence, pauses and the provider's score when it gives one; the rates are kept per voice (speech rate). Every take file is kept: pick one yourself and put it on the timeline with voice place. With choose, take N goes on the Voiceover track at once (the rest are removed); with replace, the take (choose, default 1) goes into that item, keeping its place, and its captions are timed again. The item keeps voice {text, language, provider, voice}.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_voice_speak`
- `text`: string. Voiceover text in the project content language (with replace, the item's voice text by default)
- `takes`: integer, 1…8, default 3. Number of takes to generate; capped to the provider's maxTakes (requestedTakes in the answer when it gave fewer)
- `provider`: string. Provider ID overriding the project preference for one request
- `voice`: string. Voice for this request: a preset (voice or provider/voice) or a saved clone ID (clone-…, sent to a provider that clones with its saved consent); the project's voice by default
- `choose`: integer, 1…8. Put this take on the timeline (1 = first)
- `atFrame`: integer, ≥ 0. With choose: timeline frame; defaults to the playhead
- `replace`: string. Voiceover item to put the take into, keeping its place
- `cloneConsent`: boolean. The user agreed to clone the voice set in the plugin's options; providers that clone refuse without it
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut voice lines [<lines.json>] [--takes <takes>] [--min-similarity <minSimilarity>] [--retries <retries>] [--only <only>] [--force] [--provider <provider>] [--clone-consent] [--request-id <requestId>] [--dry-run]`

Voice every line of a script in one job: per line, takes are synthesized and kept (like voice speak), each is transcribed and diffed against its text, and with minSimilarity a line whose takes all fall below it is voiced again (retries). Lines default to plan.cut.voiceover; a line that already has a kept take at or above minSimilarity is not voiced again unless force. Nothing goes on the timeline: plan apply plays each line's best kept take (or the take its entry names), with captions timed by its words. Returns per line id, status (made, kept or failed), best {projectPath, similarity, seconds, unitsPerSecond}, takes (how many were made) and unmatched words of the best take when it is under 1.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_voice_lines`
- `lines`: array. Lines [{id, text}] (CLI: path to a JSON file); plan.cut.voiceover when omitted
- `takes`: integer, 1…8, default 2. Takes per line per try
- `minSimilarity`: number, 0…1. A take passes at this similarity; lines with none passing are voiced again
- `retries`: integer, 0…3, default 1. Extra tries for a line with no passing take
- `only`: string. Comma-separated line IDs to voice
- `force`: boolean, default false. Voice lines that already have a passing kept take
- `provider`: string. Provider ID overriding the project preference for one request
- `cloneConsent`: boolean. The user agreed to clone the voice set in the plugin's options; providers that clone refuse without it
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut voice place <take> [--at-frame <atFrame>] [--replace <replace>]`

Put a take voice speak kept on the Voiceover track with its voice facts and provenance: at a frame (the playhead by default), or into a voiceover item, keeping its place, with its captions timed again from the new take.

- Mode: edit · Runs: immediately · MCP: `bashcut_voice_place`
- `take`: string, required. The take's path or projectPath from voice speak
- `atFrame`: integer, ≥ 0. Timeline frame; defaults to the playhead
- `replace`: string. Voiceover item to put the take into

### `bashcut voice check [--item <item>] [--items <items>] [--media <media>] [--text <text>] [--min-similarity <minSimilarity>] [--provider <provider>] [--request-id <requestId>] [--dry-run]`

Check what a voiceover take says against the text it should say: the take (a voiceover item, or a media) is transcribed (or its stored transcript reused) and diffed word by word. Returns similarity (matched words over the longer word count), words [{text, heard, kind match|substituted|missing, start, end}], unmatched, extra (heard but not in the text) and, only with minSimilarity, passed. The text defaults to the item's voice.text. With items (or all), several voiceover items in one job: checks [{item, similarity, unmatched, passed}] without the word lists. A job.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_voice_check`
- `item`: string. Voiceover item ID
- `items`: string. Comma-separated voiceover item IDs, or all (every item with voice text)
- `media`: string. Media ID instead of an item
- `text`: string. The text the take should say
- `minSimilarity`: number, 0…1. Report passed against this similarity
- `provider`: string. Provider ID overriding the project preference for one request
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut voice fit --item <item> [--frames <frames>] [--to-frame <toFrame>] --min-ratio <minRatio> --max-ratio <maxRatio> --base-rev <baseRev>`

Change a voiceover item's speed (pitch kept) so it lasts frames, or ends at toFrame, as one undoable edit, when the needed speed is within minRatio…maxRatio; otherwise nothing changes and the error gives the speed it would need. Returns speed, frames and slackFrames. No default bounds.

- Mode: edit · Runs: immediately · MCP: `bashcut_voice_fit`
- `item`: string, required. Voiceover item ID
- `frames`: integer, ≥ 1. Length to fill, in timeline frames
- `toFrame`: integer, ≥ 1. Timeline frame to end at
- `minRatio`: number, required, 0.1…16. Slowest speed allowed (1 = as recorded)
- `maxRatio`: number, required, 0.1…16. Fastest speed allowed
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut voice clone-add --name <name> --from <from> [--at <at>] [--to <to>] --consent <consent> [--language <language>] [--provider <provider>]`

Save a cloned voice to My voices. From a media ID or a sound/video file (for every project), BashCut picks the best clean window within the cloning provider's reference range (most speech by Apple's on-device sound classifier, levels as the fallback; fewest pauses, no clipping or music), checks it and refuses with a reason (tooShort, tooQuiet, mostlySilence, notEnoughSpeech, clipped, musicUnder; data.checks says what was measured). A second speaker is not detected (notChecked). Saving asks the user first: the consent is theirs. Returns window {start, end, seconds} in source seconds, range, checks [{id, passed, value, detail}], providers (that can speak with it), approval and, once saved, clone (as voice clone-list shows it).

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_voice_clone-add`
- `name`: string, required. Name of the voice, such as Giọng Nolan
- `from`: string, required. Project media ID or file path (relative to the project folder)
- `at`: number, 0…86400. Start of the part to use, in source seconds
- `to`: number, 0…86400. End of the part to use, in source seconds
- `consent`: string, required, one of own, permission. The user's consent: own (their own voice) or permission (they have the speaker's permission)
- `language`: string. BCP 47 language the voice speaks; the content language by default
- `provider`: string. Cloning provider whose reference range to trim to

### `bashcut voice clone-list`

List My voices: per saved clone id, name, kind clone, source my-voices, language, providers (installed ones that can speak with it), savedFor, durationSeconds, sourceDescription, createdAt, consent {by, at, statement}, reference (the clip's path) and current (this project speaks with it).

- Mode: read · Runs: immediately · MCP: `bashcut_voice_clone-list`

### `bashcut voice clone-remove <voice>`

Remove a saved clone from My voices (every project) after the user approves; a project using it goes back to its plugin's voice.

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_voice_clone-remove`
- `voice`: string, required. Clone ID (clone-…)

### `bashcut voice use <voice>`

Choose the project's voice. Like the Voice panel picker, a saved clone ID sets the project's voiceClone; a preset (voice or provider/voice) sets its plugin's voice option and the voice provider and clears voiceClone; default clears voiceClone (the plugin's own voice). voice speak and voice lines then speak with it.

- Mode: edit · Runs: immediately · MCP: `bashcut_voice_use`
- `voice`: string, required. Clone ID, preset voice (provider/voice) or default

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

### `bashcut agent ask <questions.json> [--timeout <timeout>]`

Ask the user multiple-choice questions in a card over the caller's terminal tab, the way Claude Code's AskUserQuestion does (BashCut's Claude tabs route that tool here with `bashcut agent hook`). Returns once the user answers: answers maps each question to the chosen labels (comma-separated) or the text typed under Other; answered is false when the user chose to answer in the terminal, closed the tab or timeout passed.

- Mode: ui · Runs: immediately · MCP: `bashcut_agent_ask`
- `questions`: array, required. AskUserQuestion's questions: question, header, multiSelect and options of label, description and optional preview
- `timeout`: integer, 5…3600, default 900. Seconds to wait for the answer

### `bashcut agent quick-edit <kind> [--text <text>] [--items <items>]`

A quick edit on the selected clips (or --items) like the Quick Edit menu next to Send to Agent: the open agent (else the first chat agent) gets the request with those clips as its scope (lower music adds the music under them) and is asked to review only that range afterwards (review run --from --to). faster, remove, music-lower, caption and punch-in are worded by BashCut, with --text added; custom sends --text. Returns {kind, sentTo, items, range, request}; a chat agent still working is an error.

- Mode: edit · Runs: immediately · MCP: `bashcut_agent_quick-edit`
- `kind`: string, required, one of faster, remove, music-lower, caption, punch-in, custom. What to do
- `text`: string. The request for custom, or a note added to the others
- `items`: string. Item IDs, comma-separated (default the selection)

## app

### `bashcut app version`

This BashCut's version and build, how it was installed (homebrew, direct, app-store, development) and the plugin API it offers, like About BashCut.

- Mode: read · Runs: immediately · MCP: `bashcut_app_version`

### `bashcut app update-check`

Ask GitHub for the latest BashCut release, like BashCut › Check for Updates…. Returns this version, the latest release (version, page, notes) when it is newer, and how to update: the Homebrew command or the release page, and canUpdateNow when app update can install it. Never installs anything; App Store and TestFlight copies are not checked.

- Mode: read · Runs: immediately · MCP: `bashcut_app_update-check`

### `bashcut app update`

Update a Homebrew copy of BashCut to the release app update-check found, like Update Now in Software Update; the user approves it in the app first. Homebrew downloads the release while BashCut runs, then BashCut saves the project, quits, upgrades (brew upgrade --cask bashcut) and opens again. A failure keeps BashCut running: app update-check reports it as installError. Downloaded copies update from the release page.

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_app_update`

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

Answer the topmost dialog like the user: choose an option ID or title, or give a path to a file panel. A window is answered only with --dialog (sheet:batch add-step:captions.replace, load-preset:NAME, run; see ui dialog).

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_respond`
- `option`: string. Option ID or title
- `path`: string, path. File or folder for an open/save panel
- `dialog`: string. Only answer if this dialog ID is topmost

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

### `bashcut ui action <action> [<target>] [--in <in>] [--out <out>]`

Run an editor action like the user: by ID (timeline.split, timeline.zoom-in, playback.toggle) or by shortcut (cmd+b, space, cmd+=). Actions that open a dialog return at once; answer it with ui.respond. With a target: open DIALOG (a sheet or popover: new-project, export, export-report, agent-changes, review, history, plugins, settings, doctor, knowledge, ask, sections, external-changes, plugin-proposals, commands, shortcuts, add-plugin, library-search, library-generate, quick-edit, recents, voice-clone, assets, batch), panel PANEL (a library panel in the left rail: media, audio, text, stickers, effects, transitions, filters, brand, tools, captions, voice, beats), source MEDIA (the source viewer, with --in/--out frames marked) or notify MESSAGE (a short status message).

- Mode: edit · Runs: immediately · MCP: `bashcut_ui_action`
- `action`: string, required. Action ID or shortcut, or open, panel, source, notify
- `target`: string. The dialog, panel, media ID or message of open, panel, source, notify
- `in`: integer, ≥ 0. source: in frame
- `out`: integer, ≥ 1. source: out frame (exclusive)

### `bashcut ui view [--zoom <zoom>] [--zoom-anchor <zoomAnchor>] [--snap <snap>] [--safe-area <safeArea>] [--viewer-zoom <viewerZoom>] [--compare <compare>] [--agent-dock <agentDock>] [--right-tab <rightTab>] [--reveal <reveal>] [--inspector <inspector>] [--chat-draft <chatDraft>] [--settings-section <settingsSection>] [--settings-search <settingsSearch>] [--knowledge-section <knowledgeSection>] [--plugins-tab <pluginsTab>] [--plugins-category <pluginsCategory>] [--media-source <mediaSource>] [--library-query <libraryQuery>] [--library-pack <libraryPack>] [--library-tag <libraryTag>] [--library-scope <libraryScope>] [--library-source <librarySource>] [--library-collection <libraryCollection>] [--library-width <libraryWidth>] [--library-wide <libraryWide>] [--library-layout <libraryLayout>] [--library-tile-size <libraryTileSize>]`

Read the editor view state, or change it: timeline zoom (pixels per second), viewer zoom, snapping, safe area, color compare, agent dock and chat message, side panes, inspector tab, Settings section and search, Knowledge section, Plugins tab and Browse category, the Media panel's source (footage, project, shared, selects, clips), the open library panel's search and filters, and scroll the timeline to a frame; fullScreen: the preview of viewer.fullscreen is on.

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_view`
- `zoom`: integer, 1…600. Timeline zoom in pixels per second
- `zoomAnchor`: integer, ≥ 0. Frame kept in place by --zoom; the playhead by default
- `snap`: boolean. Snapping on or off
- `safeArea`: boolean. Safe-area overlay on or off
- `viewerZoom`: string, one of fit, 25, 50, 100, 200. Viewer zoom: fit, or a percentage of the output size
- `compare`: boolean. Color before/after compare on or off
- `agentDock`: boolean. Agent column shown or hidden
- `rightTab`: string, one of inspector, agent. Side pane to show; the other stays
- `reveal`: integer, ≥ 0. Scroll the timeline so this frame is visible
- `inspector`: string, one of video, audio, text, color, speed. Inspector tab
- `chatDraft`: string. Text in the shown chat agent's message box, as if typed
- `settingsSection`: string, one of general, agents, plugins, storage. Settings section (open Settings with ui.action open settings)
- `settingsSearch`: string. Settings search text: lists matching settings of every section; empty clears it
- `knowledgeSection`: string, one of inbox, lessons, prefs, facts, notes, skills, history. Knowledge window section (open it with ui.action open knowledge)
- `pluginsTab`: string, one of installed, browse, updates, activity. Plugins sheet tab (open it with ui.action open plugins)
- `pluginsCategory`: string, one of all, agents, captions, voice, audio, color, effects, export, utilities. Category Plugins › Browse shows; all shows every one
- `mediaSource`: string, one of footage, project, shared, selects, clips. What the Media panel lists
- `libraryQuery`: string. Search text of the open library panel; empty clears it
- `libraryPack`: string. Pack the open library panel shows; empty shows all
- `libraryTag`: string. Tag the open library panel shows; empty shows all
- `libraryScope`: string, one of all, built-in, user, project, plugin. Scope the open library panel shows
- `librarySource`: string, one of all, mine, packs. Source chip of the open library panel: mine (this project and this Mac), packs (built in and plugin) or all
- `libraryCollection`: string, one of all, recent, favorites. List the open library panel shows instead of its home view: recent (this project), favorites (this Mac) or all
- `libraryWidth`: number, 300…520. Width of the library panel in points
- `libraryWide`: boolean. The wide library panel (760 pt over the viewer, with a category sidebar) on or off
- `libraryLayout`: string, one of grid, list. Grid or list for the open library panel (remembered per panel)
- `libraryTileSize`: number, 0…1. Tile size of the open library panel, 0 (small) to 1 (large)

### `bashcut ui seek <frame>`

Move the viewer to a timeline frame.

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_seek`
- `frame`: integer, required, ≥ 0. Timeline frame

### `bashcut ui frame [<frame>] [--width <width>] [--phone] [--out <out>]`

Render the viewer's picture at a timeline frame (the playhead by default) to a PNG, like attaching the viewer frame in Ask; returns its path. Read the file to look at the edit. Keeps the ten newest. width renders it that many pixels wide (phone: 390, about a phone screen, to judge text at the size viewers see it); otherwise up to 1280 on the long edge. out also copies the PNG to that file (replacing it).

- Mode: read · Runs: immediately · MCP: `bashcut_ui_frame`
- `frame`: integer, ≥ 0. Timeline frame; the playhead by default
- `width`: integer, 64…4096. Width in pixels
- `phone`: boolean. 390 pixels wide
- `out`: string, path. Also write the PNG to this file

### `bashcut ui frames --compare <compare> [--frames <frames>] [--items <items>] [--width <width>]`

Compare pictures in one PNG grid, one row per frame: compare graded puts the frame without colour (looks, adjustments, LUTs bypassed) next to the edit as graded; compare source puts the source frame of the clip on Main at that point (no reframe, no grade) next to the edit. Rows from frames (timeline frames) or items (the middle of each item). Each cell is width pixels wide (default 390). Returns {path, rows [{frame, item?, sourceSeconds?}], columns}.

- Mode: read · Runs: immediately · MCP: `bashcut_ui_frames`
- `compare`: string, required, one of graded, source. graded or source
- `frames`: string. Timeline frames, comma separated
- `items`: string. Item IDs, comma separated
- `width`: integer, 64…2048. Cell width in pixels (default 390)

## luts

### `bashcut luts import <path> [--name <name>] --base-rev <baseRev>`

Check a .cube LUT, copy it into the project's luts folder and add it (Filters panel).

- Mode: edit · Runs: immediately · MCP: `bashcut_luts_import`
- `path`: string, required, path. .cube file
- `name`: string. Display name; defaults to the file name
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

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

List lessons the agent learned (symptom, cause, fix), from this project and for every project, newest first. Each has occurrences (times seen), lastSeen and sources (projects it was seen in) when counted. Read the active ones before editing; proposed ones wait for the user's review.

- Mode: read · Runs: immediately · MCP: `bashcut_knowledge_lessons`
- `scope`: string, one of project, user. Only this scope; both by default
- `status`: string, one of proposed, active, disabled. Only this status
- `tag`: string. Only lessons with this tag
- `query`: string. Text to find in the title, symptom, cause, fix, evidence or tags
- `sort`: string, one of newest, oldest, default "newest". Order by last change; newest first by default

### `bashcut knowledge add-lesson <title> [--symptom <symptom>] [--cause <cause>] [--fix <fix>] [--evidence <evidence>] [--check <check>] [--tags <tags>] [--scope <scope>] [--status <status>] [--session <session>]`

Record a lesson: in this project (default) or, with scope user, for every project. Use status proposed when unsure. Agents' lessons for every project are always proposed until the user approves them.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_add-lesson`
- `title`: string, required. Short title
- `symptom`: string. What went wrong or what was noticed
- `cause`: string. Why it happened
- `fix`: string. What to do next time
- `evidence`: string. What shows it (frames, files, the user's words quoted)
- `check`: string. Question to ask before the next draft (empty clears)
- `tags`: string. Comma-separated tags (captions, audio, pacing…)
- `scope`: string, one of project, user, default "project". project (default) or user
- `status`: string, one of active, proposed, default "active". active (default) or proposed
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge update-lesson <id> [--title <title>] [--symptom <symptom>] [--cause <cause>] [--fix <fix>] [--evidence <evidence>] [--check <check>] [--tags <tags>] [--status <status>] [--seen] [--session <session>]`

Change a lesson's fields or status, or count a sighting (seen). Status is proposed, active or disabled; seen adds 1 to occurrences, sets lastSeen and adds this project to sources. Agents changing a lesson for every project need approval; seen alone does not.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_update-lesson`
- `id`: string, required. Lesson ID (l-…) from knowledge lessons
- `title`: string. Short title
- `symptom`: string. What went wrong or what was noticed
- `cause`: string. Why it happened
- `fix`: string. What to do next time
- `evidence`: string. What shows it (frames, files, the user's words quoted)
- `check`: string. Question to ask before the next draft (empty clears)
- `tags`: string. Comma-separated tags (captions, audio, pacing…)
- `status`: string, one of proposed, active, disabled. New status
- `seen`: boolean. The problem happened again: count it
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge remove-lesson <id> [--session <session>]`

Remove a lesson (history keeps it). Agents removing a lesson for every project need approval.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_remove-lesson`
- `id`: string, required. Lesson ID (l-…) from knowledge lessons
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge prefs [<key>] [--scope <scope>]`

Read the user's preferences (taste: length, pace, voice, caption style, music…). Each has confirmedBy (user: said or approved by the user; inferred: an agent's guess). A project value wins over the one for every project.

- Mode: read · Runs: immediately · MCP: `bashcut_knowledge_prefs`
- `key`: string. Only this key
- `scope`: string, one of project, user. Only this scope; both by default

### `bashcut knowledge set-pref <key> [<value>] [--remove] [--scope <scope>] [--confirmed-by <confirmedBy>] [--session <session>]`

Set or remove a preference: for every project (default) or only this project. An agent's change for every project waits in the Knowledge inbox (approval proposed) unless the user lets agents act without confirmation. creator.* keys are the creator's profile (name, handle, channel, platforms, language, niche, audience, tone, cta, voiceSamples as media IDs, disclosure; lists comma-separated), shown as one object in context get; an agent's creator.* change for every project always waits for approval.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_set-pref`
- `key`: string, required. Key
- `value`: string. Value; required unless remove is set
- `remove`: boolean. Remove the key instead of setting it
- `scope`: string, one of project, user, default "user". user (default) or project
- `confirmedBy`: string, one of user, inferred. user when the user said it, inferred when you guessed it (default for agents)
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge facts [<key>]`

Read this project's facts (people, places, footage notes, what was approved). Each has evidence {source, measure, n, status measured|estimated|user} when given.

- Mode: read · Runs: immediately · MCP: `bashcut_knowledge_facts`
- `key`: string. Only this key

### `bashcut knowledge set-fact <key> [<value>] [--remove] [--source <source>] [--measure <measure>] [--n <n>] [--status <status>] [--session <session>]`

Set or remove a fact about this project. Give where it comes from: source (URL, file, frame, the user), measure (the command or result path that gave it), n (sample size) and status. Plans and skills refer to a fact by its key. Needs a saved project.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_set-fact`
- `key`: string, required. Key
- `value`: string. Value; required unless remove is set
- `remove`: boolean. Remove the key instead of setting it
- `source`: string. Where it comes from: a URL, a file, a frame, user
- `measure`: string. The measurement that gave it (review.measure pace.median, media analyze C0042)
- `n`: integer, 0…100000000. Sample size behind it
- `status`: string, one of measured, estimated, user. measured, estimated or user (said by the user)
- `session`: string. Your agent session ID, recorded as the source

### `bashcut knowledge claims`

Read this project's claims ledger: {key, text, source, author} for each number, price, superlative or name the video states. Review lists those in titles and the voiceover that no claim's text covers (unsourced-claim, info).

- Mode: read · Runs: immediately · MCP: `bashcut_knowledge_claims`

### `bashcut knowledge set-claim <key> [--text <text>] [--source <source>] [--remove] [--session <session>]`

Record a claim the video makes and its source, or remove it: text as the video states it ("528 ha", "rẻ nhất", "Phở Thìn"), source a URL, a frame (MEDIA@SECONDS), a file or user. Needs a saved project.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_set-claim`
- `key`: string, required. Key
- `text`: string. The claim as stated; required unless remove is set
- `source`: string. URL, MEDIA@SECONDS, a file, or user; required unless remove is set
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

### `bashcut knowledge verdicts [--verdict <verdict>] [--subject <subject>] [--limit <limit>]`

What the user did with agents' changes in this project, as BashCut saw it: keep (dismissed the change notice, or the next edit left the agent's items alone), undo, edit (the next edit changed the same items) and reject (the scope guard's Reject). Returns total, counts {subject: {verdict: n}} by the command that made the change (timeline.apply, library.apply, library.place, plan.apply…; edit when unknown) and the newest rows {verdict, signal, subject, label, agent, rev, items, date}. Facts only: no reasons.

- Mode: read · Runs: immediately · MCP: `bashcut_knowledge_verdicts`
- `verdict`: string, one of keep, undo, reject, edit. Only this verdict
- `subject`: string. Only changes made by this command
- `limit`: integer, 0…500, default 20. Rows to return (counts cover all)

### `bashcut knowledge revert <id> [--session <session>]`

Put an entry back to how it was before a change from knowledge history: a removed entry comes back, an added one goes, an edit is undone (later changes to the same entry too). History records the revert. Agents reverting a change for every project need approval.

- Mode: edit · Runs: immediately · MCP: `bashcut_knowledge_revert`
- `id`: string, required. Change ID from knowledge history
- `session`: string. Your agent session ID, recorded as the source

## skills

### `bashcut skills list [--scope <scope>]`

List the skills agents can read. Scopes: this project's, the ones for every project (user), the ones trusted and enabled plugins ship (plugin, read-only, named <plugin-id>:<name>) and the agent kit's (read-only), with whether agents get them (enabled), their description and path.

- Mode: read · Runs: immediately · MCP: `bashcut_skills_list`
- `scope`: string, one of project, user, plugin, kit. Only this scope

### `bashcut skills get <name> [--scope <scope>] [--section <section>]`

Read a skill's SKILL.md. Without scope, the project's skill wins over the one for every project, then a plugin's (<plugin-id>:<name>, its agent name such as vlog-product-ad, or a bare name one plugin has), then the kit's. To change a plugin's skill, save a copy with skills save. sections lists its ## headings; section returns only the sections whose heading contains one of the given words (comma-separated), and still counts as reading the skill.

- Mode: read · Runs: immediately · MCP: `bashcut_skills_get`
- `name`: string, required. Skill name; a plugin's is <plugin-id>:<name>
- `scope`: string, one of project, user, plugin, kit. Where to look
- `section`: string. Only these sections: words of their headings, comma-separated

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

### `bashcut skills export --output <output> [--skills <skills>] [--scope <scope>] [--as-plugin] [--id <id>] [--name <name>] [--version <version>] [--author <author>]`

Copy saved skills (for every project by default, or this project's) into a new or empty folder. With asPlugin, the folder is a skill pack plugin (plugin.json with contributes.skills and no entrypoint) that installs in another BashCut with plugins install --path, where its skills show in skills list.

- Mode: edit · Runs: immediately · MCP: `bashcut_skills_export`
- `output`: string, required, path. New or empty folder to write
- `skills`: array. Skill names; every skill of the scope by default
- `scope`: string, one of project, user, default "user". user (default: skills for every project) or project
- `asPlugin`: boolean, default false. Write a skill pack plugin around the skills
- `id`: string. With asPlugin: the plugin id, reverse-domain (me.my-skills)
- `name`: string. With asPlugin: the plugin name; the id by default
- `version`: string, default "0.1.0". With asPlugin: semantic version
- `author`: string. With asPlugin: who wrote the skills (manifest author.name)

### `bashcut skills propose <name> <text-file> --summary <summary> [--reason <reason>] [--session <session>]`

Propose a change to an agent kit skill: the line diff against the kit's SKILL.md waits in the Knowledge inbox as a lesson for every project tagged kit. The kit itself is not changed.

- Mode: edit · Runs: immediately · MCP: `bashcut_skills_propose`
- `name`: string, required. Skill name (lowercase, hyphenated)
- `text`: string, required. SKILL.md text (CLI: path to a text file)
- `summary`: string, required. What the change does, in a few words
- `reason`: string. What happened that shows the kit is wrong or missing a step
- `session`: string. Your agent session ID, recorded as the source

## library

### `bashcut library list [--kind <kind>] [--panel <panel>] [--offset <offset>] [--limit <limit>] [--tag <tag>] [--scope <scope>] [--created-by <createdBy>] [--pack <pack>] [--query <query>] [--favorites] [--recent]`

List library items. Kinds: Media clips, Audio, Text, Stickers, Effects, Transitions, Filters, Voice; from the open project, this Mac, plugins and built-in packs, with usage. Check here before making something new. With offset or limit, one page: {items, total, offset, limit, next} (next: the offset of the following page, null after the last); without them, every match as an array.

- Mode: read · Runs: immediately · MCP: `bashcut_library_list`
- `kind`: string, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice, clip, brand. Item kind
- `panel`: string, one of media, audio, text, stickers, effects, transitions, filters, brand, tools, captions, voice, beats. Only items the library panel shows
- `offset`: integer, ≥ 0. Skip this many matches (paging)
- `limit`: integer, 1…500. At most this many matches (paging; 50 with offset alone)
- `tag`: string. Only items with this tag
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `createdBy`: string, one of user, agent, plugin, built-in. Only items made by
- `pack`: string. Only items in this pack
- `query`: string. Text to find in the id, name, pack or tags
- `favorites`: boolean. Only favourites (starred on this Mac)
- `recent`: boolean. Only the items placed or applied in this project, newest first (at most 20)

### `bashcut library favorite <id> [--scope <scope>] [--off]`

Star a library item of any scope (built-in and plugin ones too) so the panels list it under Favorites, or remove the star with off. Favorites are global: kept on this Mac and shown in every project. library list marks them with favorite: true.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_favorite`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `off`: boolean. Remove the star

### `bashcut library get <id> [--scope <scope>]`

Read one library item, with its earlier versions and file paths.

- Mode: read · Runs: immediately · MCP: `bashcut_library_get`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in

### `bashcut library stats [--kind <kind>] [--panel <panel>]`

Usage of every library item, the saved items nobody used, and groups of duplicates (same kind and content), to find what to prune or merge.

- Mode: read · Runs: immediately · MCP: `bashcut_library_stats`
- `kind`: string, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice, clip, brand. Item kind
- `panel`: string, one of media, audio, text, stickers, effects, transitions, filters, brand, tools, captions, voice, beats. Only items the library panel shows

### `bashcut library add [--kind <kind>] [--name <name>] [--from-result <fromResult>] [--id <id>] [--scope <scope>] [--origin <origin>] [--author <author>] [--tags <tags>] [--pack <pack>] [--params <params>] [--file <file>] [--profile <profile>] [--preview <preview>] [--source <source>] [--license <license>]`

Save a new library item in the project or on this Mac. Files are copied in. Agents saving to the user scope wait for approval. To improve an existing item, use library update. fromResult saves a candidate of a finished library search or library generate job instead (its kind, name, files, source and license; the other fields here override them).

- Mode: edit · Runs: immediately · MCP: `bashcut_library_add`
- `kind`: string, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice, clip, brand. Item kind (required unless fromResult)
- `name`: string. Display name (required unless fromResult)
- `fromResult`: string. A library search or generate candidate as <job>:<index> (index from 0, as the job result lists it)
- `id`: string. Item ID: lowercase letters, digits and hyphens; from the name by default
- `scope`: string, one of project, user, default "project". project (the open project's .bashcut/library; the default) or user (this Mac; agents need approval)
- `origin`: string, one of stock, web, ai, own, built-in. Where it came from (P2-H8)
- `author`: string. Who made it, for the credit line
- `tags`: string. Comma-separated tags (mood, use, genre…)
- `pack`: string. Pack or collection name the panel groups it under
- `params`: object. What the kind needs (JSON): text-preset {textPreset, text, textStyle: {size, positionY, strokeWidth} (the item property ranges), animation: a clip motion preset}, the last two optional; sticker {emoji, textPreset} or a file (PNG, JPEG, HEIC, WebP, GIF, APNG, or a .mov/.mp4 with alpha; not Lottie) with {stickerKind: emoji|image|animated|video-alpha (from the file by default), size: width as 0.01–1 of the frame, position: center|top|bottom|left|right|top-left|top-right|bottom-left|bottom-right or {x, y} in 0–1, animation: a clip motion preset, seconds}, all optional; effect-preset (a recipe) {steps: [{op: motion|keyframes|speed|speedCurve|reverse|freeze|patch|sfx|text, …}], parameters: {name: {default, min, max}}} or the older {patch: item properties}, with its own sound as file; transition-preset {kind, duration, easing: linear|in|out|inOut, sfx: audio item ID, sfxOffset: frames from the cut (−600–600, negative before it), sfxVolumeDb: −60–12} (or its own sound as file); look (a filter stack) {color: {exposure, contrast, saturation, lutStrength}, lutName} with an optional .cube LUT as file; audio (its file required) {role: music|sfx|ambience, seconds, bpm, loopable, lufs, truePeak}, all optional (library add measures seconds and picks a role by length; library analyze fills the rest), with mood and genre as tags; clip (footage: a .mov/.mp4/.m4v or an image file, required) takes any keys (library add measures seconds, width, height and hasAudio; a generator's model, prompt or aspect may ride along)
- `file`: string, path. File to copy in (audio, image or alpha-movie sticker, a look's .cube LUT, a clip's movie or image…)
- `profile`: string. The reference profile it was made from (bc:style-study): a file path, URL or knowledge fact key; empty clears it
- `preview`: string, path. Preview image, GIF or audio snippet to copy in
- `source`: string. Where it came from (URL or note)
- `license`: string. License: text as written, or a JSON object {id, redistribute, commercial, attribution…}; stored as given

### `bashcut library update <id> [--scope <scope>] [--name <name>] [--tags <tags>] [--pack <pack>] [--params <params>] [--file <file>] [--profile <profile>] [--preview <preview>] [--source <source>] [--license <license>] [--as <as>] [--into <into>]`

Improve a library item: saves a new version (the old one stays in its history). Built-in and plugin items are read-only, so pass as to save an improved copy under a new ID instead. A new file is measured like library add (an audio item's seconds, a sticker's kind and size, a clip's length, size and sound) and values measured from the old file are dropped; the result lists measured and cleared (for audio, run library analyze again for loudness and tempo).

- Mode: edit · Runs: immediately · MCP: `bashcut_library_update`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `name`: string. New display name
- `tags`: string. Comma-separated tags (mood, use, genre…)
- `pack`: string. Pack or collection name the panel groups it under
- `params`: object. What the kind needs (JSON): text-preset {textPreset, text, textStyle: {size, positionY, strokeWidth} (the item property ranges), animation: a clip motion preset}, the last two optional; sticker {emoji, textPreset} or a file (PNG, JPEG, HEIC, WebP, GIF, APNG, or a .mov/.mp4 with alpha; not Lottie) with {stickerKind: emoji|image|animated|video-alpha (from the file by default), size: width as 0.01–1 of the frame, position: center|top|bottom|left|right|top-left|top-right|bottom-left|bottom-right or {x, y} in 0–1, animation: a clip motion preset, seconds}, all optional; effect-preset (a recipe) {steps: [{op: motion|keyframes|speed|speedCurve|reverse|freeze|patch|sfx|text, …}], parameters: {name: {default, min, max}}} or the older {patch: item properties}, with its own sound as file; transition-preset {kind, duration, easing: linear|in|out|inOut, sfx: audio item ID, sfxOffset: frames from the cut (−600–600, negative before it), sfxVolumeDb: −60–12} (or its own sound as file); look (a filter stack) {color: {exposure, contrast, saturation, lutStrength}, lutName} with an optional .cube LUT as file; audio (its file required) {role: music|sfx|ambience, seconds, bpm, loopable, lufs, truePeak}, all optional (library add measures seconds and picks a role by length; library analyze fills the rest), with mood and genre as tags; clip (footage: a .mov/.mp4/.m4v or an image file, required) takes any keys (library add measures seconds, width, height and hasAudio; a generator's model, prompt or aspect may ride along)
- `file`: string, path. File to copy in (audio, image or alpha-movie sticker, a look's .cube LUT, a clip's movie or image…)
- `profile`: string. The reference profile it was made from (bc:style-study): a file path, URL or knowledge fact key; empty clears it
- `preview`: string, path. Preview image, GIF or audio snippet to copy in
- `source`: string. Where it came from (URL or note)
- `license`: string. License: text as written, or a JSON object {id, redistribute, commercial, attribution…}; stored as given
- `as`: string. Save a copy under this new ID instead of a new version
- `into`: string, one of project, user. Scope of the copy (with as); project by default

### `bashcut library remove <id> [--scope <scope>]`

Remove a project or user library item and its files. Built-in and plugin items cannot be removed. Agents removing from the user scope wait for approval.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_remove`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in

### `bashcut library save-selection --kind <kind> --name <name> [--id <id>] [--item <item>] [--media <media>] [--scope <scope>] [--tags <tags>] [--pack <pack>]`

Save what is selected on the timeline as a new library item (the panels' Save selection as…): a text item's preset, text, textStyle (size, position, outline) and motion preset when its keyframes are one, a clip's effect as a recipe (reverse, freeze frame, speed or speed ramp, framing, keyframes scaled to the clip's length, and the sound effect at its start; a looping GIF of the clip as the timeline plays it as its preview), the transition at the selected clip (kind, duration, easing and the sound a preset placed there, with its offset from the cut and volume), or a grade as a look: the full filter stack, with the project LUT it uses copied in as the look's file, or an audio clip (or project audio media) as an audio item: its file copied in (for a clip trimmed to part of its file, only the part it plays, as WAV from an uncompressed file or else M4A, with trimmedFrom {start, end} in the file's seconds), its length, and music or sfx from its layer, or an overlay item as a sticker: an image or alpha movie with its file, size, position and length, or an emoji text item with its text preset.

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

Use a library item on an existing timeline item: a text preset on a text item (its preset, then its stored textStyle over the item's and its animation, as one undo step), an effect preset's recipe on a clip (every step, its sounds and text, and a split for a from/to range, as one undo step; set overrides its parameters; when a reverse step needs a new reversed copy it runs as a job), a look's grade (adding its LUT to the project when it has one, in the same undo step), or a transition preset at the cut beside a video clip (its kind, duration and easing, plus its sound on an SFX layer moved by sfxOffset at sfxVolumeDb, as one undo step). A brand kit applies to the whole project and needs no item: it sets the project's brand (palette, fonts, logo, mascot, voice, disclosure) and restyles every text item with brandRoles, as one undo step. Defaults to the selected item.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_apply`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `item`: string. Timeline item ID; the selection by default
- `set`: string. Effect preset parameters: name=value pairs (strength=1.5,frames=12) or a JSON object
- `from`: integer, ≥ 0. Effect preset: first timeline frame of the part of the clip to change
- `to`: integer, ≥ 1. Effect preset: timeline frame after that part (the clip's end by default)
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut library place <id> [--scope <scope>] [--at-frame <atFrame>] [--duration <duration>] [--track <track>] [--position <position>] [--size <size>] [--text <text>] --base-rev <baseRev>`

Add a library item to the timeline as a new item: a text preset (with its stored textStyle and animation) or emoji sticker as text, an image, animated or video-alpha sticker (its file copied into the project's stickers/ folder once per content, imported and placed on the Overlay layer, added when missing, at size and position, as one undo step; an animated GIF, APNG or WebP sticker plays as a ProRes 4444 movie with alpha written beside its copy, looped to cover the length asked or the sticker's seconds, and the result says animated: true), a look as an adjustment (with its LUT added to the project in the same undo step), or audio: its file copied into the project's music/ or sfx/ folder (once per content), imported and placed on the Music layer (music, ambience) or SFX layer (sfx), the layer added when missing, as one undo step. duration trims a sound; longer than the file, a loopable sound repeats back to back and another plays once (the result says so). A clip (footage) is copied into the project's clips/ folder (once per content), imported and placed like media place: on track or the main layer, spilling onto a free layer when the range is taken, duration trimming it, as one undo step. At the playhead by default.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_place`
- `id`: string, required. Item ID, or scope:id to pick one scope
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `atFrame`: integer, ≥ 0. First timeline frame
- `duration`: integer, ≥ 1. Length in timeline frames
- `track`: string. Layer ID; for audio, the Music or SFX layer by its role by default; for a sticker, the Overlay layer; for a clip, the main layer
- `position`: string. Sticker: center, top, bottom, left, right, top-left, top-right, bottom-left or bottom-right (inside the safe area), or x,y in 0–1 (its centre, from the top left); the sticker's default otherwise
- `size`: number, 0.01…1. Sticker: width as a fraction of the frame width (0.3 by default)
- `text`: string. Text for a text preset instead of its sample
- `baseRev`: integer, required, ≥ 0. Current project revision (rev of context.get or of your last edit), or "last": the revision as of your session's last command, still stale when anyone else changed the project since

### `bashcut library analyze <id> [--scope <scope>] [--provider <provider>]`

Measure an audio library item's file and save the values as a new version: its length, integrated loudness and true peak (an audio.loudness provider, as audio measure), landmarks {onset, peak, tail} in seconds (where it passes the −70 LUFS gate, peaks and drops back under it) and, unless it is a sound effect, its tempo in BPM (an audio.beats provider, as beats detect) with beatConfidence 0…1 when the provider gives one, and energy {rangeDb (quiet to loud parts), liftAt, peakAt seconds} (an audio.energy provider). Runs as a job; a missing provider leaves that value and says why in notes. Agents saving to the user scope wait for approval. Tag mood and genre with library update --tags after listening or reading the analysis. Several IDs separated by commas run in one job (result: items [{id, item, measured, notes} or {id, error}], analyzed, failed); a provider busy with another job is waited for, not refused.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_library_analyze`
- `id`: string, required. Item ID or scope:id; several separated by commas
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `provider`: string. audio.loudness provider ID; the project's choice by default

### `bashcut library preview [<id>] [--scope <scope>] [--stop]`

Play a library item's sound in BashCut (the Audio panel's play button), stopping any other; stop, or no id, stops it.

- Mode: ui · Runs: immediately · MCP: `bashcut_library_preview`
- `id`: string. Item ID, or scope:id
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `stop`: boolean, default false. Stop the sound playing

### `bashcut library search <query> --kind <kind> [--provider <provider>] [--limit <limit>] [--save <save>] [--scope <scope>] [--page <page>] [--request-id <requestId>] [--dry-run]`

Ask an installed plugin that provides library.search (sounds, stickers, GIFs… from Freesound, Giphy or another source) for candidate items of a kind. Runs as a job; its result lists candidates with their fields, downloaded file and preview paths, source and license. Nothing is saved until library add --from-result <job>:<index> (or save here) copies one into the library. Network use is the plugin's.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_library_search`
- `query`: string, required. What to look for
- `kind`: string, required, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice, clip, brand. Item kind
- `provider`: string. Plugin or provider ID; the first available provider that serves the kind by default
- `limit`: integer, 1…50, default 12. Most candidates to return
- `save`: integer, ≥ 0. Also save the candidate with this index (from 0) when the job finishes
- `scope`: string, one of project, user, default "project". Where save puts it: project (the default) or user (agents need approval)
- `page`: integer, 1…1000, default 1. Result page, from 1
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut library generate <prompt> --kind <kind> [--provider <provider>] [--limit <limit>] [--save <save>] [--scope <scope>] [--params <params>] [--request-id <requestId>] [--dry-run]`

Ask an installed plugin that provides library.generate (AI music, stickers…) to make candidate items of a kind from a prompt. Runs as a job; its result lists candidates like library search. Nothing is saved until library add --from-result <job>:<index> (or save here) copies one into the library.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_library_generate`
- `prompt`: string, required. What to make
- `kind`: string, required, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice, clip, brand. Item kind
- `provider`: string. Plugin or provider ID; the first available provider that serves the kind by default
- `limit`: integer, 1…50, default 4. Most candidates to return
- `save`: integer, ≥ 0. Also save the candidate with this index (from 0) when the job finishes
- `scope`: string, one of project, user, default "project". Where save puts it: project (the default) or user (agents need approval)
- `params`: object. Hints for the provider (JSON), such as {"seconds": 30}
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut library import-pack <path> [--scope <scope>] [--replace]`

Add a pack (a folder with pack.json and files, or a .zip of one) to the project or user library. IDs already there are refused unless replace saves them as new versions.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_import-pack`
- `path`: string, required, path. Pack folder or .zip
- `scope`: string, one of project, user, default "project". project (the open project's .bashcut/library; the default) or user (this Mac; agents need approval)
- `replace`: boolean, default false. Save items whose ID exists as new versions

### `bashcut library export-pack --output <output> [--pack <pack>] [--kind <kind>] [--scope <scope>] [--name <name>]`

Write library items as a pack folder (pack.json and files) to share or import elsewhere: one pack, or every item of a kind or scope. Refuses, naming them, when an item's own licence says redistribute false; unknownLicenses lists items exported whose licence does not say.

- Mode: edit · Runs: immediately · MCP: `bashcut_library_export-pack`
- `output`: string, required, path. New or empty folder to write
- `pack`: string. Items in this pack
- `kind`: string, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice, clip, brand. Item kind
- `scope`: string, one of built-in, user, project, plugin. Look only in this scope; without it project, user, plugin, then built-in
- `name`: string. Pack name; the pack filter or the folder name by default

### `bashcut library brand-pose <brand> --pose <pose> [--image <image>] [--generate] [--reference <reference>] [--scope <scope>] [--provider <provider>]`

Add a mascot pose to a brand kit (#551). With image: the photo's subject is cut out with a vision.cutout provider, saved as a sticker and stored as the pose. With generate: every pose name not in the kit yet is made with an image.generate provider from one reference (an existing pose, or reference), cut out and stored, in one job. Returns poses [{pose, sticker}], failed and the kit. A job.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_library_brand-pose`
- `brand`: string, required. Brand kit library id
- `pose`: string, required. Pose name (with image), or comma-separated pose names (with generate)
- `image`: string. Photo or picture to cut the pose from (relative to the project or absolute), or a sticker library id
- `generate`: boolean, default false. Generate the poses not in the kit yet
- `reference`: string. With generate: the picture or sticker id of the character; the kit's first pose by default
- `scope`: string, one of project, user. Library scope the pose stickers go into; the kit's by default
- `provider`: string. Provider ID overriding the project preference for one request

## fonts

### `bashcut fonts list [--query <query>] [--project] [--language <language>] [--covers]`

List fonts for text items (Inspector › Text › Font): the project's fonts folder first, then the fonts installed on this Mac, with PostScript names (textStyle.font) and, for the content language (or --language), whether each has every letter of it (covers).

- Mode: read · Runs: immediately · MCP: `bashcut_fonts_list`
- `query`: string. Only names or families containing this text
- `project`: boolean, default false. Only the project's own fonts
- `language`: string. BCP 47 tag to check letters for; default the content language
- `covers`: boolean, default false. Only fonts with every letter of that language

### `bashcut fonts import <path>`

Copy a .ttf, .otf or .ttc font into the project's fonts folder and use it for this project (Inspector › Text › Font › Add Font…). The font travels with the project; nothing is installed on the Mac.

- Mode: edit · Runs: immediately · MCP: `bashcut_fonts_import`
- `path`: string, required, path. Font file
