# Automation: CLI and MCP

BashCut can be driven by agents, scripts and the built-in terminal dock. This guide covers how they connect,
and every command they can run. The design rationale is in
[05 — Agent integration](../specs/05-agent-integration.md).

## Overview

The app runs one local JSON-RPC server on a Unix socket. Two thin clients talk to it:

- `bashcut`, a command-line tool bundled with the app.
- `bashcut-mcp`, a stdio MCP server built with the official MCP Swift SDK. It exposes each command as a
  tool named `bashcut_<group>_<command>` (for example `bashcut_timeline_get`).
  Every result is the tool's text: string results as they are, everything else as compact JSON. There is no
  `structuredContent` (the SDK re-decodes it slowly, and compact text is also fewer tokens for the agent).
  While BashCut runs, the tool list also has one `bashcut_action_<action id>` tool per installed plugin action,
  with the action's parameters as its input schema; calling it is `plugins run <action> --params …`.

Both clients forward to the same handlers the UI uses. Edits go through the validated `EditOperation` and
history path, so permissions, revision checks, audit records and undo behave the same whether a change comes
from a click, the CLI or MCP.

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
- **Switching projects.** Tabs stay open when the project changes, also when their own agent creates or opens
  one (before, the switch closed the tab mid-task). Every token, in-app or external, must then read the new
  project (`context get`, `timeline get` or `project get`) before its next edit; until then edits fail with
  "The open project changed to …", so an agent cannot apply what it remembers of the old project. Open
  conversations are bookmarked for the new project too, so **Continue** there resumes them.

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

## Agent kit

The [agent kit](https://github.com/dongnguyenvie/bashcut-agent-kit) is a set of editing skills (footage survey,
beat cuts, audio mix, captions, colour, effects, voiceover…) for Claude Code and Codex. BashCut ships a copy in
`Contents/Resources/AgentKit` (`scripts/bundle-agent-kit.sh`, run by `scripts/run.sh` and the Xcode build, copies
the tracked files of a `bashcut-agent-kit` checkout next to the repo, or `$BASHCUT_AGENT_KIT`). **Settings → Agents**
and `agent status` / `agent setup` manage it.

- **Finding it.** When Claude Code or Codex is installed but lacks the kit (or has an older one), the agent dock
  shows a banner: **Set Up** (or **Update**) runs `agent setup` for each of them, **Details…** opens Settings →
  Agents (`ui action show.agent-kit`; also Agent › Agent Skills… and ☰), and **Later** (`ui action
  agent.kit-later`) hides it until BashCut has a newer kit.

- **Kit updates.** Settings → Agents checks the kit's signed releases (`releases.json` on bashcut-agent-kit's
  `main`) and offers **Download & Update** (`agent kit-check`, `agent kit-update`; the update asks for approval).
  BashCut installs a release only over HTTPS from GitHub, with a first-party ed25519 signature checked before the
  download and the SHA-256 after it, into `~/Library/Application Support/BashCut/agent-kits/<version>`. The newer
  of that download and the built-in kit is used; a chosen folder is never updated. After installing, Claude Code
  and Codex are refreshed where the kit is set up. Claude Code caches the plugin per version, so its row shows
  "Older kit set up" until **Update** runs.

- **BashCut's tabs** load it by default (`agent setup in-app`, `--remove` to stop). The built-in kit is copied to
  `~/Library/Application Support/BashCut/agent-kit`. Claude tabs get a skills-only plugin
  (`agent-kit-claude`, passed with `--plugin-dir`; the tab already has the BashCut MCP server). Codex tabs see
  the skills as links in `agent-workspace/.agents/skills`, which holds only the kit's skills.
- **Another kit folder** (a checkout being worked on): **Choose…** in Settings or `agent setup in-app --kit
  /abs/path` (`--kit built-in` to go back). It is used in place, so edits show up in the next tab.
- **Claude Code and Codex outside BashCut**: `agent setup claude` adds the kit as the `bashcut-agent-kit`
  marketplace and installs the `bashcut` plugin (skills and MCP server); `agent setup codex` links the skills
  into `~/.agents/skills` (never over a folder that is not a link) and runs `codex mcp add bashcut`. `--remove`
  undoes either. From the CLI this asks for approval like an export, because it changes the agents' own
  configuration.
