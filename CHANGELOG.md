# Changelog

- Set the first TestFlight candidate version to 0.0.1 (build 1).
- Add the Mac App Store category, sandbox entitlements, and BashCut app icon required for TestFlight validation.

## [Unreleased]

- **Faster agent round trips.** `bashcut-mcp` reads and writes stdio without the SDK's 10 ms polling and returns results
  as compact text only (the SDK re-decoded structured results slowly; compact JSON is also about a third fewer
  tokens): MCP calls dropped from 12–45 ms to 2–14 ms. Preview readiness and `ui frame` poll every 10 ms instead of
  100 ms, and the debug log no longer encodes whole results on the main actor. `scripts/bench-automation.py`
  measures it; numbers in `docs/status/implementation.md`.
- **Change the canvas of an open project**: the size in the toolbar is now a menu (Portrait 9:16, Landscape 16:9,
  Square 1:1), also `project format --canvas <c> [--resolution <r>]` and the new `setFormat` operation. One undoable
  edit; timing is kept and clip pan/tilt scale with the frame. Before, a project's format could never change.
- **Viewer zoom**: Fit, 25, 50, 100 and 200% from the viewer header (`ui view --viewer-zoom`); zoomed views scroll.
  Fit leaves a 12-point margin so a 16:9 picture no longer touches the panel edges.
- Fix: text was sized from the frame *width*, so titles grew 1.8× in landscape projects and ran off the frame. Text
  size is now a fraction of the short side (portrait looks the same as before), and a line wider than 90% of the
  frame shrinks to fit.
- The safe-area overlay follows the canvas: TikTok/Reels zones for vertical video, a 90% title-safe frame for
  landscape and square.
- `ui frame` waits for the preview to finish rebuilding after an edit instead of failing.
- Fix: a bad `atIndex`/`toIndex` said "must be an integer frame"; it now says it must be a layer position.
- `docs/reference/commands.md` lists every CLI command and MCP tool with its mode, how it runs and its parameters.
  It is generated from the command catalog (`scripts/update-commands.sh`) and a test fails when it is stale; the
  hand-written tables in the automation guide had fallen behind.
- **`ui frame [frame]`** renders the viewer picture at a timeline frame (the playhead by default) to a PNG and
  returns its path, without moving the playhead, so agents can look at their edits. It is the same capture as
  Ask's *attach viewer frame* (which had no command until now).
- `timeline get` also returns `transitions` and `markers` (sections); the text format adds one `TRANSITION` and
  one `MARKER` line each. Agents could not see the transitions they had added.
- Fix: `bashcut-mcp` sent list and text results (`timeline get --format text`, `review run`, `media list`,
  `ui seek`…) as `structuredContent` (first as the value, then as `null`), which MCP clients such as Claude Code
  reject; they are now text only and the field is left out.
- `clip speed` and `clip speed-curve` report `shortened: true` when a `keepDuration` change still had to shorten
  the clip because its source ran out.
- Fix: a plugin's file option (VieNeu's *Clone voice from*) squeezed its buttons to "C" in narrow panels; the file
  name and *Choose… / Clear File* now sit on their own lines.
- **Speed ramps** (CapCut Curve): Inspector › Speed › Curve and the clip menu offer Montage, Hero time, Bullet
  time, Jump cut, Flash in and Flash out with a preview of the curve; custom points through `clip speed-curve`
  or the `setSpeedCurve` operation. The clip keeps its source and its length follows the average speed; split and
  trim keep the ramp on the same source; linked sound follows; clips show 〰. Built from short scaled pieces, so
  no keyframe system is needed.
- **Reverse**: Inspector › Speed and the clip menu play a video clip backwards (with its linked sound) from a
  reversed copy rendered into the project's `reversed/` folder as a job; *Play Forward* restores the original.
  New `setSource` operation and `clip reverse` command; reversed clips show ◀.
- **Settings › Storage**: sizes of installed plugins, each plugin's data and downloads, the saved plugin catalog,
  this project's preview proxies and the audit log, with *Free Up* for what can be downloaded or made again and
  *Delete…* for a plugin's data (after a confirmation). New `storage get` and `storage clear` commands.
- **Plugin actions for agents**: agent instructions explain list → select → run → `jobs status`; the agent
  session context lists installed actions with their conditions and parameters; and `bashcut-mcp` lists one
  `bashcut_action_<id>` tool per installed action (input schema = its parameters), run through `plugins run`.
- **Core plugin `bashcut.audio-analysis`** ships inside the app (`Contents/Resources/Plugins`): `audio.loudness`
  (BS.1770-4 integrated loudness, EBU loudness range, 4× true peak) and `audio.beats` (spectral-flux onsets,
  autocorrelation tempo, dynamic-programming beats) with AVFoundation and vDSP. Loudness-normalized export and
  **Detect beats** now work without installing anything; installed providers with a higher priority still win.
  Built by `scripts/run.sh` and the Xcode project (`Plugins/audio-analysis/`).
