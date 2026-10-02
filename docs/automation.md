# Automation and model connections

The app starts a local JSON-RPC server. The bundled `bashcut` executable controls the open document through the same validated EditOperation/history path as the UI.

## Terminal dock

Use **Agent → + → Claude terminal / Codex terminal / Shell terminal**. Each tab is a real SwiftTerm terminal. Claude and Codex use their installed CLI and existing login. Choose a workspace before opening a tab; when BashCut has found the last Claude or Codex conversation for the project, the dock offers **Continue Claude/Codex** or **New conversation** (users never see or type session IDs). Opening a different project closes existing sessions and revokes their edit tokens. Context and quick actions paste text for review before Enter. Codex starts idle on GPT-5.6-Luna with low reasoning effort. Its process uses `~/Library/Application Support/BashCut/agent-workspace` as a stable working directory; the selected project path and project knowledge still arrive through the session context.

The ⌘K popover can attach the current viewer frame. BashCut renders a bounded PNG into `.bashcut/agent-context`, keeps the ten newest frames and passes its absolute path to local terminals. Model API mode sends the same pixels through the provider-native image payload for OpenAI Responses, compatible Chat Completions or Anthropic Messages; images are limited to 5 MB.

The app also embeds `bashcut-mcp`, built with the official MCP Swift SDK. Each Claude/Codex launch receives a temporary stdio server definition that inherits only the live session environment; no MCP config or token is written into the project. Thirty `bashcut_*` tools cover context, project lifecycle (create, open, save), timeline, media, layers, review, captions, UI (selection, seek, library panel, notifications), undo/redo, app-approved exports, plugin listing and provider-backed caption, beat and voice jobs. They forward to the same Unix socket handlers as the CLI, so permissions, revision checks, audit and undo behavior are identical. The CLI remains available when a client changes its MCP configuration format.

Every command is declared once in `BashCut/Core/Automation/CommandCatalog.swift` as a `CommandSpec`: name, permission mode, parameters (type, range, choices, default, CLI binding) and whether it runs immediately, as a background job or after in-app approval. The socket registry validates every request against its spec before the handler runs, so the CLI, MCP and model APIs get identical errors. The CLI parser, the MCP tool list and schemas, and the agent instructions are all generated from the specs; `bashcut help` prints every usage. Adding a command means adding one spec and one `handle`/`handleAuthored` registration in `ProjectDocument`; debug builds assert that every spec has a handler, and `CommandSpecTests` checks names, schemas and CLI bindings. Export presets are strict: `tiktok`, `youtube-1080`, `youtube-4k`, `quick-draft` or `prores`.

Layer commands follow the layer rules in `docs/specs/02-project-format.md`:

```bash
bashcut layers add --kind video --role overlay --name "B-roll 2" --base-rev 12
bashcut media import /path/to/clip.mp4 --place --base-rev 12
bashcut media place --media MEDIA_ID [--track TRACK_ID] [--at-frame 90] --base-rev 13
bashcut timeline move ITEM_ID --track TRACK_ID --at-frame 120 --base-rev 14
```

`media place` and `timeline move` use the same planner as the timeline UI: when the range is taken, the clip goes to the next free layer of the same kind and role, or to a new layer next to the target, and linked sound follows onto a dialogue layer. Both return the layer actually used. Raw `timeline apply` insert/move operations that would overlap are rejected.

The app adds its bundled CLI to PATH and supplies BASHCUT_SOCKET, BASHCUT_PROJECT and an in-memory BASHCUT_SESSION_TOKEN to each child process. Codex receives a named permission profile that allows its stable workspace plus the exact BashCut Unix socket; it does not receive a broad socket allowlist. Keep tokens out of scripts, logs and project files. Closing a tab revokes its token. Shell sessions are attributed to the user; Claude/Codex sessions have their own authors.

## Available commands

```sh
bashcut context get
bashcut project get
bashcut media list
bashcut timeline get --format text
bashcut review run
bashcut export status
bashcut export start --preset quick-draft --name draft-v1 --include-srt --normalize-audio
bashcut export otio --name timeline-v1
bashcut ui select ITEM_ID
bashcut ui seek 30
bashcut ui notify 'Finished checking the timeline'
bashcut timeline apply /absolute/path/ops.json --base-rev 12 --label 'Trim opening'
bashcut timeline undo --base-rev 13
bashcut timeline redo --base-rev 14
bashcut plugins list
bashcut captions generate --media MEDIA_ID --replace
bashcut beats detect --media AUDIO_MEDIA_ID
bashcut voice speak 'Xin chào các bạn' --takes 3 --at-frame 120
bashcut jobs status JOB_ID
bashcut jobs cancel JOB_ID
```

