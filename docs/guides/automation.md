# Automation: CLI, MCP and model APIs

BashCut can be driven by agents, scripts and the built-in terminal dock. This guide covers how they connect,
every command they can run, and how the in-app model API mode works. The design rationale is in
[05 — Agent integration](../specs/05-agent-integration.md).

## Overview

The app runs one local JSON-RPC server on a Unix socket. Two thin clients talk to it:

- `bashcut`, a command-line tool bundled with the app.
- `bashcut-mcp`, a stdio MCP server built with the official MCP Swift SDK. It exposes each command as a
  tool named `bashcut_<group>_<command>` (for example `bashcut_timeline_get`).
  While BashCut runs, the tool list also has one `bashcut_action_<action id>` tool per installed plugin action,
  with the action's parameters as its input schema; calling it is `plugins run <action> --params …`.

Both clients forward to the same handlers the UI uses. Edits go through the validated `EditOperation` and
history path, so permissions, revision checks, audit records and undo behave the same whether a change comes
from a click, the CLI, MCP or a model API.

### Socket protocol

- The socket is `~/Library/Application Support/BashCut/automation.sock`; set `BASHCUT_SOCKET` to use
  another path. The folder is `0700` and the socket `0600`. Run one BashCut instance per socket.
- Each connection carries one newline-delimited JSON-RPC 2.0 request with `id`, `method`, `params` and an
  optional `token`. Messages are limited to 8 MiB, with a 10-second I/O timeout.
- Metadata-only audit records go to `~/Library/Application Support/BashCut/audit.jsonl`. Request contents and
  credentials are never recorded.
- This is a local automation service, not a security boundary against other software already running as the
  same user.

Common error codes:

| Code | Meaning |
|---|---|
| `-32001` | The command needs a live session token |
| `-32002` | Stale revision: re-read the timeline and retry |
| `-32003` | Busy: a dialog is open, another approval is pending, or the action is not available now |
| `-32601` | Unknown command |
| `-32602` | Invalid or missing parameters, or a rejected edit |

## Terminal dock

Open a terminal with **Agent → + → Claude terminal / Codex terminal / Shell terminal**. Each tab is a real
SwiftTerm terminal. Claude and Codex use your installed CLI and its existing login.

- **Workspace.** Choose a workspace before opening a tab. Claude runs in the workspace folder. Codex runs in
  `~/Library/Application Support/BashCut/agent-workspace`; the project path and project knowledge reach it
  through the session context.
- **Resuming.** When BashCut has found the last Claude or Codex conversation for the project, the dock offers
  **Continue Claude/Codex** or **New conversation**. You never see or type session IDs.
- **Codex defaults.** Codex starts idle on `gpt-5.6-luna` with low reasoning effort, under a named permission
  profile that extends its workspace profile with the BashCut folder and the exact BashCut socket. It does not
  get a broad socket allowlist.
- **Context.** Context and quick actions paste text into the terminal for you to review before pressing
  Enter. The ⌘K popover can attach the current viewer frame: BashCut renders a bounded PNG into
  `.bashcut/agent-context`, keeps the ten newest frames and passes the absolute path to the terminal.
- **Switching projects.** Opening a different project closes the open sessions and revokes their tokens.

Each child process gets a filtered environment plus:

- `BASHCUT_SOCKET`, `BASHCUT_PROJECT` and an in-memory `BASHCUT_SESSION_TOKEN`;
- a `PATH` that includes the bundled `bashcut` and `bashcut-mcp`;
- for Claude and Codex, a temporary MCP server definition on the command line. No MCP config or token is
  written into the project.

Claude does not inherit `ANTHROPIC_API_KEY`, so it uses your CLI login. Shell tabs edit as the user; Claude and
Codex tabs have their own authors. Closing a tab revokes its token. Keep tokens out of scripts, logs and
project files.

**Settings → Allow agent timeline edits** is on by default. When it is off, Claude and Codex tabs get no
token, so they can read and point at things but cannot edit.