- **Signed plugins**: registry archives signed with ed25519 (over their SHA-256) show *Signed by BashCut* or
  *Signed by <publisher>*; unsigned ones show a warning, and a signature that matches no key is refused. The BashCut
  key is compiled into the app; the registry cannot add first-party keys.
- **Yanked plugin versions**: a registry version marked `yanked` is never offered; users who have it see why, and
  Updates offers the newest good version.
- **Daily plugin update check**: opening a project checks the registry once a day (Settings switch, on by
  default); the Plugins button and menu show how many updates wait. Nothing installs without the user.
- **App Store channel**: sandboxed builds run only the plugins inside the app (no Browse, Updates or Install
  Plugin…, no user or project plugin folders). A bundled plugin now loses only to a higher version of itself.

- Plugins › Browse: the refresh button bypasses GitHub's 5-minute CDN copy of `registry.json`, so a just-published
  plugin shows at once; an empty list now says whether nothing is published, nothing matches or no plugin provides
  the capability yet.
- Fix: releasing the speed slider recorded the change twice, so one undo seemed to do nothing. Setting a clip to
  the speed it already has is no longer an edit.
- **Change speed** like CapCut: a clip's length now follows its speed (2× halves it, 0.5× doubles it) and later
  clips on its layer, and on its linked sound's layer, move with it; "Change clip length" off keeps the old
  behaviour. Linked picture and sound change together, and a clip is shortened to fit its source. Inspector ›
  Speed has presets (0.25×–4×), a slider and a field (0.1×–16×), the clip menu has a Speed submenu, clips show a
  "2×" badge, and **Speed up / Slow down / Reset speed** are editor actions. New `setSpeed` operation and
  `clip speed` command.
- **Plugin preflight**: before the install approval, BashCut probes the plugin's dependencies and labels each one
  *Available on this Mac*, *Installed during setup* or *Not available on this Mac*; a plugin that needs something
  this Mac lacks and cannot install is refused with a plain explanation, and the space estimate counts only what
  is missing. Installed plugins use the same labels instead of raw probe errors. Changing `pluginRegistryURL` no
  longer needs a restart.
- **Plugin install UX** (plugin API 3): dependency recipes run as a job with a progress bar (`::progress` lines),
  output and Cancel, in the plugin's filtered environment and process group; the approval shows the space needed
  and refuses when the disk is too full; **Install Dependencies…** (`plugins setup`) repairs a failed or cancelled
  setup; **Remove with Data** (`plugins remove --data`) also deletes the plugin's `BASHCUT_PLUGIN_DATA` and
  `BASHCUT_PLUGIN_CACHE` folders. Options gain `choiceLabels` and a `file` type with a file panel, and the Voice,
  Text and Audio panels show the selected provider's options. Trust now pins every file in the plugin folder.
  Development builds accept a `file://` registry and relax trust for symlinked dev plugins.
- Plugin providers now receive their plugin's option values as `options` with capability requests (such as the
  voice for `voice.synthesize`), and dependency commands may leave out `arguments`. First provider using this:
  `bashcut.vieneu-tts` (VieNeu-TTS v3 Turbo) in `bashcut-plugins`.
- **Plugin registry**: Plugins › Browse and Updates install and update plugins from the static `registry.json` in
  `dongnguyenvie/bashcut-plugins` (no server). Downloads are checked against the registry SHA-256, unpacked into a
  staging folder, validated and shown for approval before anything runs; updates keep the previous copy until the
  swap succeeds. Installed › Remove uninstalls user and project plugins. Panels without a provider offer
  **Find a plugin…**. New commands: `plugins search`, `updates`, `install`, `remove`. `scripts/run.sh` now writes the
  real app version into the development bundle.
- **Localized plugin text**: plugin `name`, option `title`/`help` and action `title`/`confirm` take a string (English)
  or a language map such as `{"en": "Opacity", "vi": "Độ mờ"}`, replacing the `titleVi` fields. BashCut shows the
  interface language, then the base language, then English.
- **Plugin API 2: actions, hooks, options, sessions and trust.** Plugins can add actions to the Plugins menu,
  toolbar, clip/track/timeline/media context menus, library panels and inspector tabs (`contributes.actions`, with
  `when` conditions, native parameter sheets and shortcuts) and subscribe to 19 editor events
  (`contributes.hooks`: project, edit, selection, playback, import, capability, export and job events; debounced,
  rate-limited and notify-only). A result proposes operations and the plugin's own `pluginData` entry; the app
  validates them and commits one undoable edit by the new `plugin` author. Hook edits wait for review (toolbar
  badge, `plugins proposal`) unless Settings › **Apply plugin hook edits without review** is on; Settings ›
  **Run plugin hooks** stops all hooks. Manifests can declare `options` (per user or per project) and
  `"transport": "session"` for one long-lived NDJSON process with progress and cancel. Plugins now run only after
  the user trusts their exact files (SHA-256 pins; installing pins them) and can be turned off per plugin or per
  hooks; `minApiVersion`/`maxApiVersion` mark outdated plugins. New commands: `plugins actions`, `run`, `hooks`,
  `proposal`, `options`, `option`, `set`; `ui actions`/`ui action` include plugin actions. Example plugin:
  `Fixtures/plugins/example.toolkit`. See `docs/guides/plugins.md`.