Read/UI commands are available to local processes under the same OS account. Edit commands require a live session token and base revision. The server rejects stale edits, file conflicts, busy operations and active timeline gestures. Retry after re-reading the timeline. Each apply is atomic and creates one undo step. Review currently checks timeline structure and tagged speech coverage; it does not measure audio loudness or silence.

`export start` requires a live Claude/Codex/Shell session token. It returns an approval request ID immediately and shows a sheet in the app with the author, preset, output path, caption behavior and normalization choice. Denying writes nothing. Approving starts the same background pipeline used by the Export sheet. Presets are `tiktok`, `youtube-1080`, `youtube-4k`, `quick-draft` and `prores`; output defaults to the project's `render/` folder and can be changed with `--output-dir`. `--normalize-audio` requires an installed healthy `audio.loudness` plugin and runs the two-pass target/true-peak workflow.

`export status` reports idle/running/completed state, progress and the most recent receipt (path, preset, duration, bytes, cuts, captions and companion-SRT state). Agents should poll it after an approved request. A normalized receipt also includes `lufs`, `truePeakDbTP`, `normalizationGainDb` and whether the final measurement was verified; non-normalized exports return `lufs: null`.

`export otio --name timeline-v1` writes OpenTimelineIO JSON to the project `render/` directory after the same in-app approval used for privileged video exports. Use `--output-dir` to choose another folder. The exporter preserves integer-frame timing, source ranges and rates, layered overlaps, text generators, section markers, speed effects and BashCut metadata.

`captions generate`, `beats detect` and `voice speak` need a live session token. They call the same `CapabilityService` as the Text, Audio and Voice panels, so provider resolution, health checks, output confinement and validation are identical. Each returns `{"job": ID, "state": "running"}` immediately; poll `jobs status ID` until it reports `completed` (with `rev`, plus `bpm`/`beats` or the inserted voice `item`, its score and all take scores), `failed` or `cancelled`. The result is one undoable edit attributed to the agent, with ◆ markers and the Undo toast. `--provider ID` overrides the project preference for one request. A capability that is already running (from the UI or another job) is rejected with a retry error. Opening another project cancels and clears all jobs. Installing plugins or running their dependency recipes is never available through automation.

`ops.json` is an array (up to 1,000 operations):

```json
[
  {"op":"split","item":"clip-1","atFrame":30,"newID":"clip-right"},
  {"op":"setProperties","item":"clip-right","patch":{"transform":{"zoom":1.2}}}
]
```

Supported operations include insert, delete, split, trim, roll, slip, move, setProperties, layer operations, provider preferences, beat grids, `upsertSection`, `deleteSection`, `addColorLUT` and `deleteColorLUT`. Frames are integers. `atFrame` and `toFrame` are absolute timeline frames; an item's `in` is a source frame at that media's FPS. Section and LUT IDs remain stable. LUT catalog entries use a project-relative `luts/*.cube` path and a 3D size from 2 through 64. Apply a catalog LUT through `setProperties` using `color.lut` and optional `color.lutStrength` from 0 through 1. Property patches replace the supplied top-level keys, so preserve existing nested fields when changing color, transform or tags. Invalid render values, unsafe LUT paths, duplicate section boundaries, missing media, source overruns and Main overlaps are rejected. Source-viewer insert/overwrite plans a group of these same operations.

Transitions use `upsertTransition` with stable `from`/`to` clip IDs, a rendered kind (`dissolve`, `whip`, `blink`, `zoom`, `spin`, `shutter`, or `wipe`) and integer-frame `duration`. The clips must be adjacent on one video track. Use `deleteTransition` to restore a hard cut; moving or deleting either clip automatically removes a transition that no longer describes a valid cut.

The socket defaults to `~/Library/Application Support/BashCut/automation.sock` (override with BASHCUT_SOCKET). Directory permissions are 0700 and the socket is 0600. Newline-delimited JSON-RPC 2.0 requests carry `id`, `method`, `params` and optional `token`. One request per connection, 8 MiB messages, 10-second I/O timeout. Metadata-only audit records are written to `~/Library/Application Support/BashCut/audit.jsonl`; request contents and credentials are excluded. This is a local automation service, not a security boundary against other software already running as the same user.

## Model API / script generation

The **API** tab supports OpenAI Responses, OpenAI-compatible Chat Completions, and Anthropic Messages. Enter a base URL and the provider's model ID. HTTPS is required except for local HTTP endpoints; redirects are refused. API keys are stored in macOS Keychain when **Save connection** is used. Nonsecret settings are in UserDefaults. No model or key is hardcoded.

Choose **Script** (Python/Shell) or **Timeline edit**, write a request, and choose whether project context is included. Generate sends text context and the request to the configured endpoint; it does not upload original video. Output is editable before use. Scripts can be saved or explicitly run in a new local Shell tab after reviewing the confirmation. Timeline proposals apply as one `model` undo step against the revision used to generate them. New generations clear old output; cancelling or switching projects invalidates in-flight results.