- **Configuration folders.** Claude Code and Codex may keep their login and settings elsewhere
  (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`), often set in a shell profile that BashCut does not see when it starts
  from Finder. Each folder comes from Settings (`--claude-config-dir`, `--codex-home`; `default` detects
  again), else BashCut's environment, else the login shell (`$SHELL -ilc`, read once at launch), else
  `~/.claude` / `~/.codex`. The result is used for setup, for the tabs' environment and for finding their
  sessions to resume. `agent status` shows each folder and where it came from.

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

## Version and updates

`app version` returns this copy's version, build, plugin API and how it was installed: `homebrew`, `direct` (a zip
or dmg), `app-store` (App Store or TestFlight) or `development` (`scripts/run.sh`). `app update-check` asks GitHub
for the latest release (`api.github.com/repos/<owner>/<repo>/releases/latest`, from `BCRepositoryURL`) and returns
`updateAvailable`, the `latest` release and `update`: the Homebrew command or the release page. It never installs
anything, and App Store copies are not checked.

The UI does the same in **BashCut › Check for Updates…** (`ui action show.updates`, also ☰ and Settings ›
General). Homebrew and downloaded copies also check once a day when a project opens (**Settings › General ›
Check for BashCut updates daily**). A newer release then opens Software Update by itself, once per launch, as the
`updates` sheet with the options `skip` (**Skip This Version**, `ui action app.update-skip`: no reminders until a
newer release), `later` (**Remind Me Later**, `ui action app.update-later`: not before the next day) and `close`.
Until a release is skipped, ☰ shows a dot and an **Update to BashCut …** item. The last answer is remembered, so the
prompt and the dot work without asking GitHub at every launch. `ui action show.about` opens About BashCut.

Development builds (`scripts/run.sh`) check only on demand. To try the prompt, start one with
`BASHCUT_UPDATE_FEED=<release.json>` (a file shaped like GitHub's release JSON: `tag_name`, `html_url`,
`published_at`, `body`; read instead of GitHub) and `BASHCUT_UPDATE_INSTALL=homebrew` or `direct`, for example
`open --env BASHCUT_UPDATE_FEED=/tmp/release.json --env BASHCUT_UPDATE_INSTALL=homebrew build/BashCut.app`.
Release builds ignore both.

## Commands

Every command is declared once as a `CommandSpec` in `BashCut/Core/Automation/CommandCatalog.swift`: its name,
permission mode, parameters (type, range, choices, default and CLI binding) and whether it runs immediately,
as a background job or after in-app approval. The socket validates every request against its spec before the
handler runs, so the CLI and MCP return identical errors. The CLI parser, the MCP tool list and
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
| `ui` | Required | Controls selection, playback, panels and dialogs; dialog responses can also apply edits |
| `edit` | Required | Changes the project as one undoable, visible step; edits also need the current `--base-rev` |
| `privileged` | Required | Waits for the user to approve in the app (see [Exports and approval](#exports-and-approval)) |

### Command reference

**[Command reference](../reference/commands.md)** lists every command with its usage, mode, how it runs, MCP
tool name and parameters (types, ranges, choices, defaults). It is generated from the catalog
(`scripts/update-commands.sh`) and a test fails when it is out of date, so it never misses a command.

- Plugin actions: agents get the workflow in their instructions (list → select → run → `jobs status`), and the
  session context lists every installed action with its `when` condition and parameters. Plugin actions also
  appear in `ui actions` and run with `ui action <id>`. See [Writing plugins](plugins.md#commands).
- `ui frame [frame]` renders the viewer picture to a PNG for agents to look at; it never moves the playhead.

#### Allowed values

| Parameter | Values |
|---|---|
| `timeline get --format` | `json` (default), `text` |
| `project create --canvas` | `portrait` (default), `landscape`, `square` |
| `project create --resolution` | `720`, `1080` (default), `2160` (short side) |
| `project create --fps` | `29.97` (default), `30`, `24`, `60` |
| `project create --language` | A language tag; defaults to `vi` |
| `project create --dir` | An existing absolute folder; defaults to the projects folder (`project folder`, `~/Movies/BashCut` unless changed), made on first use |
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

Add one `CommandSpec` to the catalog and one `handle`/`handleAuthored` registration in `ProjectDocument`, then
run `scripts/update-commands.sh`. Debug builds assert that every spec has a handler, `CommandSpecTests` checks
names, schemas and CLI bindings, and `CommandReferenceTests` fails until the reference is regenerated. If
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

Use `timeline apply ... --dry-run` (MCP parameter `dryRun: true`) to validate the same batch on a copy.
It checks the base revision, locks and project invariants, but changes no revision, undo history, files,
preview or plugin hooks. The response has `dryRun: true`, current `rev`, `projectedRev`, predicted `duration`
and `previousDuration` in frames, `changedItems`, `changedTracks`, `addedTracks` and `removedTracks`.
Changed item IDs include additions, deletions, property changes and moves. A live edit token is still required.
The preview does not reserve a revision; apply the batch with the same base revision and handle stale errors.


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
  `upsertTransition`, `deleteTransition`, `addColorLUT`, `deleteColorLUT` and `setFormat` (the canvas size; the
  `project format` command and the toolbar's format menu use it). The agent instructions
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

## Library items

The library panels (Audio, Text, Stickers, Effects, Transitions, Filters, Voice) are collections of items with one
model (#66). An item has an `id`, a `kind` (`audio`, `text-preset`, `sticker`, `effect-preset`, `transition-preset`,
`look`, `voice`), a `name`, `tags`, a `pack`, `source` and `license`, `createdBy` (user, agent or plugin),
`version`, usage, an optional copied `file` and `preview`, and `params` with what the kind needs.

Items come from four scopes; when the same ID is in several, the first wins, and `scope:id` picks one:

| Scope | Where | Writable |
|---|---|---|
| `project` | `.bashcut/library/library.json` and `files/` in the project folder; travels with the project | yes |
| `user` | `~/Library/Application Support/BashCut/Library` (this Mac) | yes; agents need approval |
| `plugin` | Shipped by a plugin | no |
| `built-in` | Shipped with BashCut | no |

- `bashcut library list [--panel text] [--kind sticker] [--tag food] [--scope user] [--created-by agent] [--pack X]
  [--query word]` lists items with their usage; `library get <id>` adds the earlier versions and the file path.
- `bashcut library add --kind sticker --name Fire --params '{"emoji":"🔥"}' [--tags food,hot] [--pack Food]
  [--file f.png] [--scope project|user]` saves a new item (the ID comes from the name unless `--id` is given).
- `bashcut library update <id> [--name] [--tags] [--params] [--file] …` saves a new version; the old one stays in
  `history`. Built-in and plugin items are read-only: `--as <new-id> [--into user]` saves an improved copy with
  `basedOn` pointing at the original. Nothing is overwritten silently.
- `bashcut library remove <id>` removes a project or user item and its files.
- `bashcut library place <id> [--at-frame] [--duration] [--track] [--text] --base-rev N` adds a text preset or emoji
  sticker as a text item, or a look as an adjustment. `library apply <id> [--item] --base-rev N` sets a text preset,
  an effect preset's properties (`params.patch`) or a look's grade on an existing item. Both count a use.
- `bashcut library stats [--panel]` reports usage, the saved items nobody used, and duplicates (same kind, params
  and file), to prune or merge.
- `bashcut library export-pack --pack Food --output ~/Food` writes a pack folder (`pack.json` and `files/`);
  `library import-pack <folder|zip> [--scope user] [--replace]` adds one. IDs already there are refused unless
  `--replace` saves them as new versions.

Agents' `add`, `update`, `remove` and `import-pack` in the `user` scope wait for the user's approval, like exports;
the project scope follows the normal edit rules.

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

The dock no longer has a model-API tab (removed 2026-10-04): it generated a script or one timeline proposal per
request, without tools, the agent kit or a look at the result, which is not enough to finish a video. To use a
model with API billing, use a Codex tab (it passes `OPENAI_API_KEY` through) or log the Claude CLI in with a Console
account (Claude tabs never receive `ANTHROPIC_API_KEY`); both get the agent kit and the full command set. See the
[Claude CLI reference](https://code.claude.com/docs/en/cli-reference) and the
[Codex CLI reference](https://developers.openai.com/codex/cli/reference).

## Debug log

The app, the `bashcut` CLI and `bashcut-mcp` append one line per event to `~/Library/Logs/BashCut/debug.log`
(rotated to `debug.1.log` at 5 MB) and mirror it to the unified log under subsystem `app.bashcut`. It records:

- app launch, with the executable path and build time;
- project opens, with the layer layout and any layer-rule repair;
- every committed or rejected edit with its operation name, and layer placement and spill decisions;
- media import details (`kind`, `hasAudio`, frames), proxy queueing, timeline gestures and library panel
  switches;
- every automation request with its author, duration and success/failure code, and auto-approved exports.

Sensitive command parameters are marked in `CommandParameter` and replaced with `[redacted]`; unknown input
fields are redacted too. Chat text, option values, arbitrary plugin parameters and operation payloads are not
persisted. RPC results and error messages are omitted because they may echo secrets. The CLI logs the parsed
command name, never raw argv. Log files are created with `0600`, existing active files are restricted on write,
and unified-log messages use private visibility. Open uses `O_NOFOLLOW` and append mode. Handles are retained;
a stable `.lock` file protects append and rotation across processes, and writers reopen when the pathname's
inode changes. Release builds disable logging by default; use `BASHCUT_DEBUG_LOG=1` to enable it explicitly,
or `BASHCUT_DEBUG_LOG=0` to disable it in Debug. `BASHCUT_DEBUG_LOG_PATH` overrides the file destination.

```sh
tail -f ~/Library/Logs/BashCut/debug.log
```

Set `BASHCUT_DEBUG_LOG=0` to turn it off. Test runners never write to it.

### Error responses

CLI failures write `{"error":{"code":-32002,"message":"…","data":{"expected":1,"actual":2}}}` to stderr
and leave stdout empty. `data` is optional. MCP returns the same object in `structuredContent` and JSON text,
with `isError: true`. Error messages are intended for the requesting client and are omitted from debug logs.

| Condition | RPC code | CLI exit status |
|---|---:|---:|
| Stale revision / project read required | -32002 | 75 |
| Editor busy | -32003 | 69 |
| App/socket unavailable | -32000 | 69 |
| Missing or revoked token | -32001 | 77 |
| Invalid request, command or arguments | -32600 / -32601 / -32602 | 64 |
| Malformed response | -32700 | 65 |
| Internal / other failure | -32603 / other | 70 |

Stale revision errors include `data.expected` and `data.actual`. Refresh the project before constructing a new
edit; do not blindly replay after a timeout because a timed-out mutation may already have completed.