- **Adjustment layers** replace the New Project "Style preset" setting, which was stored but never used. An
  adjustment layer (Add Layer › Adjustment Layer, `layers add --kind adjustment`) holds items with only a color
  grade (look, exposure, contrast, saturation, LUT) that applies to every layer below them while they are on screen,
  like adjustment layers in CapCut or Premiere; captions above them stay ungraded and hiding the layer bypasses it.
  Filters › Add adjustment and `adjustment add` add one over the selected clip or 3 seconds at the playhead; a
  look or LUT with nothing selected does the same. New look: Vivid.
- **Style kits** (Filters › Style kits, `style apply`): one undoable edit adds a full-length adjustment with the
  kit's look (replacing an earlier kit's) and sets the kit's preset on every caption; titles, place cards and
  other presets keep theirs.
- **Custom looks and kits** live in the project (`looks`, `styleKits`) and show in the Filters library:
  `looks save` (from an item's grade and/or values), `looks delete`, `style save`, `style delete`. `adjustment add`
  takes `--exposure`, `--contrast`, `--saturation`, `--lut-strength` and `--lut`; commands gained a `number`
  parameter type with ranges published to MCP. `timeline get` lists `luts`, `looks` and `styleKits`.
- **Generated JSON Schema**: `docs/reference/project.schema.json` and `schema get` come from `ProjectSchema`,
  built from the same declarations validation uses (`TrackKind`, `ItemProperty`, `ColorGrade`, `TextPreset`).
  `scripts/update-schema.sh` regenerates it; a test fails when it is stale. `ProjectMigration` is the registry for
  future upgrade steps.
- **Project format reset to `bashcut.project/1`** (nothing is released yet): no migrations; text items use
  `textPreset` instead of `style`; tracks always store `name`; the project-wide `style` field and
  `project create --style` are gone. Agent instructions list color keys and ranges and warn that `setProperties`
  replaces the whole `color` object.

- Agent dock tabs: each tab shows its provider icon, the close button sits inside the tab (shown on hover or
  selection), the selected tab is outlined in cyan, API is a tab like the others, header buttons highlight on
  hover, and the terminal has a small inset instead of touching the dock edge.
- Sample project for contributors: `scripts/sample-project.py` generates synthetic media with ffmpeg and builds
  `build/sample-project/bashcut-sample` through the `bashcut` CLI, with every timeline case (linked clips, LUT,
  reframing, dissolve, freeze frame, 2× speed, gap, 4K HEVC proxy, picture in picture, captions, locked, hidden
  and muted layers, voiceover warning, music with beat grid and ducking, SFX, sections, an agent-changed clip),
  then checks it end to end (`check` re-runs the checks). See `docs/guides/sample-project.md`.
- Validation now rejects a clip's `color.lut` that is not a catalog ID (an object was accepted and then silently
  ignored by the engine).
- Faster playback and timeline drawing: the play controls and time under the viewer are their own view, so the
  editor no longer re-renders every playback frame; the timeline's current time is its own small label instead of
  redrawing the layer header; new filmstrip thumbnails redraw only the visible filmstrip rows; clips look up
  their media by ID; the beat grid is one path. The playhead is only written when it moves, and state used only
  for reference (`timelineGestureActive`, the zoom anchor) is no longer observed by views. The viewer no longer
  publishes itself to Control Center's Now Playing, which polled the player on the main thread during playback.
- The timeline arrow keys are editor actions: `left`/`right` run `playhead.previous-frame`/`playhead.next-frame`,
  and ⇧← / ⇧→ run the new `playhead.back-second`/`playhead.forward-second`, so `ui action shift+right` works.
