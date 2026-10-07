# Command reference

<!-- Generated from CommandCatalog by scripts/update-commands.sh. Do not edit by hand. -->

Every automation command, 200 in all. Each is the same command on the CLI (`bashcut …`), as an
MCP tool (`bashcut_<group>_<command>`, same parameter names as JSON-RPC) and over the socket. Modes and
approval are explained in the [automation guide](../guides/automation.md#permission-modes).

## context

### `bashcut context get`

Read the project path, revision, playhead and selection, and a summary of the agent knowledge: active lessons, preferences, project facts and the number of proposals; scope lists the timeline items attached to your tab's request (edit only those), with the scope guard's mode, a held edit and the user's answer to the last one (last); agentPermissions tells what you may do without asking; analysis lists running analysis jobs and the media not yet measured (media.analyze), transcribed (media.transcribe) or described (media.describe), so a plan does not use defaults where measurements are missing; plan summarises the brief (goal, outputs, length) and the edit plan (mode, stage, section/shot/beat counts, frozen sections); recentFailures lists your session's failed requests of the last 15 minutes (method, code, category, message) and repeated, how many in a row at the newest end share a method and category: stop and rethink after repeated ones.

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
- `outputs`: string. Comma-separated export presets (tiktok, reels, shorts, feed-4x5, square, portrait-3x4, youtube-1080, youtube-4k, quick-draft, prores); none clears them
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut project credits`

Rights facts of the media the edit plays (P2-H9): per media {media, name, kind, license and provenance as stored, framesOnTop (frames where it is the picture on top)}, frames, and ai {media, pictureShare}. Raw facts on request; credit wording and disclosure are yours. Nothing is added to the video. With the project's review.credits true, review notes AI picture as info and each export's job result carries these facts.

- Mode: read · Runs: immediately · MCP: `bashcut_project_credits`

### `bashcut project data <key>`

Read a top-level project field: brief, plan or any key of your own (a free JSON object, the agent's notes); null when unset.

- Mode: read · Runs: immediately · MCP: `bashcut_project_data`
- `key`: string, required. brief, plan or your own key

### `bashcut project set-data <key> <value.json> [--merge] --base-rev <baseRev>`

Set a top-level project field to a JSON object as one undoable edit; with merge, only the given fields change (null removes one). Identity, format, media and tracks are not data. Core reads only: brief lengthSeconds {min, max} and outputs [names], plan sections [{id, label, lengthSeconds {min, max}, frozen}], shots and beats [{id, text, section}] when present (directly or under value): review compares them with the edit, as info, and context get summarises them so work can resume from them.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_set-data`
- `key`: string, required. brief, plan or your own key
- `value`: object, required. The object (CLI: path to a JSON file)
- `merge`: boolean. Change only the given fields
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut project derive [--ids <ids>] [--dir <directory>]`

Write a sibling project per select (the kept ones, or ids): same canvas, outputs, review profile, brief and layers, only that media (paths made absolute) and the select's range on Main, with derivedFrom. Several shorts from one long recording; the open project does not change and nothing opens.

- Mode: edit · Runs: immediately · MCP: `bashcut_project_derive`
- `ids`: string. Select IDs instead of the kept ones
- `directory`: string, path. Parent folder; defaults to the one holding this project's folder

### `bashcut project recents`

List recently opened projects (Welcome screen).

- Mode: read · Runs: immediately · MCP: `bashcut_project_recents`

## timeline

### `bashcut timeline get [--format <format>]`

Read the revision, format and tracks, including track IDs and roles, and scale per video or image item: fit or fill, baseScale, zoom and maxZoom (keyframes), pixelRatio (output pixels per source pixel; over 1 is upscaled) now and at maxZoom, maxZoomNative (the largest zoom before upscaling), shown size and frameCoverage. media lists each media's path, kind, license and provenance as stored.

- Mode: read · Runs: immediately · MCP: `bashcut_timeline_get`
- `format`: string, one of json, text. json (default) or a compact text listing

### `bashcut timeline apply <ops.json> --base-rev <baseRev> [--label <label>] [--dry-run] [--why <why>] [--evidence <evidence>] [--expect-fingerprint <expectFingerprint>]`

Atomically apply validated timeline operations as one undoable edit; returns changed false and keeps the revision when nothing changes. why and evidence stay with the undo step (timeline.changes lists them). Both the dry run and the apply return fingerprint (the ops and baseRev); expectFingerprint refuses an apply whose ops differ from the reviewed dry run.

- Mode: edit · Runs: immediately · MCP: `bashcut_timeline_apply`
- `ops`: array, required. Operations array (CLI: path to ops.json)
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get
- `label`: string, default "Agent edit". Short description of the edit
- `dryRun`: boolean, default false. Validate without editing; return projected duration, changed IDs, cutsInsideWord (clip edges the edit leaves inside a transcribed word) and fingerprint
- `why`: string. Why this edit, in one sentence (up to 500 characters)
- `evidence`: string. What it rests on, separated by ; (review issue IDs, transcript ranges, measurements; up to 20, 200 characters each)
- `expectFingerprint`: string. The dry run's fingerprint; refuse other ops

### `bashcut timeline changes [--limit <limit>] [--author <author>]`

Recent edits from the undo history, newest first: step, label, author, why, evidence, at, the rev each produced and changes {counts, text, truncated}; undone lists what redo would bring back. Edits made before why was recorded have only label and author.

- Mode: read · Runs: immediately · MCP: `bashcut_timeline_changes`
- `limit`: integer, 1…50, default 10. Most edits to list
- `author`: string. Only this author (user, claude, codex, …), or agent for any agent

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

### `bashcut timeline sheet [--at <at>] [--cuts] [--text] [--every <every>] [--size <size>] [--columns <columns>] [--rows <rows>] [--outputs <outputs>]`

Lay the composed edit out on contact sheets without exporting: cells at listed frames (at: numbers, first, last), at every cut on Main (cuts), in the middle of every title (text) and every N seconds (every; 2 s when nothing else is asked), labelled '<cell> <m:ss.s>'. Returns {sheets [{path, output, firstCell, cells}], cells [{cell, frame, seconds, items on screen, text on screen}], index (the same as index.json), cached}. Kept per revision and request in .bashcut/cache/timeline-sheets. With outputs (all: the project's outputs; or preset names) another set of sheets per output of the frame's shape with the zones its interface covers shaded.

- Mode: read · Runs: immediately · MCP: `bashcut_timeline_sheet`
- `at`: string. Frames, comma separated; first and last allowed
- `cuts`: boolean. A cell at the start of every shot on Main
- `text`: boolean. A cell in the middle of every title
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

Add a media file (path relative to the project or absolute): video, audio or a still image (PNG keeps transparency; placed for 3 s, trims to any length). With place, also put it on a layer like Import. A file already in the project, unchanged, reuses its media and returns existing true. origin, license, source and author record where it came from (license is free text, or a JSON object with an open id and the facts you know: commercial, redistribute, attributionRequired, attribution; stored as given).

- Mode: edit · Runs: immediately · MCP: `bashcut_media_import`
- `path`: string, required, path. Media file path
- `kind`: string, one of video, audio, image. Media kind; from the file type by default
- `place`: boolean, default false. Also place it on a layer
- `track`: string. Layer ID for place; defaults to the main layer (music for audio)
- `atFrame`: integer, ≥ 0. Timeline frame for place
- `origin`: string, one of stock, ai, own, built-in. Where the file came from
- `license`: string. Its licence: text as written, or a JSON object {id, redistribute, commercial, attribution…}; stored as given
- `source`: string. Where it was found (URL)
- `author`: string. Who made it, for the credit line
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut media proxy [<media>] [--force]`

Queue preview proxies (smaller, quick-to-seek copies in .bashcut/cache/proxies; export keeps the originals) for heavy video media, or one media item. Imports queue them automatically. Returns a status per media: queued with its job ID, exists, not-needed, skipped, or unsupported (with codec and reason) when this Mac cannot decode the video.

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
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut media subjects --media <media> [--step <step>] [--from <from>] [--to <to>] [--provider <provider>] [--request-id <requestId>] [--dry-run]`

Faces and people in the picture of a video or image, with a vision.faces provider (built in: Apple Vision): frames [{seconds, frame (source), faces [{box, confidence}], people [{box, confidence}]}] one picture every step source seconds over from…to; box is [x, y, width, height] as shares of the upright picture from the top left. timeline [{item, at, fromSeconds, toSeconds}] places a second. No labels: which face is the speaker or matters is yours. A job.

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

Measure source media once and keep the record (by file content, in .bashcut/cache/analysis): file facts (codec, size, rotation, frame timing for variable frame rate, colour transfer/primaries/bit depth, track lengths), picture samples (luma, spread, change, peak as in review.picture, plus sharpness and colourfulness) with every jump searched to its exact frame as a cut candidate, and sound levels (RMS per 0.1 s, peak, stereo correlation). Read it with media.analysis. A record that exists is reused unless force. The job's result lists each media with its key and whether it was reused.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_media_analyze`
- `media`: string. Project media ID; every video and audio media by default
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

Transcribe whole source media once with a captions.transcribe provider and keep the transcript (by file content, in .bashcut/cache/transcripts), without placing anything on the timeline. Read it with media.transcript; captions.generate places captions from it without transcribing again, and transcript.words --heard maps its words through the clips. A transcript in the project's content language (by the given provider) is reused unless force. The job's result lists each media with status transcribed, reused or failed and its overview.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_media_transcribe`
- `media`: string. Project media ID; every video and audio media by default
- `force`: boolean. Transcribe again even when a transcript exists
- `provider`: string. Provider ID overriding the project preference for one request
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut media transcript --media <media> [--as <as>] [--from <from>] [--to <to>]`

Read the stored transcript of one media in its own seconds: language, provider, transcribedAt, speechSeconds, firstSpeech/lastSpeech, precision (wordTimes provider or none, and whether words carry confidence, speakers, events, noSpeechProb), then as words: wordList [{index, text, start, end, gapBefore, confidence?, speaker?, event?, noSpeechProb?}]; phrases (default): phraseList [{index, start, end, seconds, text, words, confidence (mean), gapBefore}]; json: both; text: one line per phrase (#index start–end seconds | text; print it with --format text). from/to keep what overlaps.

- Mode: read · Runs: immediately · MCP: `bashcut_media_transcript`
- `media`: string, required. Project media ID
- `as`: string, one of words, phrases, json, text. phrases (default), words, json or text
- `from`: number, 0…86400. Only from this source second
- `to`: number, 0…86400. Only up to this source second

### `bashcut media describe [<shots.json>] --media <media> [--merge] [--clear] --base-rev <baseRev>`

Store what you saw in a source media, shot by shot, as one undoable edit (it is saved with the project). Each shot: start and end in source seconds (shots may not overlap) and at least one fact: size, angle, move, direction (open labels; suggested: size ECU/CU/MCU/MS/MWS/WS/EWS/insert, angle eye/high/low/top/dutch/pov/ots, move static/pan/tilt/push/pull/track/orbit/handheld/zoom/crane, direction left/right/toward/away/none), subjects (up to 12 names), tags, people, onScreenText, confidence 0–1, bestMoment (source seconds or null), looked (source seconds of the frames you looked at), note; any other field is kept as given. Replaces the description unless merge (shots overlapping the new ones are replaced) or clear. Returns rev and coverage.

- Mode: edit · Runs: immediately · MCP: `bashcut_media_describe`
- `shots`: array. Shots array, or {shots: […]} (CLI: path to shots.json)
- `media`: string, required. Project media ID
- `merge`: boolean. Keep stored shots that the new ones do not overlap
- `clear`: boolean. Remove the description
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut media description [--media <media>]`

Read media descriptions. With media: description {shots, describedBy, describedAt} and coverage {shots, describedSeconds, describedShare, and with a media.analyze record measuredShots, coveredShots (half or more of the measured shot described) and missing [{index, start, end}]}. Without: each media's coverage, describedMedia/totalMedia, measuredShots/coveredShots, missing media IDs and the vocabulary.

- Mode: read · Runs: immediately · MCP: `bashcut_media_description`
- `media`: string. Project media ID; every media by default

### `bashcut media frames [--media <media>] [--at <at>] [--every <every>] [--count <count>] [--from <from>] [--to <to>] [--sheet] [--columns <columns>] [--rows <rows>] [--size <size>] [--reference <reference>] [--reference-from <referenceFrom>] [--reference-to <referenceTo>]`

Read exact source frames of media as PNG files (in .bashcut/cache/media-stills; read them to look): at the given source seconds, every N seconds, or count evenly spaced (default 8, each in the middle of its part) over from…to (the whole file by default). Every media with a picture by default. frames [{path, media, frame (exact source frame index), seconds, width, height}]. With sheet: contact sheets of columns × rows cells labelled '<cell> <file> <m:ss.s>' (the colour changes with each media), sheets [{path, cells [{cell, media, frame, seconds}]}], so a cell maps back to its media and second. With reference (one media): a sheet with a REF row from that media (over referenceFrom…referenceTo) above an OURS row, cell for cell. At most 400 frames per call.

- Mode: read · Runs: immediately · MCP: `bashcut_media_frames`
- `media`: string. Media IDs, comma separated; every media with a picture by default
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

## review

### `bashcut review run [--since-rev <sinceRev>] [--min-severity <minSeverity>] [--summary]`

Review the timeline before export: issues {id, kind, severity error|warning|info, title, detail, frame, endFrame?, facts {raw numbers}, fix? {command?, arguments?, hint?}}, errors first. Invariants (gaps, black picture, cut-in-word, missing fonts or glyphs, output length and shape, true peak) are always checked; editorial checks only against the limits in the project's review object, and nothing without them. IDs are anchored to clips. With summary: {issues, summary, checks (measured, stale, notChecked, failed, unreliable, unsetLimits)}; with sinceRev also diff {fixed, new, persisting}.

- Mode: read · Runs: immediately · MCP: `bashcut_review_run`
- `sinceRev`: integer, ≥ 0. Compare with the review of this revision (this session)
- `minSeverity`: string, one of error, warning, info. Leave out issues less severe than this
- `summary`: boolean. Wrap the issues with counts and a pass flag

### `bashcut review measure [--picture <picture>] [--plugins <plugins>]`

Run the measured review for this revision and keep it, so review.run includes it: render the timeline small (two frames a second and both sides of every hard cut on Main, proxies allowed) for black or empty picture, frozen picture, long static shots and jump cuts, and run every enabled plugin review.check side by side (each at most 30 s; a failing or slow check becomes an info issue). Plugin issues carry source (the plugin ID) and IDs prefixed with the provider. A project turns checks off with review.disabledChecks (plugin or provider IDs; timeline apply setProjectProperties). The job's result has the sample count, the plugin checks that ran and the measured issues; measure again after an edit.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_review_measure`
- `picture`: boolean. Measure the picture (default true)
- `plugins`: boolean. Run plugin review checks (default true)

### `bashcut review accept <id> [--reason <reason>] [--remove] --base-rev <baseRev>`

Keep a warning or note on purpose, with the reason, as one undoable edit (review.accepted); later runs show it with accepted.reason, leave it out of the counts, and the export report lists it. Errors cannot be accepted: fix them, or change their severity in review.severities with a reason. With remove, the issue counts again.

- Mode: edit · Runs: immediately · MCP: `bashcut_review_accept`
- `id`: string, required. Issue ID from review run
- `reason`: string. Why it stays
- `remove`: boolean. Count the issue again
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut review verify <id>`

Prove a fix: the issue as an earlier review of this session saw it (before, beforeRev) against now, measured over the issue's own range and a second around it (picture issues re-sample just that range; others re-run the review), status fixed or persisting, other issues nearby, and window: a still strip of the range with the cuts, words and levels. Loudness needs a normalized export of the revision.

- Mode: read · Runs: immediately · MCP: `bashcut_review_verify`
- `id`: string, required. Issue ID

### `bashcut review packet`

Write an evidence folder for a fresh critic (a sub-agent with only this folder and bc:review): README, plan.json (brief, plan, review profile, outputs), digest.json (what changed since the last review round), issues.json (with the round diff), shots.json (review.shots with summary), word-landing.json (words against cuts and titles), coverage.json (described shot per clip, script beats heard), measured.json (what was and was not measured) and a contact sheet of every cut and title. No editor reasons are included.

- Mode: read · Runs: immediately · MCP: `bashcut_review_packet`

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

Read where text sits as the renderer lays it out: per visible text item id, track, trackRole, at/end, text, preset, lines, longestLineChars, fontPixels and fontShare (of the frame's short side), bounds (pixels from the top-left) and edges (distance to each frame edge as a share of that dimension, negative outside), keyframed when keyframes move it (not followed); holdSeconds, words and wordsPerSecond; speech {onsetOffsetFrames (from the nearest word start), narrationShare (of its time with words spoken)} from the heard or caption words; captionOverlap {item, ratio of its box} for titles; templateRepeats (items with its preset on its layer); faceOverlap null (unknown: not measured here; media subjects gives face boxes in source pictures). With contrast: contrast {ratio (WCAG, 1–21) of the mean, lightRatio and darkRatio (the light and dark parts of the text, such as fill and outline), textLuminance, backgroundLuminance, textPixels} measured on the frame with and without text (at frame, or each item's middle). Also the frame size, the platform whose zones apply (safeArea, minTextSize), density (titles and captions per minute) and, at a frame, pictures on screen with their scale and coverage. With from/to, only text that overlaps those frames. With ink: ink {frame, luma, mid (0–100), inkShare (pixels text and overlay layers change)} of the composed frame (frame, default 0) against Main alone. No verdicts.

- Mode: read · Runs: immediately · MCP: `bashcut_review_layout`
- `frame`: integer, ≥ 0. Only text on screen at this timeline frame
- `from`: integer, ≥ 0. Only text that ends after this timeline frame
- `to`: integer, ≥ 1. Only text that starts before this timeline frame
- `ink`: boolean. Measure the composed frame (frame, default 0): luma, mid and inkShare
- `contrast`: boolean. Measure each item's contrast on rendered frames

### `bashcut review sync [--events <events>] [--bins] [--rendered]`

Time events against the beat grid and the spoken words: per event (cuts on Main by default; text items and sfx items on request) the nearest beat and the nearest word edge (start or end, its text, whether the event falls inside the word) with offsetFrames and offsetMs (positive = after it), and for beats and words count, mean and median offset (with bins also p10, p90 and counts per offset from −6 to +6 frames). Words are the stored transcripts heard through the clips (media.transcribe), else the caption words. With rendered: rendered {windows [{at, lagMs, correlation}], driftMsPerMinute, lagStartMs, lagEndMs} from matching the last export's sound to the timeline's mix every 10 s (positive lag = the render is later); the export must show this revision.

- Mode: read · Runs: immediately · MCP: `bashcut_review_sync`
- `events`: string. cuts, text, sfx, captions (comma separated; default cuts)
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

Read the platform facts review uses: per platform (TikTok, Reels, Shorts, YouTube) shape, maxSeconds, targetLUFS, maxTruePeakDbTP and safeArea (zones the app covers, as fractions), with the project's review.platform overrides applied, whether it is one of the project's outputs and whether it was overridden; layout: the zones text is checked against (the strictest of the outputs of the frame's shape, null when none); targets: each output preset's loudness target (output.targets, else the platform's); data: the platform table's version and origin (built-in or the plugin that shipped a newer one). With facts, every field with {value, kind hard|recommended|info, source, checked, confidence}, including bitrateMbps, title and cover facts, chapter and disclosure rules where known. With id, that one platform's row with its facts.

- Mode: read · Runs: immediately · MCP: `bashcut_platforms_get`
- `id`: string. tiktok, reels, shorts, youtube
- `facts`: boolean. Include each field's provenance

## export

### `bashcut export status`

Read the export state: while one runs, its job, step, preset and path (last receipt under lastExport); otherwise the most recent receipt. Includes the queue (job IDs for jobs.cancel) and delivered: each exported file of this session measured (stream starts and drift, fps and size against the preset, black and silent stretches), which review run reads (P1-E6).

- Mode: read · Runs: immediately · MCP: `bashcut_export_status`

### `bashcut export cover <frame> [--aspect <aspect>] [--size <size>]`

Write a still of the composed frame for each cover aspect into render/: the asked aspects (W:H, comma separated), else each output's cover aspect from platforms get (cover.aspect, else its shape), cropped from the centre. Pick the frame from real frames (timeline sheet); look at the result.

- Mode: ui · Runs: immediately · MCP: `bashcut_export_cover`
- `frame`: integer, required, ≥ 0. Timeline frame
- `aspect`: string. Aspects such as 16:9,9:16
- `size`: integer, 160…3840. Long edge in pixels

### `bashcut export chapters [--platform <platform>] [--write]`

A chapter list from the section markers (00:00 first; an Intro at 0 when no marker is there) and each rule of the platform's chapter fact (first at 00:00, the least count, the shortest chapter) with whether it holds. With write, saves render/chapters-<platform>.txt. Caption mode per output is output.captions (preset → {mode burn|sidecar|both|none, format srt|vtt, track}); the export follows it.

- Mode: ui · Runs: immediately · MCP: `bashcut_export_chapters`
- `platform`: string. Platform whose rule applies (default youtube)
- `write`: boolean. Save the list in render/

### `bashcut export start --preset <preset> --name <name> [--output-dir <directory>] [--include-srt] [--normalize-audio] [--bitrate <bitrate>]`

Request a background video export; the user approves it in the app first. Approved exports queue behind a running one. Vertical presets default under the platform's recompression line (platforms list: bitrateMbps); bitrate overrides it. Feed shapes: feed-4x5 (1080×1350), square, portrait-3x4 (1080×1440). The export status reports the bitrate written.

- Mode: privileged · Runs: after the user approves in the app · MCP: `bashcut_export_start`
- `preset`: string, required, one of tiktok, reels, shorts, feed-4x5, square, portrait-3x4, youtube-1080, youtube-4k, quick-draft, prores. Export preset
- `name`: string, required. Output base name without an extension
- `directory`: string. Output folder, relative to the project; defaults to its render folder
- `includeSRT`: boolean, default false. Also write a SubRip file
- `normalizeAudio`: boolean, default false. Run two-pass LUFS normalization with a plugin
- `bitrate`: number, 0.5…200. Video bit rate in Mbps instead of the preset's

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

### `bashcut plugins validate [<path>] [--url <url>] [--ref <ref>] [--sha256 <sha256>]`

Check a plugin that is not in the registry (a folder, its plugin.json, a .zip or .bashcutplugin archive, or a link) without installing or running it: its id, version and capabilities, every problem with the field and the fix (library packs included: each pack.json and the files it names, inside the plugin), and for a link the commit or release it resolved to.

- Mode: read · Runs: immediately · MCP: `bashcut_plugins_validate`
- `path`: string, path. Plugin folder, plugin.json, or .zip / .bashcutplugin file (or use url)
- `url`: string. Link to a .zip / .bashcutplugin file, a GitHub repo (or /tree/<ref>/<folder>, or its plugin.json) or a GitHub release; #sha256=<hex> pins it. A private link uses the access token saved in Add Plugin…
- `ref`: string. Tag, branch or commit for a GitHub repo link (release tag for a release link)
- `sha256`: string. Expected SHA-256 of the downloaded archive

### `bashcut plugins install [<plugin>] [--version <version>] [--path <path>] [--url <url>] [--ref <ref>] [--sha256 <sha256>] [--scope <scope>] [--link]`

Download a registry plugin (or its update), check its SHA-256 and manifest, and show the install approval in the Plugins sheet. With path or url instead, add a plugin that is not in the registry (Add Plugin…): a folder, its plugin.json or a .zip / .bashcutplugin file on this Mac, or a link, checked like plugins validate. Only the user can approve; the job ends when the approval is shown.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_plugins_install`
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

Show the approval to run an installed plugin's dependency install recipes again (Install Dependencies…). Only the user can approve; follow it with jobs status.

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
- `type`: string, one of click, change, submit, select, action, default "click". What happened
- `value`: string. New value (change), row id (select) or {"item","action"} (action); JSON or text

### `bashcut plugins invoke <capability> [--provider <provider>] [--params <params>]`

Run a plugin capability directly with raw parameters and return the provider's raw result, for capabilities without their own command (prefer voice speak, captions generate, beats detect … when one exists). Files go to the returned outputDirectory. Plugins call this from their views and actions for capabilities listed in their manifest's uses.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_plugins_invoke`
- `capability`: string, required. Capability ID, such as voice.synthesize
- `provider`: string. Provider ID; the project's choice or the highest priority by default
- `params`: object. Request parameters (JSON object)

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

### `bashcut captions group [<groups.json>] [--source <source>] [--max-chars <maxChars>] [--max-seconds <maxSeconds>] [--break-gap <breakGapSeconds>] [--from <from>] [--to <to>] --base-rev <baseRev>`

Re-cut captions from word groups you choose, as one undoable edit: groups is a list of runs of word indices (from transcript words, or with source heard from transcript words --heard), each becoming one caption from its first word's start to its last word's end with its words timed; the captions those words fall in are replaced (their style kept). Rule mode instead (maxChars, maxSeconds and breakGapSeconds, all required; from/to limit it) joins words greedily. Returns rev and facts: cues [{frames, seconds, chars, cps, text}], gaps and overlaps between cues in frames. No default grouping.

- Mode: edit · Runs: immediately · MCP: `bashcut_captions_group`
- `groups`: array. Runs of word indices (CLI: path to groups.json)
- `source`: string, one of captions, heard. captions (default) or heard
- `maxChars`: integer, 1…500. Rule mode: longest caption in characters
- `maxSeconds`: number, 0.1…60. Rule mode: longest caption in seconds
- `breakGapSeconds`: number, 0…10. Rule mode: a pause this long starts a caption
- `from`: integer, ≥ 0. Rule mode: from this timeline frame
- `to`: integer, ≥ 0. Rule mode: up to this timeline frame
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

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

Read every word on the caption layers in timeline order: index, text, at/end (frames), atSeconds, endSeconds, item and cue (captions export numbering), timing (transcribed or estimated from word length), gapBefore (frames since the previous word ended) and, for captions made from a media, source {media, clip, start, end} in that media's seconds through the clip heard there now (null when no clip of it plays there: captions do not move with their clips). count is the words returned, total the words on the caption layers. With heard, the words come from the stored transcripts (media.transcribe) of the media the timeline plays instead: each word inside a clip that plays it, at that clip's frames (trim, speed), with item = the clip, timing source and the provider's confidence/speaker/event/noSpeechProb; transcribed and untranscribed list the media.

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
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut layers set <track> [--hidden <hidden>] [--muted <muted>] [--locked <locked>] [--language <language>] --base-rev <baseRev>`

Change a layer's header switches like the timeline header: hide a visual layer, mute an audio layer, lock any layer (a locked layer refuses edits until unlocked); set a caption layer's language (P1-F4), which output.captions picks a layer by.

- Mode: edit · Runs: immediately · MCP: `bashcut_layers_set`
- `track`: string, required. Layer ID
- `hidden`: boolean. Hidden (visual layers)
- `muted`: boolean. Muted (audio layers)
- `locked`: boolean. Locked
- `language`: string. Language tag such as vi or en; none clears it
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

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

Animate a clip, image or text over its length (Inspector › Animation): a preset (zoom-in, zoom-out, pan-left, pan-right, pan-up, pan-down, fade-in-out, pop-in, slide-up, zoom-punch; none removes the animation) sized to the item, or keyframes JSON {property: [{frame, value, ease?}, …]} with frames from the item's start. Properties: zoom, pan, tilt (px, up), rotation (degrees), opacity, and volume (dB, like volumeDb; the only one on audio items, none on text); ease: linear, in, out, inOut, hold or cubic-bezier(x1,y1,x2,y2) (default inOut). Keys replace the item's static value for that property. Images with zoom-in, zoom-out or pan-* make a Ken Burns move; presets are for pictures and text. focus frames a rectangle of a video clip (a panel of a screen recording) without working out zoom, pan and tilt by hand.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_motion`
- `item`: string. Item ID; the selection by default
- `preset`: string, one of zoom-in, zoom-out, pan-left, pan-right, pan-up, pan-down, fade-in-out, pop-in, slide-up, zoom-punch, none. Preset name, or none
- `keyframes`: string. Keyframes as JSON, replacing the item's animation
- `focus`: string. Frame a rectangle of a video clip's picture: x,y,width,height in source pixels from the top left (media.list width/height); sets zoom, pan and tilt and keeps the other keys
- `focusTo`: string. With focus: move to this rectangle by the item's last frame
- `ease`: string. With focus-to: the move's ease (linear, in, out, inOut, hold or cubic-bezier(x1,y1,x2,y2))
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut clip keyframe [<item>] [--property <property>] [--value <value>] [--at-frame <atFrame>] [--ease <ease>] [--remove] --base-rev <baseRev>`

Set one keyframe like the Inspector's controls with keyframes on: property at a timeline frame (the playhead by default) to value (its current value when omitted); remove deletes that key. Without property, keys every picture property at its current value (the Inspector's Keyframe at playhead); on an audio item, its volume. Volume (dB) works on audio items and clips with sound.

- Mode: edit · Runs: immediately · MCP: `bashcut_clip_keyframe`
- `item`: string. Item ID; the selection by default
- `property`: string, one of color.contrast, color.exposure, color.lutStrength, color.saturation, opacity, pan, rotation, textStyle.lineHeight, textStyle.positionX, textStyle.positionY, textStyle.size, textStyle.strokeWidth, textStyle.tracking, tilt, volume, zoom. Property; all of them by default
- `value`: number. Value
- `atFrame`: integer, ≥ 0. Timeline frame inside the item; the playhead by default
- `ease`: string. Change to the next key: linear, in, out, inOut, hold or cubic-bezier(x1,y1,x2,y2)
- `remove`: boolean, default false. Remove the key at that frame
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut clip reverse [<item>]`

Play a video clip backwards (with its linked sound): renders a reversed copy of the source it uses into the project's reversed/ folder and points the clip at it. Reversing again restores the original.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_clip_reverse`
- `item`: string. Item ID; the selected clip by default

## jobs

### `bashcut jobs status [<job>]`

Read one job (plugin call or export), or all recent jobs when job is omitted. Each job has state, progress, step and usage {provider, wallSec, units, costUSD, costSource}: units and cost only as a provider reported them, never estimated.

- Mode: read · Runs: immediately · MCP: `bashcut_jobs_status`
- `job`: string. Job ID

### `bashcut jobs wait <job> [--timeout <timeout>]`

Wait until a job's state or step changes, or it finishes, up to timeout seconds; returns the job, changed and timedOut. A finished job returns at once. Use it instead of polling jobs status.

- Mode: read · Runs: immediately · MCP: `bashcut_jobs_wait`
- `job`: string, required. Job ID
- `timeout`: integer, 1…30, default 25. Seconds to wait at most

### `bashcut jobs cancel <job>`

Cancel a queued or running job (plugin call or export).

- Mode: edit · Runs: immediately · MCP: `bashcut_jobs_cancel`
- `job`: string, required. Job ID

## capabilities

### `bashcut capabilities get [<capability>] [--kind <kind>] [--voices]`

Whether each plugin capability (or one) can serve now: available, else reason missing (no plugin provides it), not_configured (turned off, not approved, changed, outdated or missing a required plugin) or unhealthy (a dependency fails its health check). Lists each provider with plugin, priority, paid, state and detail, and the commands that call the capability. A command whose capability cannot serve fails with category capability_missing and the same reason. With voices, voices: the voices of every voice.synthesize provider (per provider plugin, name, availability, clones (voice speak then needs cloneConsent) and the voice its plugin is set to; per voice id, language, region, style, gender, supportsRate and measuredRate (rates measured on its takes, per language: samples, p10, p50, p90)); without a capability the result is then {capabilities, voices}.

- Mode: read · Runs: immediately · MCP: `bashcut_capabilities_get`
- `capability`: string. Capability ID, such as captions.transcribe; all by default
- `kind`: string, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice. Only providers serving this library item kind
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

Read the mix by role without exporting: one stem each for speech (dialogue and voiceover layers and the sound of video clips), music and sound effects is rendered (other sounds at −120 dB, so ducking stays as in the mix) and measured over time. Spoken blocks are those inside heard or caption words, else where the speech stem is over −70 LUFS. Returns voice, musicUnderSpeech (voice minus music, in LU) and musicInGaps as {median, p10, p90, blocks}; speechWindows with the same per window; effects per sound-effect item: loudness (loudest momentary LUFS), peakDb, voiceP95 within nearSeconds, deltaDb, masked (under that voice level), onset and peak offsets in frames to the nearest cut, beat and word edge; and each stem's integrated loudness. A job; no levels are changed.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_audio_mix-measure`
- `nearSeconds`: number, 0.1…10. Seconds around an effect read for the voice (default 1)
- `provider`: string. Provider ID overriding the project preference for one request
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

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

The user's workflow gates: G1 brief, G2 strategy, G3 roughCut (rough-cut sheet), G4 script (before speech is made), G5 draft (before export) and any gate a skill stopped at by name, each ask, notify or skip (ask unless the user changed it), and maxReviewRounds. Request each gate with checkpoint request; never decide one is approved yourself.

- Mode: read · Runs: immediately · MCP: `bashcut_workflow_gates`

### `bashcut workflow set-gates [--gate <gate>] [--mode <mode>] [--max-review-rounds <maxReviewRounds>]`

Change a gate or the review round limit. Agents may only make a gate ask more (skip → notify → ask); loosening a gate or changing the round limit is the user's (Settings → Agents → Workflow gates).

- Mode: ui · Runs: immediately · MCP: `bashcut_workflow_set-gates`
- `gate`: string. G1…G5, brief, strategy, roughCut, script, draft or a gate name
- `mode`: string, one of ask, notify, skip. Gate mode
- `maxReviewRounds`: integer, 1…10. Review round limit (user only)

## checkpoint

### `bashcut checkpoint request <gate> --summary <summary> [--attach <attach>]`

Stop at a gate: with ask, the user sees the summary and attachments in BashCut and answers approved, changes (with a note) or rejected; poll checkpoint status until it is not awaiting_user. With notify the user is told and the run goes on; with skip nothing is shown. The answer is bound to the current revision and written to the run log; only the user can answer.

- Mode: ui · Runs: immediately · MCP: `bashcut_checkpoint_request`
- `gate`: string, required. G1…G5, brief, strategy, roughCut, script, draft, or any name (1–40 letters, digits, ., -, _) for a stop of your own
- `summary`: string, required. What the user is asked to approve
- `attach`: string. Comma-separated files to show (sheets, stills); relative to the project

### `bashcut checkpoint status [<id>]`

A checkpoint of this session (default the last): status awaiting_user, approved, changes, rejected, skipped, notified or withdrawn, the user's note, the revision it covers and stale when the project has changed since.

- Mode: read · Runs: immediately · MCP: `bashcut_checkpoint_status`
- `id`: string. Checkpoint ID

## run

### `bashcut run log [--run <run>] [--kind <kind>] [--limit <limit>]`

The run log (.bashcut/run-log.jsonl, append-only): starts, stages, gates with the user's answers, review rounds (fixed, left), what was measured and not measured, notes. Read it for the hand-off report and self-learn instead of the chat.

- Mode: read · Runs: immediately · MCP: `bashcut_run_log`
- `run`: string. current (default), all or a run number
- `kind`: string. Only this kind
- `limit`: integer, 1…10000. Last N entries

### `bashcut run append <kind> [--data <data>] [--stage <stage>] [--text <text>] [--round <round>] [--fixed <fixed>] [--left <left>] [--measured <measured>] [--not-measured <notMeasured>]`

Append to the run log: an entry of any kind (start opens a run; stage, round, measured, note and end are the usual ones; gate is reserved for checkpoints) with the fields given and any data object. The revision, author and time are added.

- Mode: ui · Runs: immediately · MCP: `bashcut_run_append`
- `kind`: string, required. Entry kind (1–40 characters; not gate)
- `data`: object. More fields as a JSON object
- `stage`: string. Stage name
- `text`: string. What happened
- `round`: integer, 1…100. Review round
- `fixed`: integer, ≥ 0. Issues fixed this round
- `left`: integer, ≥ 0. Issues left
- `measured`: string. Comma-separated checks measured
- `notMeasured`: string. Comma-separated checks not measured

## script

### `bashcut script check [--beats <beats>] [--text <text>]`

A script against the words heard on the timeline (stored transcripts, else caption words): per beat (the beats given, the text as one beat, else the plan's beats) the share of its words heard as written, the unmatched words, where it was heard and the section marker it starts in against the beat's section; overall similarity and extra heard words.

- Mode: read · Runs: immediately · MCP: `bashcut_script_check`
- `beats`: array. Beats [{id, text, section}] as JSON
- `text`: string. The whole script as one beat

## selects

### `bashcut selects list [--status <status>]`

The project's selects: source ranges {id, media, from, to (seconds), status (free; usually candidate, kept or rejected), quote, reason (why it was picked), evidence, mustKeep, order, statusReason (why its status last changed)} and counts per status. The user sees and overrides them in the Media panel (Selects).

- Mode: read · Runs: immediately · MCP: `bashcut_selects_list`
- `status`: string. Only this status

### `bashcut selects set <value.json> --base-rev <baseRev>`

Add, update or remove selects (by id; a new one without id gets one, status candidate) as one undoable edit. Give the quote, the reason and the evidence (what was measured) with each; media resolve-range gives from/to. On an existing select, status or mustKeep with a reason keeps it as statusReason; {id, remove: true} removes it. A must-keep select no clip plays is a review warning.

- Mode: edit · Runs: immediately · MCP: `bashcut_selects_set`
- `value`: array, required. Selects (CLI: path to selects.json)
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

### `bashcut selects place [--ids <ids>] [--at-frame <atFrame>] --base-rev <baseRev>`

Lay the kept selects (or the given IDs) in order (order, else source start), from atFrame or the first one's layer end, as one undoable edit: pictures on Main, sound-only media on the dialogue layer (else music); returns the new item IDs.

- Mode: edit · Runs: immediately · MCP: `bashcut_selects_place`
- `ids`: string. Select IDs instead of the kept ones
- `atFrame`: integer, ≥ 0. Timeline frame
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

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

### `bashcut voice speak [<text>] [--takes <takes>] [--provider <provider>] [--choose <choose>] [--at-frame <atFrame>] [--replace <replace>] [--clone-consent] [--request-id <requestId>] [--dry-run]`

Synthesize voice takes and measure them: per take index, path, projectPath, seconds, units (syllables, words or characters for the content language), unitsPerSecond over its sound, leadingSilence, trailingSilence, pauses and the provider's score when it gives one; the rates are kept per voice (speech rate). Every take file is kept: pick one yourself and put it on the timeline with voice place. With choose, take N goes on the Voiceover track at once (the rest are removed); with replace, the take (choose, default 1) goes into that item, keeping its place, and its captions are timed again. The item keeps voice {text, language, provider, voice}.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_voice_speak`
- `text`: string. Voiceover text in the project content language (with replace, the item's voice text by default)
- `takes`: integer, 1…8, default 3. Number of takes to generate
- `provider`: string. Provider ID overriding the project preference for one request
- `choose`: integer, 1…8. Put this take on the timeline (1 = first)
- `atFrame`: integer, ≥ 0. With choose: timeline frame; defaults to the playhead
- `replace`: string. Voiceover item to put the take into, keeping its place
- `cloneConsent`: boolean. The user agreed to clone the voice set in the plugin's options; providers that clone refuse without it
- `requestId`: string. Your stable ID for this request: sending it again returns the same job instead of starting (and paying for) another; the provider receives it too
- `dryRun`: boolean, default false. Return the request as it would go to the provider (without option values), whether the provider is paid and its estimate if it gives one; nothing runs

### `bashcut voice place <take> [--at-frame <atFrame>] [--replace <replace>]`

Put a take voice speak kept on the Voiceover track with its voice facts and provenance: at a frame (the playhead by default), or into a voiceover item, keeping its place, with its captions timed again from the new take.

- Mode: edit · Runs: immediately · MCP: `bashcut_voice_place`
- `take`: string, required. The take's path or projectPath from voice speak
- `atFrame`: integer, ≥ 0. Timeline frame; defaults to the playhead
- `replace`: string. Voiceover item to put the take into

### `bashcut voice check [--item <item>] [--media <media>] [--text <text>] [--min-similarity <minSimilarity>] [--provider <provider>] [--request-id <requestId>] [--dry-run]`

Check what a voiceover take says against the text it should say: the take (a voiceover item, or a media) is transcribed (or its stored transcript reused) and diffed word by word. Returns similarity (matched words over the longer word count), words [{text, heard, kind match|substituted|missing, start, end}], unmatched, extra (heard but not in the text) and, only with minSimilarity, passed. The text defaults to the item's voice.text. A job.

- Mode: read · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_voice_check`
- `item`: string. Voiceover item ID
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
- `baseRev`: integer, required, ≥ 0. Current project revision from timeline.get

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

Run an editor action like the user: by ID (timeline.split, timeline.zoom-in, playback.toggle) or by shortcut (cmd+b, space, cmd+=). Actions that open a dialog return at once; answer it with ui.respond. With a target: open DIALOG (a sheet or popover: new-project, export, export-report, agent-changes, review, history, plugins, settings, doctor, knowledge, ask, sections, external-changes, plugin-proposals, commands, shortcuts, add-plugin, library-search, library-generate), panel PANEL (a library panel in the left rail: media, audio, text, stickers, effects, transitions, filters, voice), source MEDIA (the source viewer, with --in/--out frames marked) or notify MESSAGE (a short status message).

- Mode: edit · Runs: immediately · MCP: `bashcut_ui_action`
- `action`: string, required. Action ID or shortcut, or open, panel, source, notify
- `target`: string. The dialog, panel, media ID or message of open, panel, source, notify
- `in`: integer, ≥ 0. source: in frame
- `out`: integer, ≥ 1. source: out frame (exclusive)

### `bashcut ui view [--zoom <zoom>] [--zoom-anchor <zoomAnchor>] [--snap <snap>] [--safe-area <safeArea>] [--viewer-zoom <viewerZoom>] [--compare <compare>] [--agent-dock <agentDock>] [--reveal <reveal>] [--inspector <inspector>] [--settings-section <settingsSection>] [--settings-search <settingsSearch>] [--knowledge-section <knowledgeSection>] [--plugins-tab <pluginsTab>] [--plugins-category <pluginsCategory>] [--media-source <mediaSource>] [--library-query <libraryQuery>] [--library-pack <libraryPack>] [--library-tag <libraryTag>] [--library-scope <libraryScope>]`

Read the editor view state, or change it: timeline zoom (pixels per second), viewer zoom, snapping, safe area, color compare, agent dock, inspector tab, Settings section and search, Knowledge section, Plugins tab and Browse category, the Media panel's source (footage, project, shared, selects), the open library panel's search and filters, and scroll the timeline to a frame.

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
- `settingsSection`: string, one of general, agents, plugins, storage. Settings section (open Settings with ui.action open settings)
- `settingsSearch`: string. Settings search text: lists matching settings of every section; empty clears it
- `knowledgeSection`: string, one of inbox, lessons, prefs, facts, notes, skills, history. Knowledge window section (open it with ui.action open knowledge)
- `pluginsTab`: string, one of installed, browse, updates, activity. Plugins sheet tab (open it with ui.action open plugins)
- `pluginsCategory`: string, one of all, agents, captions, voice, audio, color, effects, export, utilities. Category Plugins › Browse shows; all shows every one
- `mediaSource`: string, one of footage, project, shared, selects. What the Media panel lists
- `libraryQuery`: string. Search text of the open library panel; empty clears it
- `libraryPack`: string. Pack the open library panel shows; empty shows all
- `libraryTag`: string. Tag the open library panel shows; empty shows all
- `libraryScope`: string, one of all, built-in, user, project, plugin. Scope the open library panel shows

### `bashcut ui seek <frame>`

Move the viewer to a timeline frame.

- Mode: ui · Runs: immediately · MCP: `bashcut_ui_seek`
- `frame`: integer, required, ≥ 0. Timeline frame

### `bashcut ui frame [<frame>] [--width <width>] [--phone]`

Render the viewer's picture at a timeline frame (the playhead by default) to a PNG, like attaching the viewer frame in Ask; returns its path. Read the file to look at the edit. Keeps the ten newest. width renders it that many pixels wide (phone: 390, about a phone screen, to judge text at the size viewers see it); otherwise up to 1280 on the long edge.

- Mode: read · Runs: immediately · MCP: `bashcut_ui_frame`
- `frame`: integer, ≥ 0. Timeline frame; the playhead by default
- `width`: integer, 64…4096. Width in pixels
- `phone`: boolean. 390 pixels wide

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

### `bashcut library add [--kind <kind>] [--name <name>] [--from-result <fromResult>] [--id <id>] [--scope <scope>] [--origin <origin>] [--author <author>] [--tags <tags>] [--pack <pack>] [--params <params>] [--file <file>] [--preview <preview>] [--source <source>] [--license <license>]`

Save a new library item in the project or on this Mac. Files are copied in. Agents saving to the user scope wait for approval. To improve an existing item, use library update. fromResult saves a candidate of a finished library search or library generate job instead (its kind, name, files, source and license; the other fields here override them).

- Mode: edit · Runs: immediately · MCP: `bashcut_library_add`
- `kind`: string, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice. Item kind (required unless fromResult)
- `name`: string. Display name (required unless fromResult)
- `fromResult`: string. A library search or generate candidate as <job>:<index> (index from 0, as the job result lists it)
- `id`: string. Item ID: lowercase letters, digits and hyphens; from the name by default
- `scope`: string, one of project, user, default "project". project (the open project's .bashcut/library; the default) or user (this Mac; agents need approval)
- `origin`: string, one of stock, ai, own, built-in. Where it came from (P2-H8)
- `author`: string. Who made it, for the credit line
- `tags`: string. Comma-separated tags (mood, use, genre…)
- `pack`: string. Pack or collection name the panel groups it under
- `params`: object. What the kind needs (JSON): text-preset {textPreset, text, textStyle: {size, positionY, strokeWidth} (the item property ranges), animation: a clip motion preset}, the last two optional; sticker {emoji, textPreset} or a file (PNG, JPEG, HEIC, WebP, GIF, APNG, or a .mov/.mp4 with alpha; not Lottie) with {stickerKind: emoji|image|animated|video-alpha (from the file by default), size: width as 0.01–1 of the frame, position: center|top|bottom|left|right|top-left|top-right|bottom-left|bottom-right or {x, y} in 0–1, animation: a clip motion preset, seconds}, all optional; effect-preset (a recipe) {steps: [{op: motion|keyframes|speed|speedCurve|reverse|freeze|patch|sfx|text, …}], parameters: {name: {default, min, max}}} or the older {patch: item properties}, with its own sound as file; transition-preset {kind, duration, easing: linear|in|out|inOut, sfx: audio item ID} (or its own sound as file); look (a filter stack) {color: {exposure, contrast, saturation, lutStrength}, lutName} with an optional .cube LUT as file; audio (its file required) {role: music|sfx|ambience, seconds, bpm, loopable, lufs, truePeak}, all optional (library add measures seconds and picks a role by length; library analyze fills the rest), with mood and genre as tags
- `file`: string, path. File to copy in (audio, image or alpha-movie sticker, a look's .cube LUT…)
- `preview`: string, path. Preview image, GIF or audio snippet to copy in
- `source`: string. Where it came from (URL or note)
- `license`: string. License: text as written, or a JSON object {id, redistribute, commercial, attribution…}; stored as given

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
- `license`: string. License: text as written, or a JSON object {id, redistribute, commercial, attribution…}; stored as given
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

Measure an audio library item's file and save the values as a new version: its length, integrated loudness and true peak (an audio.loudness provider, as audio measure), landmarks {onset, peak, tail} in seconds (where it passes the −70 LUFS gate, peaks and drops back under it) and, unless it is a sound effect, its tempo in BPM (an audio.beats provider, as beats detect). Runs as a job; a missing provider leaves that value and says why in notes. Agents saving to the user scope wait for approval. Tag mood and genre with library update --tags after listening or reading the analysis.

- Mode: edit · Runs: as a background job (`jobs wait` until it ends) · MCP: `bashcut_library_analyze`
- `id`: string, required. Item ID, or scope:id to pick one scope
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
- `kind`: string, required, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice. Item kind
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
- `kind`: string, required, one of audio, text-preset, sticker, effect-preset, transition-preset, look, voice. Item kind
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