## Agents outside BashCut

Claude Code in another terminal, scripts and other MCP clients need no copied token. While BashCut runs, it
writes a fresh token to `~/Library/Application Support/BashCut/automation-token` with mode `0600`, next to the
`0600` socket, so the file grants nothing beyond what can already open the socket. The CLI and `bashcut-mcp`
read it whenever `BASHCUT_SESSION_TOKEN` is not set.

- Edits are attributed to `agent` and get the same change markers and Undo toast as Claude and Codex.
- Unlike in-app terminal tokens, this token survives project switches.
- BashCut deletes the file when it quits. **Settings → Agents outside BashCut** turns it off or issues a new
  token.
- Exports still wait for your approval in the app.

## Commands

Every command is declared once as a `CommandSpec` in `BashCut/Core/Automation/CommandCatalog.swift`: its name,
permission mode, parameters (type, range, choices, default and CLI binding) and whether it runs immediately,
as a background job or after in-app approval. The socket validates every request against its spec before the
handler runs, so the CLI, MCP and model APIs return identical errors. The CLI parser, the MCP tool list and
schemas, and the agent instructions are all generated from these specs.

Print every usage line (also shown by `bashcut --help`) with:

```sh
bashcut help
```

Add `--format text` to any command to print string results without JSON quoting. MCP tools take the same
parameter names as the JSON-RPC `params` (`baseRev`, `atFrame`, …); the CLI spells them as options
(`--base-rev`, `--at-frame`). Relative paths given to the CLI are made absolute against its working
directory.

### Permission modes