- A CapCut-style timeline:
  - **Playhead:** a red playhead with a grip that you drag (on the grip, the line or anywhere on the ruler) with a timecode label, snapping and edge autoscroll. ← / → step frames, and playback turns the page.
  - **Hover and dragging:** hovered clips light up with trim brackets and move/trim cursors. Dragging a clip shows a see-through copy where it would land with a closed-hand cursor, a cyan target line, a yellow snap line, and a label with the new start, duration or change.
  - **Clips:** durations on clips; filmstrip thumbnails on the taller main layer (from proxies when present); clearer colors per layer and icons instead of emoji.
  - **Clip menu:** right-click Split, Delete, Lift, Freeze frame, Change framing, Unlink audio and Lock layer (new actions `clip.freeze`, `clip.change-framing`, `clip.unlink-audio`).
  - **Gaps:** hatched gaps on Main that can be selected and deleted (`timeline close-gap`).
  - **Drop media:** drag from the Media and Audio panels or from Finder onto a layer.
  - **Layer header:** pinned on the left with hide, mute and lock switches (`layers set`). Hidden layers leave preview and export, muted layers are silent and stop ducking music, and locked layers refuse edits.
  - **Performance:** the playhead, guides and labels are separate overlay views, so playback and scrubbing no longer redraw the whole timeline.
  - **Behavior change:** clicking a clip now selects it without moving the playhead.
