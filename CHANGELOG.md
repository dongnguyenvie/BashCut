# Changelog

## [Unreleased]

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
- Document functional gaps against the HTML mockup in docs/mockup-parity.md.

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