| Mode | Token | Behavior |
|---|---|---|
| `read` | Not needed | Reads state; changes nothing |
| `ui` | Not needed | Changes what the app shows (selection, playhead, panels, dialogs), never the project |
| `edit` | Required | Changes the project as one undoable, visible step; edits also need the current `--base-rev` |
| `privileged` | Required | Waits for the user to approve in the app (see [Exports and approval](#exports-and-approval)) |

### Command reference

All 62 commands, grouped by purpose. Prefix each with `bashcut`. Arguments in brackets are optional.

#### Read

| Command | Mode | Summary |
|---|---|---|
| `context get` | read | Project path, revision, playhead and selection |
| `project get` | read | The whole open project document |
| `project recents` | read | Recently opened projects (Welcome screen) |
| `timeline get [--format <format>]` | read | Revision, format, tracks (IDs and roles), `luts`, and the built-in and custom `looks` and `styleKits`; `json` (default) or compact `text` |
| `schema get` | read | The JSON Schema of `project.bashcut.json`: every field, type and range ([project.schema.json](../reference/project.schema.json)) |
| `media list` | read | Project media, each with its `proxy` state |
| `review run` | read | Structural timeline review: timeline structure and tagged speech coverage, not measured loudness or silence |
| `captions export` | read | Captions as SubRip text on stdout |
| `export status` | read | Export state, queue with job IDs, and the most recent receipt |
| `plugins list` | read | Installed plugins, their providers and project provider preferences, plus catalog diagnostics |
| `plugins health [<plugin>]` | read | Run plugin health checks (Plugins sheet, Check Health); all plugins by default |
| `doctor run` | read | Run the Doctor checks (workspace, tools, plugins) |
| `knowledge get` | read | The project memo and project skills shared with the agents |

#### Project

| Command | Mode | Summary |
|---|---|---|
| `project create --name <name> --dir <directory> [--footage <footage>] [--canvas <canvas>] [--resolution <resolution>] [--fps <fps>] [--language <language>] [--save-current] [--discard-current]` | edit | Create a project folder like the New Project wizard and open it |
| `project open <path> [--save-current] [--discard-current]` | edit | Open a `project.bashcut.json` or its folder |
| `project save` | edit | Save the open project to disk |
| `edl import <path> [--save-current] [--discard-current]` | edit | Convert a legacy `edl.json` into `project.bashcut.json` beside it and open it |

`project open`, `project create` and `edl import` never show the discard dialog. When the open project has
unsaved changes they fail unless you pass `--save-current` or `--discard-current`. In-app agent tabs close
when another project opens; agents outside BashCut keep access.

#### Edit

| Command | Mode | Summary |
|---|---|---|
| `timeline apply <ops.json> --base-rev <baseRev> [--label <label>]` | edit | Atomically apply validated timeline operations as one undo step |
| `timeline undo --base-rev <baseRev>` | edit | Undo one timeline action |
| `timeline redo --base-rev <baseRev>` | edit | Redo one timeline action |
| `timeline move <item> --track <track> --at-frame <atFrame> --base-rev <baseRev>` | edit | Move an item and its linked partner; an occupied range spills onto a free or new layer |
| `timeline close-gap --at-frame <atFrame> [--track <track>] --base-rev <baseRev>` | edit | Delete the empty gap containing a frame (main layer by default): later clips on that layer move left with their linked sound |
| `clip speed [item] --speed <x> [--keep-duration] [--preserve-pitch on\|off] --base-rev N` | edit | Constant speed like Inspector › Speed; by default the length follows the speed and later clips move |
| `layers set <track> [--hidden on\|off] [--muted on\|off] [--locked on\|off] --base-rev <baseRev>` | edit | The layer header switches: hide a visual layer, mute an audio layer, lock any layer (a locked layer refuses edits) |
| `layers add --kind <kind> [--role <role>] [--name <name>] --base-rev <baseRev>` | edit | Add an empty `video`, `adjustment`, `text` or `audio` layer; the role can be `overlay`, `captions`, `music`, `sfx` and so on, never `main` |
| `adjustment add [--look <look>] [--exposure <n>] [--contrast <n>] [--saturation <n>] [--lut-strength <n>] [--lut <lut>] [--at-frame <atFrame>] [--duration <duration>] [--track <track>] --base-rev <baseRev>` | edit | Add an adjustment item: a color grade on every layer below it for its range (the selected clip's range, else 3 seconds at the playhead). Starts from the look; the grade options override it. Adds an adjustment layer when needed |
| `style apply <kit> --base-rev <baseRev>` | edit | Apply a built-in or custom style kit as one undo step: a full-length adjustment with the kit's look (replacing an earlier kit's) and the kit's preset on captions |
| `looks save <id> --title <title> [--item <item>] [grade options] --base-rev <baseRev>` | edit | Save a custom look in the project, starting from an item's grade when given; saving an existing custom ID replaces it |
| `looks delete <id> --base-rev <baseRev>` | edit | Delete a custom look (refused while a custom kit uses it) |
| `style save <id> --title <title> --look <look> [--caption-preset <preset>] --base-rev <baseRev>` | edit | Save a custom style kit in the project |
| `style delete <id> --base-rev <baseRev>` | edit | Delete a custom style kit |
| `media import <path> [--kind <kind>] [--place] [--track <track>] [--at-frame <atFrame>] --base-rev <baseRev>` | edit | Add a media file; with `--place`, also put it on a layer like the Import button |
| `media place --media <media> [--track <track>] [--at-frame <atFrame>] --base-rev <baseRev>` | edit | Place project media on a layer (main by default), with linked sound on a dialogue layer |
| `media proxy [<media>] [--force]` | edit | Queue preview proxies for heavy video, or for one media item |
| `storage get` | read | What BashCut keeps on disk (Settings › Storage) with sizes and paths |
| `storage clear <plugin-cache\|plugin-data\|registry\|proxies> [--plugin <id>]` | edit | Delete what can be made or downloaded again; `plugin-data` needs `--plugin` and means setting the plugin up again |
| `captions import <text-file> --base-rev <baseRev> [--replace]` | edit | Import UTF-8 SubRip captions as one undoable edit |
| `luts import <path> [--name <name>] --base-rev <baseRev>` | edit | Check a `.cube` LUT, copy it into the project's `luts` folder and add it (Filters panel) |
| `knowledge memo <text-file>` | edit | Replace the project memo (`.bashcut/agent-memory.md`) |
| `knowledge skill <name> <text-file>` | edit | Write a project skill's `SKILL.md`, creating it and sharing it with Claude and Codex if needed |

#### Jobs

| Command | Mode | Summary |
|---|---|---|
| `captions generate --media <media> [--replace] [--provider <provider>]` | edit, job | Transcribe media with a `captions.transcribe` provider and import the captions |
| `beats detect --media <media> [--provider <provider>]` | edit, job | Detect beats in audio media already on the timeline and set its beat grid |
| `voice speak <text> [--takes <takes>] [--at-frame <atFrame>] [--provider <provider>] [--keep-takes]` | edit, job | Synthesize 1–8 takes (default 3) and insert the best one on the Voiceover track |
| `jobs status [<job>]` | read | One job (plugin call or export), or all recent jobs |
| `jobs cancel <job>` | edit | Cancel a queued or running job |

#### Plugins

| Command | Mode | Summary |
|---|---|---|
| `plugins actions` | read | Actions plugins add (menus, toolbar, context menus, panels) with placements, parameter schema and enabled state |
| `plugins run <action> [--params <json>]` | edit, job | Run a plugin action like clicking it; its proposed operations become one undoable edit by `plugin` |

Agents get the plugin workflow in their instructions (list → select → run → `jobs status`), and the session
context lists every installed action with its `when` condition and parameters (ranges and defaults).
| `plugins hooks` | read | Hook subscriptions, recent hook runs and hook edits waiting for review |
| `plugins proposal <id> --decision <apply\|discard>` | edit | Apply or discard an edit a hook proposed |
| `plugins options <plugin>` | read | A plugin's options: schema, scope and current values |
| `plugins option <plugin> --option <option> [--value <value>]` | edit | Set one option (project scope: undoable edit; user scope: this Mac); no value resets it |
| `plugins set <plugin> [--enabled <bool>] [--hooks <bool>]` | edit | Turn a plugin or its hooks off; turning them on and trusting stay with the user |
| `plugins search [query] [--capability <id>] [--refresh]` | read | Search the plugin registry with install status |
| `plugins updates` | read | Installed plugins with a newer compatible registry version |
| `plugins install <plugin> [--version <v>]` | edit | Download and verify a registry plugin, then show the install approval (job; only the user approves) |
| `plugins remove <plugin> [--data]` | edit | Uninstall a plugin from the user or project plugin folder; `--data` also deletes its environments and models |
| `plugins setup <plugin>` | edit | Ask to run a plugin's install recipes again (approval stays with the user; then `jobs status`) |

Plugin actions also appear in `ui actions` and run with `ui action <id>`. See [Writing plugins](plugins.md#commands).

#### Privileged

| Command | Mode | Summary |
|---|---|---|
| `export start --preset <preset> --name <name> [--output-dir <directory>] [--include-srt] [--normalize-audio]` | privileged, approval | Request a background video export |
| `export otio --name <name> [--output-dir <directory>]` | privileged, approval | Request an OpenTimelineIO export |

#### UI

| Command | Mode | Summary |
|---|---|---|
| `ui dialog` | read | The open dialogs (alerts, file panels, sheets), topmost last, with their option IDs |
| `ui respond [<option>] [--path <path>] [--dialog <dialog>]` | ui | Answer the topmost dialog like the user: an option ID or title, or a path for a file panel |
| `ui open <dialog>` | ui | Open a sheet or popover |
| `ui actions` | read | Every editor action (buttons, menu items, shortcuts) with its shortcuts and whether it is enabled now |
| `ui action <action>` | edit | Run an editor action by ID or shortcut, using the same code as the UI |
| `ui view [--zoom <zoom>] [--zoom-anchor <zoomAnchor>] [--snap <snap>] [--safe-area <safeArea>] [--compare <compare>] [--agent-dock <agentDock>] [--reveal <reveal>] [--inspector <inspector>]` | ui | Read the view state, or change zoom, toggles and inspector tab, and scroll the timeline to a frame |
| `ui select [<item>] [--track <track>]` | ui | Select a timeline item (omit it to clear the selection), or a layer with `--track` |
| `ui source <media> [--in <in>] [--out <out>]` | ui | Open media in the source viewer, optionally with in and out frames marked |
| `ui seek <frame>` | ui | Move the viewer to a timeline frame |
| `ui panel <panel>` | ui | Open a library panel in the left rail |
| `ui notify <message>` | ui | Show a short status message in BashCut |

#### Allowed values

| Parameter | Values |
|---|---|
| `timeline get --format` | `json` (default), `text` |
| `project create --canvas` | `portrait` (default), `landscape`, `square` |
| `project create --resolution` | `720`, `1080` (default), `2160` (short side) |
| `project create --fps` | `29.97` (default), `30`, `24`, `60` |
| `project create --language` | A language tag; defaults to `vi` |
| `layers add --kind` | `video`, `adjustment`, `text`, `audio` |
| `adjustment add --look`, `style save --look` | Built-in `original` (default), `vivid`, `muted-film`, `black-white`, or a custom look ID from `timeline get` |
| `style apply <kit>` | Built-in `food-review` (vivid, Bold Outline), `cinematic` (muted film, Cinematic Serif), or a custom kit ID |
| Grade options | `--exposure` −10…10, `--contrast` 0…4, `--saturation` 0…4, `--lut-strength` 0…1 (decimals allowed), `--lut` a LUT ID |
| `style save --caption-preset` | `bold-outline` (default), `cinematic-serif`, `keyword-sticker`, `place-card`, `hook-title`, `chapter-card` |
| `media import --kind` | `video` (default), `audio` |
| `export start --preset` | `tiktok`, `youtube-1080`, `youtube-4k`, `quick-draft`, `prores` |
| `ui open <dialog>` | `new-project`, `export`, `export-report`, `agent-changes`, `review`, `history`, `plugins`, `settings`, `doctor`, `knowledge`, `ask`, `sections`, `external-changes`, `plugin-proposals` |
| `ui panel <panel>` | `media`, `audio`, `text`, `stickers`, `effects`, `transitions`, `filters`, `voice` |
| `ui view --zoom` | 1–600 pixels per second; `--zoom-anchor` is the frame kept in place (the playhead by default) |
| `ui view --snap`, `--safe-area`, `--compare`, `--agent-dock` | `on` / `off` (also `true`/`false`, `yes`/`no`, `1`/`0`) |
| `ui view --inspector` | `video`, `audio`, `text`, `color`, `speed` |

### Adding a command

Add one `CommandSpec` to the catalog and one `handle`/`handleAuthored` registration in `ProjectDocument`. Debug
builds assert that every spec has a handler, and `CommandSpecTests` checks names, schemas and CLI bindings. If
the command mirrors something in the UI, see the parity rule in
[05 — Agent integration](../specs/05-agent-integration.md#ui-parity-rule). The step-by-step checklist is in
[CONTRIBUTING.md](../../CONTRIBUTING.md).

## Editing the timeline

Edit commands need a live session token and the current revision as `--base-rev`. The server rejects stale
revisions, file conflicts, busy operations and active timeline gestures; re-read the timeline and retry. Each
apply is atomic and creates one undo step.

```sh
bashcut context get
bashcut timeline get --format text
bashcut timeline apply /absolute/path/ops.json --base-rev 12 --label 'Trim opening'
bashcut timeline undo --base-rev 13
bashcut timeline redo --base-rev 14
```

### Timeline operations

`ops.json` is an array of up to 1,000 operations:

```json
[
  {"op": "split", "item": "clip-1", "atFrame": 30, "newID": "clip-right"},
  {"op": "setProperties", "item": "clip-right", "patch": {"transform": {"zoom": 1.2}}}
]
```

- **Operations.** `insert`, `delete`, `split`, `trim`, `roll`, `slip`, `move`, `reorder`, `setSpeed`, `setProperties`,
  `setLinkedAudio`, track operations (`addTrack`, `moveTrack`, `setTrackProperties`, `deleteTrack`),
  `setProjectProperties`, `setProviderPreference`, `setBeatGrid`, `upsertSection`, `deleteSection`,
  `upsertTransition`, `deleteTransition`, `addColorLUT` and `deleteColorLUT`. The agent instructions
  (`BashCut/Core/Automation/AgentInstructions.swift`) show an example of each.
- **Frames.** All frames are integers. `atFrame` and `toFrame` are absolute timeline frames; an item's `in` is a
  source frame at that media's FPS.
- **Property patches** replace the top-level keys they supply, so keep existing nested fields when you change
  color, transform or tags.
- **Sections and LUTs** keep stable IDs. A LUT catalog entry uses a project-relative `luts/*.cube` path and a 3D
  size from 2 through 64. Apply it with `setProperties` on `color.lut`, with optional `color.lutStrength` from 0
  through 1.
- **Transitions.** `upsertTransition` takes stable `from`/`to` clip IDs, a kind (`dissolve`, `whip`, `blink`,
  `zoom`, `spin`, `shutter` or `wipe`) and an integer-frame `duration`. The clips must be adjacent on one video
  track. `deleteTransition` restores a hard cut; moving or deleting either clip removes a transition that no
  longer describes a valid cut.
- **Roll.** `{"op": "roll", "item": "ID", "edge": "end", "toFrame": 75}` moves the shared cut with exactly one
  adjacent clip; `edge: "start"` uses the preceding clip. Both clips must stay nonempty and within source
  bounds, and the rest of the track and the total duration stay fixed.
- **Slip.** `{"op": "slip", "item": "ID", "sourceIn": 100}` sets an absolute source start without changing
  timeline position or duration. It rejects text items and source overruns.
- **Rejections.** Invalid render values, unsafe LUT paths, duplicate section boundaries, missing media, source
  overruns and Main overlaps are rejected, and nothing is applied.

Source-viewer insert and overwrite plan a group of these same operations.

### Captions (SubRip)

`bashcut captions import /path/captions.srt --base-rev N` appends cues; `--replace` replaces the caption track
atomically. Stale revisions and malformed files leave existing captions untouched.
`bashcut captions export --format text` writes SRT to stdout without changing the project. The Text library
offers the same import, add, replace and export workflows.

Input is UTF-8, at most 4 MiB and 10,000 cues. BOM, CRLF, multiline text and comma or period milliseconds are
accepted. Timing rounds to the nearest project frame; reversed, out-of-bounds or sub-frame cues are rejected.
Export sorts cues and keeps Unicode text. Paragraph gaps collapse to single line breaks because blank lines
delimit SRT cues. Inline markup stays literal text; rich caption styling lives only in the project format.

## Layers and placement

Layer commands follow the layer rules in [02 — Project format](../specs/02-project-format.md#rules).

```sh
bashcut layers add --kind video --role overlay --name "B-roll 2" --base-rev 12
bashcut media import /path/to/clip.mp4 --place --base-rev 12
bashcut media place --media MEDIA_ID --track TRACK_ID --at-frame 90 --base-rev 13
bashcut timeline move ITEM_ID --track TRACK_ID --at-frame 120 --base-rev 14
```

Track IDs and roles are dynamic: always take them from `timeline get`. `media place` and `timeline move` use
the same planner as the timeline UI. When the range is taken, the clip goes to the next free layer of the same
kind and role, or to a new layer next to the target, and linked sound follows onto a dialogue layer. Both
return the layer actually used. Raw `timeline apply` insert and move operations that would overlap are
rejected.

## Media proxies

Heavy footage (HEVC, a long side above 1920 px, or above 20 Mbit/s) gets a preview proxy when it is imported:
an H.264 copy at most 960 px on the long side, with a keyframe every 10 frames and the original frame times,
written to `.bashcut/proxies/<media id>.mov`. The viewer reads proxies; exports always read the originals.

Proxies are made one at a time as `media.proxy` jobs, and the preview switches to each one as it lands.

- `bashcut media proxy [MEDIA_ID] [--force]` queues them by hand and returns a status per media: `queued`
  (with its job ID), `exists`, `not-needed` or `skipped`. The Media panel's **Create Preview Proxy** menu does
  the same with `--force`.
- `media list` reports each media's `proxy` state: `none`, `queued` or `ready`.

## Dialogs and UI actions

Anything you can click or press in the editor is also a command. Buttons, menu items and shortcuts are
`UIAction` cases (`BashCut/Core/Automation/UIAction.swift`) with an ID, a title and shortcuts; the views bind
to them and `ui action` runs the same code.

```sh
bashcut ui actions                 # every action, its shortcuts and whether it is enabled now
bashcut ui action timeline.split   # by ID
bashcut ui action cmd+b            # or by shortcut: cmd+=, space, i, shift+delete
bashcut ui view --zoom 60 --snap on --inspector color --reveal 300
bashcut ui view --zoom 480 --zoom-anchor 1200   # zoom in on frame 1200, keeping it where it is on screen
bashcut ui action timeline.zoom-fit            # or shift+z: show the whole timeline
bashcut ui action clip.freeze                  # the clip context menu: clip.freeze, clip.change-framing, clip.unlink-audio
bashcut ui action shift+right                  # timeline arrows: left/right step a frame, shift+left/right a second
```

Shortcuts are written as `cmd+shift+z`; modifiers can also be spelled `command`, `option`/`alt`/`opt` and
`control`/`ctrl`. When one shortcut means different things in different places (`space` plays the source viewer
while it is shown), `ui action` picks the one that is available.

Every alert, file panel, sheet and popover is visible to `ui dialog`:

```sh
bashcut ui action project.open     # returns at once with {"started": true}
bashcut ui dialog                  # the open-panel, with its option IDs
bashcut ui respond --path /path/to/project
```

- `ui action` refuses while a dialog is open; answer it first.
- Actions that open an alert or panel (`project.new`, `project.open`, `project.import-media`) return at once
  so you can answer the dialog.
- `ui respond --dialog ID` answers only if that dialog is topmost.
- `ui open` refuses while another dialog is open, and some sheets only open when they apply (for example
  `export` needs a nonempty timeline).
- The export approval and plugin-install sheets offer agents only `deny` or `cancel`. Approving stays with
  the user.

## Jobs

`captions generate`, `beats detect` and `voice speak` call the same `CapabilityService` as the Text, Audio and
Voice panels, so provider resolution, health checks, output confinement and validation are identical.

```sh
bashcut captions generate --media MEDIA_ID --replace
bashcut beats detect --media AUDIO_MEDIA_ID
bashcut voice speak 'Xin chào các bạn' --takes 3 --at-frame 120
bashcut jobs status JOB_ID
bashcut jobs cancel JOB_ID
```

- Each returns `{"job": ID, "state": "running"}` at once. Poll `jobs status ID` until it reports `completed`,
  `failed` or `cancelled`. A completed job's result includes the new `rev`, plus `bpm`/`beats`, or the inserted
  voice `item` with its score and all take scores.
- The result is one undoable edit attributed to the agent, with change markers and the Undo toast.
- `voice speak --keep-takes` inserts nothing and keeps every take in `voiceover/generated`, so you can choose
  one and place it with `media import`.
- `--provider ID` overrides the project preference for one request.
- A capability that is already running (from the UI or another job) is rejected with a retry error.
- Opening another project cancels and clears all jobs.
- Installing plugins, running their dependency recipes, trusting a plugin or turning one on is never available
  through automation. See [Writing plugins](plugins.md).

Jobs move through `queued`, `running`, `completed`, `failed` and `cancelled`. Exports and proxy builds use the
same job center.

## Exports and approval

```sh
bashcut export start --preset quick-draft --name draft-v1 --include-srt --normalize-audio
bashcut export otio --name timeline-v1
bashcut export status
```

`export start` and `export otio` need a live session token. They return at once with an approval request ID,
and the app shows a sheet with the author, preset, output path, caption behavior and normalization choice.
Denying writes nothing. Approving starts the same background pipeline as the Export sheet. Only one privileged
request can wait for approval at a time.

**Settings → Run agent exports without confirmation** is off by default, and no command can change it. When
you turn it on, requests run at once, return `approval: "approved"` and are audited as
`<method>.auto-approved`.

- **Output.** Files go to the project's `render/` folder unless you pass `--output-dir`.
- **Queue.** Each approved export (and each export started in the UI) becomes an `export.start` job. Exports
  render one at a time in request order, from the project as it was when requested. `jobs cancel` stops a
  queued or running export.
- **Status.** `export status` lists the queue with job IDs. While an export runs, its top-level fields (`job`,
  `step`, `progress`, `preset`, `path`, `includedSRT`) describe that export and the previous receipt moves to
  `lastExport`. Otherwise it returns the most recent receipt: path, preset, duration, bytes, cuts, captions and
  companion-SRT state. Poll it after an approved request.
- **Captions.** An export asked to include SubRip writes no `.srt` when the timeline has no captions.
- **Loudness.** `--normalize-audio` needs an installed, healthy `audio.loudness` plugin and runs the two-pass
  target and true-peak workflow. A normalized receipt also includes `lufs`, `truePeakDbTP`,
  `normalizationGainDb` and whether the final measurement was verified; other exports return `lufs: null`.
- **OTIO.** `export otio` writes OpenTimelineIO JSON. It keeps integer-frame timing, source ranges and rates,
  layered overlaps, text generators, section markers, speed effects and BashCut metadata.

## Model APIs

The dock's **API** tab sends requests to a model provider directly instead of through a terminal agent.

- **Providers.** OpenAI Responses, OpenAI-compatible Chat Completions and Anthropic Messages. Enter a base URL
  and the provider's model ID; no model or key is hardcoded.
- **Transport.** HTTPS is required except for local HTTP endpoints, and redirects are refused.
- **Credentials.** **Save connection** stores the API key in the macOS Keychain. Other settings live in
  UserDefaults.

Choose **Script** (Python or Shell) or **Timeline edit**, write a request, and choose whether to include
project context. Generate sends text context and your request to the endpoint; it never uploads original
video. An attached viewer frame is sent through the provider's native image payload, up to 5 MB.

The output is editable before use:

- Scripts can be saved, or run in a new local Shell tab after you confirm.
- Timeline proposals apply as one `model` undo step against the revision they were generated from.
- A new generation clears the old output. Cancelling or switching projects discards in-flight results.

Protocol references: [OpenAI text generation](https://developers.openai.com/api/docs/guides/text),
[Anthropic Messages](https://platform.claude.com/docs/en/api/messages/create),
[Claude CLI reference](https://code.claude.com/docs/en/cli-reference),
[Codex CLI reference](https://developers.openai.com/codex/cli/reference).

## Debug log

The app, the `bashcut` CLI and `bashcut-mcp` append one line per event to `~/Library/Logs/BashCut/debug.log`
(rotated to `debug.1.log` at 5 MB) and mirror it to the unified log under subsystem `app.bashcut`. It records:

- app launch, with the executable path and build time;
- project opens, with the layer layout and any layer-rule repair;
- every committed or rejected edit with its operations, and layer placement and spill decisions;
- media import details (`kind`, `hasAudio`, frames), proxy queueing, timeline gestures and library panel
  switches;
- every automation request with its author, duration and result, and auto-approved exports.

```sh
tail -f ~/Library/Logs/BashCut/debug.log
```

Set `BASHCUT_DEBUG_LOG=0` to turn it off. Test runners never write to it.