- Timeline zoom works like CapCut: pinch on the trackpad or ⌘ + scroll zooms around the pointer, the buttons and ⌘= / ⌘− zoom around the playhead, and the frame under the pointer or playhead stays in place instead of the view jumping. The slider is logarithmic, zoom now ranges from 1 to 600 pixels per second (a whole long video down to single frames, with frame ticks on the ruler), and a new **Zoom to fit** button (⇧Z in the timeline, `timeline.zoom-fit`) shows the whole timeline. `ui view --zoom` accepts the new range and `--zoom-anchor <frame>`.
- Reorganize and rewrite the documentation: `docs/README.md` is the index; guides (`docs/guides/automation.md` with the full command list, `docs/guides/plugins.md`), reference (`docs/reference/project-format.md`, `docs/reference/third-party.md`), status (`docs/status/implementation.md`, `docs/status/mockup-parity.md`) and the design specs, all brought up to date with the code. `docs/extension-boundaries.md` is folded into the architecture spec.
- Open projects from Finder: double-click or **Open With → BashCut** on a `project.bashcut.json`, or drop the file or its project folder on the Dock icon, whether or not BashCut is running. BashCut is listed as an alternate app for JSON files and folders, never the default. Unsaved changes still get the discard prompt.
- M0 accepted on real DJI footage: `bashcut-bench` now measures scrubbing the way the viewer does (AVPlayer exact seeks) and can preview through proxies (`--proxies`); 20 HEVC clips play with no dropped frames, scrub at p95 19.6 ms (8.9 ms with proxies) and export at 9× real time (results in `docs/status/implementation.md`). The viewer scrubs with chase-time seeking: while one exact seek decodes, newer playhead positions only replace its target, so dragging never queues stale frames.
- Make preview proxies for heavy footage (M-5). Importing HEVC, larger-than-1920 px or high-bit-rate video now queues a small H.264 copy (at most 960 px, a keyframe every 10 frames, same frame times) in `.bashcut/proxies`; proxies are made one at a time in the background, the viewer switches to each one as it is ready and exports keep using the originals. `media proxy [MEDIA_ID] [--force]` and the Media panel's **Create Preview Proxy** menu make one by hand, the media tile shows "Proxy" or "Making proxy…", and `media list` reports each media's proxy state (46 tools).
- R6, contributing guide: `CONTRIBUTING.md` explains the build layout and gives a one-file template (with its registry and test) for agent providers, model adapters, commands and UI actions, plugin capabilities and timeline formats. R6 is done, which completes the refactor plan.
- R6, build and tests: `Package.swift` is the single source of targets and `project.yml` links its library products instead of redeclaring the core modules; `scripts/verify.sh xcode [build|test]` builds or tests the generated Xcode project. Tests are split into one target per module (`Tests/BashCut<Module>Tests`, and Project/Plugin/Import/Interchange in the core package) with shared fixtures (`BashCutTestSupport`, `BashCutProjectFixtures`) and an apply→undo→redo round trip for every edit operation. The core package no longer declares the unused snapshot-testing dependency, so `swift test` stops rewriting its `Package.resolved`.
- R5c: timeline formats are `TimelineExporter`s (OpenTimelineIO, SubRip) and `TimelineImporter`s (legacy edl.json) listed in `TimelineFormats`; OTIO export and EDL import go through them. The import report sheet is generic (`TimelineImport`: counts, mismatch note, warnings) and `edl import` adds `sourceDuration` to its report. R5 is done.
- R5b: the engine reads media through a `MediaSource`. `ProxyMediaSource` (the default) uses `.bashcut/proxies/<media id>.mov|.mp4` for preview when present and always the original for export; `RenderEngine.build` takes a `purpose`. `CompositionBuilder` now keeps opened assets and their loaded tracks across builds (up to 64, least recently used dropped, reloaded when the file's date or size changes), so preview rebuilds after an edit no longer reopen every clip.
- R5a: plugin capabilities are `CapabilityAdapter`s (transcription, beats, loudness, voice synthesis, one file each) run by `CapabilityService.run`, which owns validation, provider resolution, the request folder and provenance. Plugin calls go through a `PluginTransport` protocol (the process runner is the one-shot transport), so tests and future session transports plug in without changing the service.
- `scripts/run.sh` signs `build/BashCut.app` with a stable identity (`BASHCUT_SIGN_IDENTITY`, else the first Apple Development identity; ad hoc with a warning when there is none), so macOS stops asking for Desktop folder access after every rebuild. SwiftPM resource bundles now go in `Contents/Resources`.
- R4b, step 1: move editor view state (timeline zoom and reveal, snapping, safe area, agent dock, library panel, Inspector tab and every editor sheet flag) out of `ProjectDocument` into a tested `EditorUIState` in `BashCutDocument`; `LibraryTab` moves there too, and its match with the `ui.panel` choices is now a test instead of a startup assert. No behavior change.
- R4b, step 2: the viewer (program and comparison players, playhead, composition rebuilds, color compare) moves into `PreviewController` in `BashCutDocument`, tested with a counting fake engine.
- R4b, step 3: `ExportController` in `BashCutDocument` owns the export queue, the last export report (moved into the library with its `export.status` JSON), export history, the loudness project patch and OTIO writing; the document keeps only panels, messages and the edit.
- R4b, step 4: `FileSyncController` in `BashCutDocument` owns saving against the last bytes read, autosave, the folder watch and disk-conflict state; the document applies the reloads it reports. Tests cover saves, outside edits (reload and conflict) and conflict resolution.
- R4b, step 5: `SettingsModel` in `BashCutDocument` holds Settings preferences (workspace, default agent, agent edit and external-agent switches, export auto-approval, default export preset, interface language) and recent projects. Each change is saved at once under the existing `UserDefaults` keys, so current preferences carry over.
- R4b, step 6: `AutomationController` in `BashCutDocument` owns the command registry with its audit log, the socket server and the external-agent token file; the document registers its handlers on it. `CommandRegistry.author(for:)` reports who a token edits as.
- R4b, step 7: `AppServices` (render engine, settings, automation endpoint) is the composition root; `AppServices.live()` builds the app's and `ProjectDocument(services:)` creates its per-project controllers from it. R4 is done: `ProjectDocument` went from 64 to 28 stored properties and keeps history, the single `commit` and the command handlers.
- Replace the agent dock's "Resume session ID" field with **Continue Claude/Codex** and **New conversation** buttons; BashCut keeps finding and saving the last conversation per project on its own, and users never see session IDs.
- Fix fixed-size sheets (Plugins, Doctor, History, agent changes, external changes, skills and memory) floating their content in the middle when it is short; content now starts at the top and the empty Plugins state fills the sheet.
- Fix the Media panel's source picker label wrapping one word per line in the narrow library panel.
- Close the remaining UI-only gaps: `luts import` (Filters, Import .cube…), `edl import` (Welcome, Import from edl.json…), `project recents`, `doctor run`, `plugins health`, `knowledge get` / `knowledge memo` / `knowledge skill`, and `voice speak --keep-takes` to keep every take and place the chosen one. New actions: show/undo/dismiss the agent change notice, open or reveal the last export, clear recent projects; `ui view --inspector` switches Inspector tabs (45 tools).
- Fix a crash when importing a .cube LUT: the copy combined `.atomic` with `.withoutOverwriting`, which Foundation rejects with a trap.
- Fix the app no longer answering automation requests while an agent-started open panel or alert was showing (`ui action cmd+o`).
- Let agents do everything the editor's buttons and shortcuts do: every toolbar button, menu item and keyboard shortcut is a `UIAction` (ID, title, shortcuts) that the views bind to and `ui action <id|shortcut>` runs through the same code (`ui action cmd+b` splits, `ui action timeline.zoom-in` zooms). `ui actions` lists them with their shortcuts and enabled state. `ui view` reads and sets timeline zoom, snapping, safe area, color compare and the agent dock, and scrolls the timeline to a frame (`--reveal`). `ui source <media>` opens the source viewer with in/out marks, and `ui select --track` selects a layer (37 tools).
- Add ⌘= / ⌘− and zoom buttons to the timeline; Delete, Shift-Delete and `s` in the timeline are listed actions too.
- `context get` reports `dirty`, `conflict`, `busy`, `saving` and the selected layer; `ui open external-changes` shows the disk-conflict sheet. Boolean CLI options accept `on`/`off`.
- Agents can no longer approve a plugin install from the `plugin-install` sheet; like export approval, they can only cancel it.
- `export status` describes the running export while one renders (`job`, `step`, `progress`, `preset`, `path`, `includedSRT`), with the previous receipt under `lastExport`; exports no longer write an empty `.srt` when the timeline has no captions.
- Rewrite older `../../…` media paths that point into the project's linked `footage` folder (or any top-level folder link) to `footage/<file>` when a project opens, as one undoable "Relink media paths" edit that is saved with the project.
- Let agents drive every dialog like the user: all alerts and open/save panels go through `ModalCenter`, and every sheet and popover is reported too. `ui dialog` lists open dialogs with stable option IDs, `ui respond <option> [--path <file>]` answers the topmost one (a path fills a file panel), and `ui open <dialog>` shows a sheet such as Settings, Export or Doctor. The export approval sheet can only be declined by agents; approving stays with the user unless confirmation is turned off in Settings (33 tools).
- Add a Settings switch, "Run agent exports without confirmation" (off by default), that runs privileged agent commands (`export start`, `export otio`) at once instead of showing the approval sheet; they answer `approval: "approved"` and are audited as auto-approved. Only the user can change it in Settings.
- Queue exports in the background (E-1): starting an export while one renders queues it instead of refusing, in the app and through `export start`. Exports render one at a time from the project as it was when requested; the status bar shows the current step, progress and queued count, `export status` lists the queue with job IDs, and `jobs status`/`jobs cancel` now cover exports as well as plugin jobs.
- Add the `BashCutDocument` library with `JobCenter` (one job list for capability calls and exports), `ExportRequest`, `ExportPipeline` and `ExportQueue`, covered by tests with a fake render engine.
- Make agent terminals and model APIs pluggable: each terminal program is an `AgentProvider` (Claude, Codex, Shell) and each model API a `ModelAdapter` (Responses, Chat Completions, Anthropic), registered once; the dock menus, Settings picker, resume bookmarks (now keyed by provider ID, same file format) and session discovery come from the registries.
- Launch terminals with an allowlisted environment instead of the whole app environment: locale, home, proxy and certificate variables plus each provider's own (`CLAUDE_*`, `CODEX_*`, `OPENAI_API_KEY`); Claude still never receives `ANTHROPIC_API_KEY`.
- Store media picked from the linked `footage` folder (or any top-level folder link) as `footage/<file>` instead of a `../../…` path into the link's target, so projects keep working when moved with their footage link.
- Add `project create`, `project open` and `project save` CLI/MCP commands sharing the wizard, open and save code; they never show modal dialogs and refuse to drop unsaved work without `--save-current` or `--discard-current` (30 tools).
- Let agents outside BashCut edit without copying a token: the app writes a 0600 automation token file that the CLI and MCP read automatically, attributed to a new `agent` author that survives project switches; a Settings switch turns it off or rotates it. Exports still require in-app approval.
- Keep overflow layers in creation order (after the last layer with the same role), add new video layers behind text layers, and name the moved layer in band errors.
- Add an Edit menu (Cut, Copy, Paste, Select All) so ⌘X/⌘C/⌘V/⌘A work in text fields and the embedded Claude, Codex and Shell terminals, and a Copy/Paste/Select All right-click menu on terminals.
- Add a `media import` CLI/MCP command that adds a media file through the same probe as the Import button and can place it on a layer (27 tools).
- Add a shared debug log (`~/Library/Logs/BashCut/debug.log`) written by the app, CLI and MCP bridge: launches, project opens and layer repairs, committed and rejected edits, layer placement decisions, media imports, timeline gestures and automation requests.
- Make each left-rail library tile clickable across its whole area, not only on the icon and label, and add a `ui panel` CLI/MCP command to open a panel (26 tools).

- Enforce layer rules in core validation: visual layers stay above audio layers, exactly one undeletable main layer, no overlapping items on one layer, and no audio media on visual layers. Older projects are repaired when opened.
- Place and move clips CapCut-style through a shared `LayerPlanner`: an occupied range spills onto the next free layer of the same role or a new layer next to it, with linked sound following. Imports, the library, timeline drags and overlapping SRT cues all use it.
- Add `layers add`, `media place` and `timeline move` CLI/MCP commands (25 tools) backed by the same code as the UI.
- Fix the layer up/down buttons moving audio layers the wrong way on screen, and keep layers inside their visual or audio band.

- Declare every automation command once in `CommandCatalog.specs` (name, mode, parameters, CLI binding, sync/job/approval). The registry validates requests against the spec before handlers run (types, ranges, choices, defaults, unknown parameters); handlers are `async`. The `bashcut` CLI parser, the 22 MCP tools and the agent instructions are generated from the same specs, and a consistency test guards them.
- Fix `bashcut_timeline_apply` rejecting calls without `label`: the schema now advertises the `"Agent edit"` default and the server applies it.
- Agent instructions no longer name fixed track IDs (`v1`, `t1`); they tell agents to read track IDs and roles from `bashcut timeline get`. `bashcut help` lists every command's usage, and CLI argument errors print that command's usage.

- Route every history mutation (UI, automation, model API, captions, LUTs, generated results, external reloads) through one `ProjectDocument.commit` that enforces conflict/busy/revision rules and records agent diffs consistently; `history` is now read-only outside that choke point.
- Look tracks up by role (`Project.track(role:)`, `TrackRole`, `placementOperations`) instead of fixed `v1`/`t1`/`a2`/`a3`/`a4` IDs, so renamed, reordered or added layers keep working; the audio library lists the project's real audio tracks.
- Serialize `EditOperation` in one `"op"`-keyed codec in core, shared by agents, model APIs and the history journal. Journals written by earlier builds are discarded with the existing "History could not be restored" warning; project files are unchanged.
- Cap undo history at 200 steps, hide the `Deque` storage behind `canUndo`/`undoEntries`/`lastUndo`, and expose snapshot inverses through `HistoryEntry.before`.

- Make plugin calls cancellable without blocking Swift's cooperative pool: providers start in their own process group, cancellation and timeouts terminate the whole group, including helpers they spawned.
- Serve automation clients concurrently on a dedicated accept thread and client queue, so an idle or slow client no longer stalls other agents.
- Merge continuous Inspector input (slider drags, typing) on the same field into one undo step through history coalescing in core.
- Add `docs/specs/10-refactor-plan.md` with the structural audit and refactor rounds R0–R6.

- Route every plugin call through a shared `CapabilityService` module used by the Voice, Text and Audio panels, normalized export and automation, so provider resolution, health checks, output confinement and provenance are identical for users and agents.
- Add authenticated `captions generate`, `beats detect` and `voice speak` CLI/MCP commands that run as cancellable background jobs and apply one undoable agent-attributed edit, plus `plugins list` and `jobs status/cancel` (22 MCP tools).
- Use `grep` instead of ripgrep for `scripts/verify.sh` failure summaries, since ripgrep is not a required tool.

- Persist the latest 20 export metric reports per project, restore the latest report after reopen and compare duration, size, cuts, captions, tagged speech coverage and LUFS with the previous export in UI and automation status.
- Discover matching local Claude and Codex sessions without loading full histories, persist their IDs per canonical project and automatically bookmark newly launched terminal sessions.
- Record voiceover directly from the macOS microphone as a project-local 48 kHz mono WAV, show elapsed time and input level, validate it and insert it undoably at the playhead.
- Attach a bounded current-viewer PNG from ⌘K to Claude/Codex terminals by local path or to configured model APIs using provider-native multimodal request bodies.
- Let the Agent dock detach into a resizable window while preserving live Claude, Codex, Shell and API sessions, then reattach cleanly when the project closes.
- Show red timeline badges when voiceover is less than 0.3 seconds from tagged speech, with the same layer-aware rule exposed through Review and agents.
- Add an undoable Preserve Audio Pitch speed control, using AVFoundation spectral processing or intentional varispeed in both preview and export.
- Add rendered Place Card, Hook Title and Chapter Card presets to the Text library and Inspector, sharing the same cached Core Text output in preview and export.
- Add a synchronized Viewer Before/After split backed by a non-mutating comparison composition that bypasses color adjustments and LUTs.
- Add deterministic Wide/Medium/Close/left/right Change Framing presets in core and Inspector, using the same validated properties available to agents.
- Add optional provider-based two-pass loudness normalization: measure a temporary mix, apply target gain with a −1 dBTP ceiling, verify the final export, persist mix gain/provenance undoably and expose results through UI, CLI and MCP status.
- Add a three-take Voice workflow with provider-scored or pacing-scored results, isolated audio preview, best-take selection, legacy single-output plugin compatibility and cleanup of discarded generated assets.
- Add frame-accurate automatic music ducking under tagged Dialogue and Voiceover, with track-level level/attack/release controls and one shared preview/export gain envelope that composes with clip fades and volume.
- Add an external-change comparison sheet covering project settings, media, tracks and stable timeline-item additions, removals and modifications before choosing which version to keep.
- Add Footage, Project and Shared media-source filtering with symlink-aware footage classification.
- Add modular legacy `edl.json` import with cut, timing, picture-borrow, dialogue, transform, tag, split-subtitle, voiceover and section mapping plus a post-import comparison report.
- Add modular OpenTimelineIO export with overlap-preserving lanes, gaps, text generators, markers, speed effects and BashCut metadata, available from UI and privileged CLI.
- Add stable undoable dissolve, whip, blink, zoom, spin, shutter and wipe transitions rendered identically in preview/export, with UI duration controls and agent operations.
- Add project-scoped `.cube` 3D LUT import/catalog, validated and undoable clip application/strength, agent operations and shared Core Image preview/export rendering.
- Add an embedded `bashcut-mcp` stdio server using the official MCP Swift SDK, with 16 structured tools and ephemeral Claude/Codex session configuration over the existing authenticated automation socket.
- Add stable, undoable section markers with an editable timeline band, boundary dragging and Claude/Codex wire operations.
- Record and display source resolution, frame rate, duration and audio presence, with offline media badges.
- Add reciprocal linked A/V items for video sound, atomic paired move/trim/split/slip/roll/delete, Inspector unlinking and agent wire support.
- Add deterministic magnetic Main-track reorder with linked Dialogue synchronization and agent wire support.
- Add debounced media hover-scrubbing, event-driven project-file monitoring and rendered freeze frames controlled from the Inspector.
- Persist separate Claude/Codex resume bookmarks per project and add context handoff between embedded terminal providers.
- Resolve `@assets/...` media consistently through the configured workspace with traversal confinement across library, plugins, preview and export.
- Added a first-launch welcome screen with persistent recent projects and stale-file cleanup.

- Upgrade projects to schema v2 with dynamic ordered video/image, text and audio layers, layer controls, vertical timeline scrolling and compositor ordering across text/video tracks.
- Reuse AV assets and composition lanes when building large timelines.
- Add before/after agent diffs, ◆ markers, Undo/Show Changes UI and history restoration for Claude, Codex and model API edits.
- Add Agent Knowledge for shared project memo and skill management across Claude and Codex.
- Launch Codex idle on GPT-5.6-Luna/low with a socket-scoped permission profile and a stable app-support workspace, avoiding security-scoped project-directory stalls.
- Add an out-of-process plugin manifest/catalog, a reviewed installer for optional capabilities and dependencies, dependency health checks and a bounded process RPC runtime with a filtered environment.
- Connect the Voice panel to replaceable `voice.synthesize` providers with project-level selection, output confinement, audio validation, provenance and undoable insertion.
- Connect Auto Captions to replaceable `captions.transcribe` providers with source/language input, confined SRT output, provenance and atomic replace or append.
- Add replaceable `audio.beats` detection, validated undoable beat grids, timeline rendering, beat snapping and agent wire support.
- Add persistent Settings for workspace, default agent, agent edit permission, export preset and UI language, plus Doctor checks for agent CLIs, the automation socket, project structure and plugin health.
- Add capability-based provider declarations and undoable project overrides so voice, transcription and other optional providers can be replaced without changing feature code or timeline data.

- Add mockup-based export options for TikTok, YouTube 1080p/4K, Quick Draft and ProRes, with real bitrate/container settings, background progress/cancellation, optional SRT, post-export receipts and `bashcut export status`.
- Add token-gated `bashcut export start` for embedded Claude/Codex/Shell sessions, with a concrete in-app approval sheet; denied requests write nothing and approved requests use the normal export pipeline.
- Add a native New Project wizard with canvas/resolution/FPS, content language, style, destination and optional footage reference. Publish complete folders without overwriting existing paths; preserve the open document on failure.
- Document functional gaps against the HTML mockup in docs/status/mockup-parity.md.

- Add off-main-actor stereo waveform analysis and bounded memory/disk caching, timeline peak drawing aligned to source trim/speed, refresh/progress/error controls and generated-audio regression tests.
- Fix waveform invalidation by reading fresh file attributes instead of cached URL metadata.

- Add UTF-8 SRT import/add/replace/export to the Text library and CLI, with frame conversion, bounded parsing, one-step undo and subtitle regression tests.

- Add atomic rolling trims and source slips in core, Inspector, timeline gestures and agent wire commands; Shift-Delete lifts without ripple. Add mixed-FPS, bounds and undo regression tests.

- Rebuild the native editor around the mockup: library rail, source viewer with In/Out and insert/overwrite, Inspector tabs, scroll/zoom/snap/drag timeline, safe area, review and history.
- Add text presets, emoji text stickers, color/opacity/audio controls, render-value validation and regression coverage for source placement.
- Add SwiftTerm Claude/Codex/Shell sessions, authenticated local socket, bundled CLI, author badges, atomic API edits and metadata-only audit records.
- Add configurable Responses/Chat Completions/Anthropic model clients, Keychain credentials, editable Python/Shell generation and explicit script execution.
- Fix the app/CLI executable collision on case-insensitive macOS disks, thumbnail layout, timeline hit testing after scroll, and stale model generation handling.
- Expand English/Vietnamese resources and refactor command/render/edit functions for strict SwiftLint.

- Bootstrap the separate BashCut repository, XcodeGen configuration and SwiftPM build path.
- Add lossless schema-v1 project data, validation, atomic edits, revision checks and session undo/redo.
- Add a native editing harness and shared AVFoundation compositor for reframing, Vietnamese captions, audio and H.264 export.
- Add core and engine tests, generated media fixtures and verification scripts.
- Add M1 project persistence: autosave/recovery, saved undo/redo, external-file reload/conflict handling and storage tests.