## Verification and remaining work

Automated tests use fake model transports and temporary sockets, without paid API calls. Native Shell smoke tests verified CLI reads, authenticated caption edits, visible updates and one-step undo. A real authenticated Codex smoke test on GPT-5.6-Luna/low verified idle startup, context/timeline reads, an atomic caption edit through the allowlisted Unix socket, revision advancement, Show Changes and undo. Claude and remote model API end-to-end tasks remain unverified.

The dock stores Claude and Codex resume IDs per project and can hand current context between providers. It discovers matching local session metadata in a bounded background scan and records newly launched terminal sessions automatically; manual IDs remain editable. Voice-enrollment approval flow and the remaining command catalog are still outstanding. Provider-backed jobs are covered by service tests with fake plugins; an end-to-end agent run against a real provider is not yet verified. Run one BashCut instance per socket.

Protocol references: [OpenAI text generation](https://developers.openai.com/api/docs/guides/text), [Claude CLI reference](https://code.claude.com/docs/en/cli-reference), [Codex CLI reference](https://developers.openai.com/codex/cli/reference), [Anthropic Messages](https://platform.claude.com/docs/en/api/messages/create).

### Advanced trims

`{"op":"roll","item":"ID","edge":"end","toFrame":75}` moves the shared cut with exactly one adjacent clip. Both clips must remain nonempty and within source bounds; the rest of the track and total duration stay fixed. `edge:"start"` uses the preceding clip.

`{"op":"slip","item":"ID","sourceIn":100}` sets an absolute source-frame start without changing timeline position or duration. It rejects text items and source overruns. Both edits use normal revision checks and one-step undo.

In the timeline, Option-drag an edge for Roll, Command-drag a media clip body for Slip, and Shift-Delete for Lift. Inspector has explicit Roll buttons and a source-frame input. Escape cancels the active drag. A revision change during a gesture rejects that gesture instead of applying it to newer state.

### SubRip captions

`bashcut captions import /path/captions.srt --base-rev N` appends cues. Add `--replace` to replace the caption track atomically. Import needs a live edit token; stale revisions and malformed files leave existing captions untouched.

`bashcut captions export --format text` writes SRT to stdout; redirect it to a file when wanted. This read command does not change the project. The Text library exposes the same import/add/replace and export workflows.

Input is UTF-8, at most 4 MiB and 10,000 cues. BOM, CRLF, multiline text and comma/decimal milliseconds are supported. Timing rounds to the nearest project frame; reversed, out-of-bounds or subframe cues are rejected. Export sorts cues and retains Unicode text; paragraph gaps collapse to single line breaks because blank lines delimit SRT cues. Inline markup remains literal text; rich caption styling stays in the project format. The Text panel can request SRT from an installed `captions.transcribe` plugin; no transcription engine is bundled.

## Projects and agents outside BashCut

`bashcut project create --name NAME --dir PARENT [--footage DIR] [--canvas portrait] [--resolution 1080] [--fps 29.97]` builds the same folder as the New Project wizard and opens it. `bashcut project open PATH` accepts `project.bashcut.json` or its folder, and `bashcut project save` writes the open project. Open and create never show the discard dialog: when the open project has unsaved changes they fail unless `--save-current` or `--discard-current` is given. Path parameters are made absolute against the CLI's working directory.

Agents outside BashCut's terminals (Claude Code in another terminal, scripts, other MCP clients) need no copied token. While BashCut runs, it writes a fresh token to `~/Library/Application Support/BashCut/automation-token` with mode 0600, next to the 0600 socket, so it grants nothing beyond what can already open the socket. The CLI and `bashcut-mcp` read it when `BASHCUT_SESSION_TOKEN` is not set. Edits through it are attributed to `agent` and get the same diff markers and Undo toast as Claude and Codex. Unlike in-app terminal tokens, it survives project switches. BashCut deletes the file when it quits; **Settings → Agents outside BashCut** turns it off or issues a new token. Export and OTIO export still wait for approval in the app.

## Debug log

The app, the `bashcut` CLI and `bashcut-mcp` append one line per event to `~/Library/Logs/BashCut/debug.log` (rotated to `debug.1.log` at 5 MB) and mirror it to the unified log under subsystem `app.bashcut`. It records app launch (executable path and build time), project opens with the layer layout and any layer-rule repair, every committed or rejected edit with its operations, layer placement and spill decisions, media import details (`kind`, `hasAudio`, frames), timeline gestures, library panel switches, and every automation request with author, duration and result. Follow it with `tail -f ~/Library/Logs/BashCut/debug.log`. Set `BASHCUT_DEBUG_LOG=0` to disable it; test runners never write to it.
